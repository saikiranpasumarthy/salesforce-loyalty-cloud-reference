/**
 * @description Core service for all loyalty member enrollment paths.
 *
 * ENTRY POINTS:
 *   - enrollNewMember       : Web registration form (new Contact + new LPM)
 *   - enrollExistingMember  : "Join Rewards" CTA for authenticated users (LPM only)
 *
 * FLOW FOR enrollNewMember:
 *   1. Validate request fields
 *   2. Check for duplicate Contact (email + phone)
 *   3. ContactMatchService.matchOrCreateContact → get Contact Id
 *   4. Call LC Individual Member Enrollment API
 *   5. Update Contact fields (Has_Loyalty__c, Loyalty_Member_Id__c, etc.)
 *   6. Publish Loyalty_Enrollment_Event__e platform event
 *   7. Return EnrollmentResponse with LPM Id and Loyalty Id
 *
 * All LC API calls are made via LoyaltyAPIClient (no Http.send() here).
 * All DML is performed here — not in the controller.
 */
public with sharing class LoyaltyEnrollmentService {

    private final LoyaltyAPIClient     apiClient;
    private final ContactMatchService  matchService;

    public LoyaltyEnrollmentService() {
        this.apiClient    = new LoyaltyAPIClient();
        this.matchService = new ContactMatchService();
    }

    @TestVisible
    private LoyaltyEnrollmentService(LoyaltyAPIClient apiClient, ContactMatchService matchService) {
        this.apiClient    = apiClient;
        this.matchService = matchService;
    }

    /**
     * @description Enrolls a brand-new member — creates Contact if not found, then creates LPM.
     */
    public EnrollmentResponse enrollNewMember(EnrollmentRequest req) {
        req.validate();
        checkDuplicateMember(req.email, req.phone);

        // Step 1: Match or create Contact
        ExternalProfileDTO profile = new ExternalProfileDTO();
        profile.email        = req.email;
        profile.phone        = req.phone;
        profile.firstName    = req.firstName;
        profile.lastName     = req.lastName;
        profile.sourceSystem = req.enrollmentSource;

        Id contactId = matchService.matchOrCreateContact(profile);

        // Step 2: Call LC enrollment API
        Map<String, Object> apiResp = callEnrollmentAPI(req);
        Map<String, Object> lpm = (Map<String, Object>) apiResp.get('loyaltyProgramMember');

        String lpmId      = (String) lpm.get('id');
        String loyaltyId  = (String) lpm.get('membershipNumber');
        String tier       = (String) lpm.get('currentTierName');

        // Step 3: Update Contact with loyalty fields
        updateContactLoyaltyFields(contactId, lpmId, loyaltyId, req.memberType, req);

        // Step 4: Publish platform event for SFMC welcome email trigger
        publishEnrollmentEvent(contactId, lpmId, loyaltyId, req.memberType, req.enrollmentSource);

        return EnrollmentResponse.ok(contactId, Id.valueOf(lpmId), loyaltyId, tier);
    }

    /**
     * @description Enrolls an existing SFSC Contact in the loyalty program.
     *              No Contact creation — only creates the LPM and updates Contact flags.
     *
     * @throws LoyaltyEnrollmentException (DUPLICATE_MEMBER) if Contact already has an LPM
     */
    public EnrollmentResponse enrollExistingMember(Id contactId, String memberType) {
        Contact c = [
            SELECT Id, FirstName, LastName, Email, Phone,
                   Has_Loyalty__c, Loyalty_Member_Id__c
            FROM   Contact
            WHERE  Id = :contactId
            LIMIT  1
        ];

        if (c.Has_Loyalty__c) {
            throw new LoyaltyEnrollmentException(
                'Contact is already enrolled in the loyalty program',
                LoyaltyEnrollmentException.EnrollmentErrorCode.DUPLICATE_MEMBER
            );
        }

        EnrollmentRequest req = buildEnrollmentRequest(c, memberType);
        Map<String, Object> apiResp = callEnrollmentAPI(req);
        Map<String, Object> lpm = (Map<String, Object>) apiResp.get('loyaltyProgramMember');

        String lpmId     = (String) lpm.get('id');
        String loyaltyId = (String) lpm.get('membershipNumber');
        String tier      = (String) lpm.get('currentTierName');

        updateContactLoyaltyFields(contactId, lpmId, loyaltyId, memberType, req);
        publishEnrollmentEvent(contactId, lpmId, loyaltyId, memberType, 'SERVICE_CLOUD');

        return EnrollmentResponse.ok(contactId, Id.valueOf(lpmId), loyaltyId, tier);
    }

    /**
     * @description Checks whether a Contact already exists with this email or phone.
     *              Throws LoyaltyEnrollmentException(DUPLICATE_MEMBER) if found and has LPM.
     */
    public void checkDuplicateMember(String email, String phone) {
        Contact byEmail = matchService.findContactByEmail(email);
        if (byEmail != null && byEmail.Has_Loyalty__c) {
            throw new LoyaltyEnrollmentException(
                System.Label.Loyalty_Duplicate_Member_Email,
                LoyaltyEnrollmentException.EnrollmentErrorCode.DUPLICATE_MEMBER
            );
        }

        if (String.isNotBlank(phone)) {
            Contact byPhone = matchService.findContactByPhone(phone);
            if (byPhone != null && byPhone.Has_Loyalty__c) {
                throw new LoyaltyEnrollmentException(
                    System.Label.Loyalty_Duplicate_Member_Phone,
                    LoyaltyEnrollmentException.EnrollmentErrorCode.DUPLICATE_MEMBER
                );
            }
        }
    }

    /**
     * @description Assembles the LC API enrollment request from Contact and member type.
     */
    public EnrollmentRequest buildEnrollmentRequest(Contact c, String memberType) {
        Loyalty_Program_Config__mdt cfg = [
            SELECT Program_Name__c FROM Loyalty_Program_Config__mdt
            WHERE DeveloperName = 'Default' LIMIT 1
        ];

        EnrollmentRequest req = new EnrollmentRequest();
        req.firstName    = c.FirstName;
        req.lastName     = c.LastName;
        req.email        = c.Email;
        req.phone        = c.Phone;
        req.memberType   = memberType;
        req.programName  = cfg.Program_Name__c;
        return req;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private Map<String, Object> callEnrollmentAPI(EnrollmentRequest req) {
        Map<String, Object> payload = new Map<String, Object>{
            'associatedContactId'  => '',
            'membershipNumber'     => '',
            'memberStatus'         => 'Active',
            'memberType'           => req.memberType,
            'loyaltyProgramName'   => req.programName,
            'enrollmentDate'       => String.valueOf(Date.today()),
            'contactDetails' => new Map<String, Object>{
                'firstName' => req.firstName,
                'lastName'  => req.lastName,
                'email'     => req.email,
                'phone'     => req.phone
            }
        };

        if (req.dobMonth != null) payload.put('dobMonth', req.dobMonth);
        if (req.dobDay   != null) payload.put('dobDay',   req.dobDay);

        return apiClient.post('/individual-member-enrollments', JSON.serialize(payload));
    }

    private void updateContactLoyaltyFields(
        Id contactId, String lpmId, String loyaltyId, String memberType, EnrollmentRequest req
    ) {
        Contact c = new Contact(
            Id                    = contactId,
            Has_Loyalty__c        = true,
            Loyalty_Member_Id__c  = loyaltyId,
            Loyalty_Member_Type__c = memberType
        );
        if (req.dobMonth != null) c.DOB_Month__c = req.dobMonth;
        if (req.dobDay   != null) c.DOB_Day__c   = req.dobDay;
        if (req.proLicenseNumber != null) c.Pro_License_Number__c = req.proLicenseNumber;
        if (req.proLicenseExpiry != null) c.Pro_License_Expiry__c = req.proLicenseExpiry;
        if (req.schoolName       != null) c.School_Name__c        = req.schoolName;
        if (req.graduationDate   != null) c.Graduation_Date__c    = req.graduationDate;
        update c;
    }

    private void publishEnrollmentEvent(
        Id contactId, String lpmId, String loyaltyId, String memberType, String source
    ) {
        Loyalty_Enrollment_Event__e evt = new Loyalty_Enrollment_Event__e(
            Contact_Id__c       = contactId,
            LPM_Id__c           = lpmId,
            Loyalty_Id__c       = loyaltyId,
            Member_Type__c      = memberType,
            Enrollment_Source__c = source
        );
        EventBus.publish(evt);
    }
}
