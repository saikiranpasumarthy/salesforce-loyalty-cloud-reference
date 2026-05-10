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
    public void log(String contactId, String action, String requestSource, String requestId, Id privacyRequestSfId) {
        Privacy_Audit_Log__c entry = new Privacy_Audit_Log__c(
            Privacy_Request__c = privacyRequestSfId,
            Action__c          = action,
            Detail__c          = 'Contact: ' + contactId + ' | Source: ' + requestSource + ' | ReqId: ' + requestId,
            Performed_At__c    = DateTime.now()
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
        Id cId = Id.valueOf(contactId);
        return [
            SELECT Id, Action__c, Detail__c, Performed_At__c
            FROM   Privacy_Audit_Log__c
            WHERE  Privacy_Request__c IN (
                SELECT Id FROM Privacy_Request__c WHERE Contact__c = :cId
            )
            ORDER  BY Performed_At__c DESC
        ];
    }
}
