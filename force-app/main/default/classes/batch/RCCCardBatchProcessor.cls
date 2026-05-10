/**
 * @description Nightly batch processor for inbound RCC card provider files.
 *
 * PROCESS FLOW:
 *   1. Reads RCC_Import_Record__c staging records in Pending status
 *   2. For each record: match or create Contact via ContactMatchService
 *   3. Create or update LoyaltyMember (LPM) via Loyalty Cloud enrollment API
 *   4. Update Contact.RCC_Active__c + RCC_Card_Number__c
 *   5. Update staging record to Processed/Failed
 *   6. On finish: log batch run summary and send completion email
 *
 * GOVERNOR LIMIT CONSIDERATIONS:
 *   - Batch size: 50 (configurable) — balances LC API callouts against heap
 *   - Each execute() chunk makes up to 50 LC API calls (1 per record)
 *   - Database.Stateful preserves BatchStats across execute() invocations
 *   - All DML is bulkified; no DML inside loops
 *
 * SCHEDULING: RCCBatchScheduler runs this nightly at 02:00 local time.
 */
public with sharing class RCCCardBatchProcessor
    implements Database.Batchable<SObject>, Database.Stateful {

    // ── Inner stat tracker ────────────────────────────────────────────────────

    @TestVisible
    private class BatchStats {
        Integer totalProcessed = 0;
        Integer succeeded      = 0;
        Integer failed         = 0;
        List<String> errors    = new List<String>();

        void recordSuccess() { totalProcessed++; succeeded++; }
        void recordFailure(String msg) { totalProcessed++; failed++; errors.add(msg); }
    }

    private BatchStats stats = new BatchStats();
    private String batchRunId;

    // ── Batchable interface ───────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        batchRunId = bc.getJobId();
        return Database.getQueryLocator([
            SELECT Id, Card_Number__c, Email__c, Member_Type__c,
                   Status__c, Error_Message__c, Batch_Job_Id__c
            FROM   RCC_Import_Record__c
            WHERE  Status__c = 'Pending'
            ORDER  BY CreatedDate ASC
        ]);
    }

    public void execute(Database.BatchableContext bc, List<RCC_Import_Record__c> scope) {
        LoyaltyEnrollmentService enrollSvc = new LoyaltyEnrollmentService();
        ContactMatchService      matchSvc  = new ContactMatchService();
        LoyaltyMemberService     memberSvc = new LoyaltyMemberService();

        List<RCC_Import_Record__c>  toUpdate  = new List<RCC_Import_Record__c>();
        List<Contact>               contacts  = new List<Contact>();
        Map<Id, RCC_Import_Record__c> recMap  = new Map<Id, RCC_Import_Record__c>();

        for (RCC_Import_Record__c rec : scope) {
            try {
                RCCRecordParser.ValidationResult vr = RCCRecordParser.validateRecord(rec);
                if (!vr.isValid) {
                    markFailed(rec, vr.errorMessage);
                    toUpdate.add(rec);
                    stats.recordFailure('Record ' + rec.Id + ': ' + vr.errorMessage);
                    continue;
                }

                // Match or create Contact
                ExternalProfileDTO dto = new ExternalProfileDTO();
                dto.email        = rec.Email__c;
                dto.rccCardNumber = rec.Card_Number__c;
                dto.sourceSystem = 'RCC_BATCH';

                Id contactId = matchSvc.matchOrCreateContact(dto);

                // Enroll or update LPM
                Contact c = [SELECT Id, Has_Loyalty__c, Loyalty_Member_Id__c FROM Contact WHERE Id = :contactId LIMIT 1];
                if (!c.Has_Loyalty__c) {
                    EnrollmentRequest req = enrollSvc.buildEnrollmentRequest(c, rec.Member_Type__c == 'Pro' ? 'Pro' : 'Retail');
                    req.programName = getProgramName();
                    enrollSvc.enrollNewMember(req);
                }

                // Update Contact RCC fields
                Contact toUpdateContact = new Contact(
                    Id               = contactId,
                    RCC_Active__c    = rec.Status__c == 'Active',
                    RCC_Card_Number__c = rec.Card_Number__c
                );
                contacts.add(toUpdateContact);

                markProcessed(rec);
                toUpdate.add(rec);
                stats.recordSuccess();

            } catch (Exception e) {
                markFailed(rec, e.getMessage());
                toUpdate.add(rec);
                stats.recordFailure('Record ' + rec.Id + ': ' + e.getMessage());
            }
        }

        if (!contacts.isEmpty())  update contacts;
        if (!toUpdate.isEmpty())  update toUpdate;
    }

    public void finish(Database.BatchableContext bc) {
        // Log batch run summary
        Batch_Run_Log__c log = new Batch_Run_Log__c(
            Batch_Type__c      = 'RCCCardBatchProcessor',
            Completed_At__c    = DateTime.now(),
            Total_Processed__c = stats.totalProcessed,
            Total_Succeeded__c = stats.succeeded,
            Total_Failed__c    = stats.failed,
            Error_Summary__c   = stats.errors.isEmpty() ? null : String.join(stats.errors, '\n').left(131072),
            Apex_Job_Id__c     = batchRunId
        );
        insert log;

        // Send completion notification email to the batch admin user
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        email.setToAddresses(new List<String>{ 'loyalty-ops@company.com' });
        email.setSubject('RCC Batch Complete: ' + stats.succeeded + '/' + stats.totalProcessed + ' succeeded');
        email.setPlainTextBody(
            'RCC Card Batch Run Summary\n'
            + 'Date: ' + DateTime.now() + '\n'
            + 'Total: ' + stats.totalProcessed + '\n'
            + 'Succeeded: ' + stats.succeeded + '\n'
            + 'Failed: ' + stats.failed + '\n'
            + (stats.failed > 0 ? 'Errors:\n' + String.join(stats.errors.subList(0, Math.min(10, stats.errors.size())), '\n') : '')
        );
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
    }

    // ─────────────────────────────────────────────────────────────────────────

    private void markProcessed(RCC_Import_Record__c rec) {
        rec.Status__c        = 'Processed';
        rec.Error_Message__c = null;
        rec.Batch_Job_Id__c  = batchRunId;
    }

    private void markFailed(RCC_Import_Record__c rec, String errorMsg) {
        rec.Status__c        = 'Failed';
        rec.Error_Message__c = errorMsg?.left(255);
        rec.Batch_Job_Id__c  = batchRunId;
    }

    private String getProgramName() {
        return [SELECT Program_API_Name__c FROM Loyalty_Program_Config__mdt
                WHERE DeveloperName = 'Default' LIMIT 1].Program_API_Name__c;
    }
}
