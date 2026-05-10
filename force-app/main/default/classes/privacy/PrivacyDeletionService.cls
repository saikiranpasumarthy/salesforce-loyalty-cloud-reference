/**
 * @description Processes GDPR right-to-erasure and CCPA deletion requests.
 *
 * SAFETY GATES (checked in order):
 *   1. Check for in-progress orders — do not delete if an active order exists
 *   2. Cancel/expire unredeemed vouchers
 *   3. Unenroll from Loyalty Cloud
 *   4. Deactivate SFSC Contact and clear PII fields per retention schedule
 *   5. Log all actions to Privacy_Audit_Log__c
 *
 * PII FIELDS CLEARED ON DELETION (Contact):
 *   Email, Phone, MailingStreet, MailingCity, MailingPostalCode,
 *   DOB_Month__c, DOB_Day__c, Pro_License_Number__c, School_Name__c,
 *   RCC_Card_Number__c, Epsilon_Profile_Id__c
 *   FirstName is set to 'Deleted', LastName preserved as 'User {contactId last 4}'
 *
 * FIELDS RETAINED for compliance:
 *   Has_Loyalty__c, Loyalty_Member_Id__c (for TJ history reference),
 *   Country_Code__c (for reporting), Privacy_Deletion_Date__c (audit)
 *
 * NOT DELETED by this service:
 *   Transaction Journal records (retained for financial compliance)
 *   Order records (retained per commerce policy)
 */
public without sharing class PrivacyDeletionService {

    private final LoyaltyMemberService  memberSvc;
    private final LoyaltyVoucherService voucherSvc;
    private final PrivacyAuditLogger    auditLogger;

    public PrivacyDeletionService() {
        this.memberSvc   = new LoyaltyMemberService();
        this.voucherSvc  = new LoyaltyVoucherService();
        this.auditLogger = new PrivacyAuditLogger();
    }

    /**
     * @description Entry point for a deletion request.
     *
     * @param contactId     SFSC Contact Id
     * @param requestSource 'OneTrust' | 'Agent' | 'SelfService'
     * @param requestId     Correlation Id from the requesting system
     */
    public void processPrivacyRequest(String contactId, String requestSource, String requestId) {
        // Gate 1: Check for open orders
        List<Order> openOrders = [
            SELECT Id FROM Order
            WHERE AccountId IN (
                SELECT AccountId FROM Contact WHERE Id = :contactId
            )
            AND Status NOT IN ('Delivered', 'Cancelled', 'Failed')
        ];

        if (!openOrders.isEmpty()) {
            throw new LoyaltyAPIException(
                'Cannot process deletion: Contact has ' + openOrders.size() + ' in-progress order(s)',
                409
            );
        }

        Contact c = [
            SELECT Id, Has_Loyalty__c, Loyalty_Member_Id__c, FirstName
            FROM Contact WHERE Id = :contactId LIMIT 1
        ];

        List<String> systemsUpdated = new List<String>();

        // Gate 2: Handle vouchers
        if (c.Has_Loyalty__c && String.isNotBlank(c.Loyalty_Member_Id__c)) {
            handleUnredeemedVouchers(c.Loyalty_Member_Id__c);
            auditLogger.log(contactId, 'VouchersCancelled', requestSource, requestId);
            systemsUpdated.add('LoyaltyCloud');

            // Gate 3: Unenroll from Loyalty Cloud
            unenrollFromLoyalty(c.Loyalty_Member_Id__c, 'PRIVACY_REQUEST');
            auditLogger.log(contactId, 'Unenrolled', requestSource, requestId);
        }

        // Gate 4: Deactivate Contact and clear PII
        deactivateContact(Id.valueOf(contactId));
        auditLogger.log(contactId, 'Deactivated', requestSource, requestId);
        systemsUpdated.add('SFSC');

        // Final audit entry with all systems updated
        Privacy_Audit_Log__c summary = new Privacy_Audit_Log__c(
            Contact_Id__c     = contactId,
            Action__c         = 'DeletionComplete',
            Request_Source__c = requestSource,
            Request_Id__c     = requestId,
            Systems_Updated__c = String.join(systemsUpdated, ';'),
            Timestamp__c      = DateTime.now(),
            Handled_By__c     = UserInfo.getUserId()
        );
        insert summary;
    }

    /**
     * @description Unenrolls the member from Loyalty Cloud — sets LPM to CANCELLED.
     */
    public void unenrollFromLoyalty(String lpmId, String reason) {
        memberSvc.unenrollMember(lpmId, reason);
    }

    /**
     * @description Clears all PII fields on the Contact per the retention schedule.
     */
    public void deactivateContact(Id contactId) {
        String suffix = String.valueOf(contactId).right(4);
        Contact c = new Contact(
            Id                   = contactId,
            FirstName            = 'Deleted',
            LastName             = 'User ' + suffix,
            Email                = null,
            Phone                = null,
            MailingStreet        = null,
            MailingCity          = null,
            MailingPostalCode    = null,
            DOB_Month__c         = null,
            DOB_Day__c           = null,
            Pro_License_Number__c = null,
            Pro_License_Expiry__c = null,
            School_Name__c       = null,
            Graduation_Date__c   = null,
            RCC_Card_Number__c   = null,
            Epsilon_Profile_Id__c = null
        );
        update c;
    }

    /**
     * @description Cancels all active vouchers for the member before unenrollment.
     *              Expired and already-redeemed vouchers are skipped (handled gracefully).
     */
    public void handleUnredeemedVouchers(String lpmId) {
        List<VoucherDTO> vouchers = voucherSvc.getMemberVouchers(lpmId);
        for (VoucherDTO v : vouchers) {
            if (v.isActive()) {
                try {
                    voucherSvc.cancelVoucher(v.voucherCode, 'PRIVACY_REQUEST');
                } catch (LoyaltyVoucherException e) {
                    System.debug(LoggingLevel.WARN,
                        'Could not cancel voucher ' + v.voucherCode + ': ' + e.getMessage());
                }
            }
        }
    }

    /**
     * @description Returns the last qualifying purchase date for a member.
     *              Used by PointsExpiryService — also relevant for privacy audits.
     */
    public Date getLastQualifyingPurchaseDate(String lpmId) {
        List<Order_Points_Status__c> records = [
            SELECT Id, CreatedDate
            FROM   Order_Points_Status__c
            WHERE  LPM_Id__c = :lpmId
            AND    Status__c = 'Awarded'
            ORDER  BY CreatedDate DESC
            LIMIT  1
        ];
        return records.isEmpty() ? null : records[0].CreatedDate.date();
    }
}
