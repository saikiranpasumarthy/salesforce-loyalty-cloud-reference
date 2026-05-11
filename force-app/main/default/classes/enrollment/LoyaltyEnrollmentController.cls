/**
 * @description AuraEnabled controller backing the loyaltyEnrollmentForm and loyaltyJoinCta LWC components.
 *
 * DESIGN RULES:
 *   - No DML or HTTP callouts here — all delegated to LoyaltyEnrollmentService.
 *   - Always return a typed wrapper with success/errorMessage (never throw to LWC).
 *   - Input validation in LoyaltyEnrollmentService; controller only translates parameters.
 */
public with sharing class LoyaltyEnrollmentController {

    /**
     * @description Enrolls a new member from the enrollment form.
     *              Called by loyaltyEnrollmentForm on submit.
     *
     * @return EnrollmentResponse with loyaltyId and tier on success; errorMessage on failure
     */
    @AuraEnabled
    public static EnrollmentResponse enrollMember(
        String firstName,
        String lastName,
        String email,
        String phone,
        String memberType,
        Integer dobMonth,
        Integer dobDay
    ) {
        try {
            EnrollmentRequest req = new EnrollmentRequest();
            req.firstName        = firstName;
            req.lastName         = lastName;
            req.email            = email;
            req.phone            = phone;
            req.memberType       = memberType;
            req.dobMonth         = dobMonth;
            req.dobDay           = dobDay;
            req.enrollmentSource = 'WEB';

            // Program name loaded from CMDT inside the service
            Loyalty_Program_Config__mdt cfg = [
                SELECT Program_API_Name__c FROM Loyalty_Program_Config__mdt
                WHERE DeveloperName = 'Default' LIMIT 1
            ];
            req.programName = cfg.Program_API_Name__c;

            LoyaltyEnrollmentService svc = new LoyaltyEnrollmentService();
            return svc.enrollNewMember(req);

        } catch (LoyaltyEnrollmentException e) {
            return EnrollmentResponse.fail(e.getMessage(), e.reason.name());
        } catch (LoyaltyAPIException e) {
            return EnrollmentResponse.fail(
                System.Label.Loyalty_API_Error_Generic,
                'API_ERROR'
            );
        } catch (Exception e) {
            // Log unexpected exceptions but never surface raw stack traces to the LWC
            System.debug(LoggingLevel.ERROR, 'enrollMember unexpected error: ' + e.getMessage());
            return EnrollmentResponse.fail(System.Label.Loyalty_API_Error_Generic, 'INTERNAL_ERROR');
        }
    }

    /**
     * @description Checks whether an email address is already registered as a loyalty member.
     *              Called on email blur in loyaltyEnrollmentForm for real-time duplicate warning.
     *
     * @return True if the email is already associated with a loyalty member
     */
    @AuraEnabled(cacheable=true)
    public static Boolean checkEmailExists(String email) {
        try {
            if (String.isBlank(email)) return false;

            List<Contact> contacts = [
                SELECT Id, Has_Loyalty__c
                FROM   Contact
                WHERE  Email = :email.trim().toLowerCase()
                AND    Has_Loyalty__c = true
                LIMIT  1
            ];
            return !contacts.isEmpty();

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'checkEmailExists error: ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Enrolls an existing authenticated Contact in the loyalty program.
     *              Called by loyaltyJoinCta when a non-loyalty user clicks "Join Rewards".
     */
    @AuraEnabled
    public static EnrollmentResponse enrollExistingContact(Id contactId, String memberType) {
        try {
            LoyaltyEnrollmentService svc = new LoyaltyEnrollmentService();
            return svc.enrollExistingMember(contactId, memberType);

        } catch (LoyaltyEnrollmentException e) {
            return EnrollmentResponse.fail(e.getMessage(), e.reason.name());
        } catch (LoyaltyAPIException e) {
            return EnrollmentResponse.fail(System.Label.Loyalty_API_Error_Generic, 'API_ERROR');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'enrollExistingContact error: ' + e.getMessage());
            return EnrollmentResponse.fail(System.Label.Loyalty_API_Error_Generic, 'INTERNAL_ERROR');
        }
    }
}
