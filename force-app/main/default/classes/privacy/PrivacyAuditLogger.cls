/**
 * @description Creates and retrieves Privacy_Audit_Log__c records for GDPR/CCPA compliance.
 *
 * IMMUTABILITY: Audit log records are insert-only; no updates or deletes.
 *               This ensures the audit trail cannot be tampered with post-creation.
 *
 * RETENTION: Audit records must be retained for 7 years per compliance policy.
 *            A scheduled retention batch should archive records older than 7 years
 *            to external storage (not delete them from the platform).
 */
public with sharing class PrivacyAuditLogger {

    /**
     * @description Logs a privacy action for the given Contact.
     *
     * @param contactId     SFSC Contact Id
     * @param action        What happened (Unenrolled / Deactivated / VouchersCancelled / Exported)
     * @param requestSource External system that initiated the request (OneTrust / SFSC / Agent)
     * @param requestId     OneTrust request UUID for cross-system correlation
     */
    public void log(String contactId, String action, String requestSource, String requestId) {
        Privacy_Audit_Log__c entry = new Privacy_Audit_Log__c(
            Contact_Id__c     = contactId,
            Action__c         = action,
            Request_Source__c = requestSource,
            Request_Id__c     = requestId,
            Timestamp__c      = DateTime.now(),
            Handled_By__c     = UserInfo.getUserId()
        );
        insert entry;
    }

    /**
     * @description Logs multiple actions in a single DML call (bulk version).
     */
    public void logBulk(List<Privacy_Audit_Log__c> entries) {
        if (!entries.isEmpty()) insert entries;
    }

    /**
     * @description Returns all audit entries for the given Contact, ordered by timestamp desc.
     *              Used by privacy admin screens to show a member's deletion history.
     */
    public List<Privacy_Audit_Log__c> getAuditTrail(String contactId) {
        return [
            SELECT Id, Action__c, Request_Source__c, Request_Id__c,
                   Timestamp__c, Systems_Updated__c, Handled_By__c
            FROM   Privacy_Audit_Log__c
            WHERE  Contact_Id__c = :contactId
            ORDER  BY Timestamp__c DESC
        ];
    }
}
