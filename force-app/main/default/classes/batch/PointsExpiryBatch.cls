/**
 * @description Annual batch that expires points for US members who have not made
 *              a qualifying purchase within the past 12 months.
 *
 * EXPIRY RULES:
 *   - US members (Contact.Country_Code__c = 'US'): points expire annually
 *     if no qualifying purchase in the preceding 12 months.
 *   - CA members: points NEVER expire — this batch skips them entirely.
 *   - Members with an active in-progress order are deferred until next run.
 *
 * FLOW:
 *   1. Query US Contacts with active LPMs
 *   2. For each: PointsExpiryService.evaluateExpiryEligibility
 *   3. If eligible: PointsExpiryService.processExpiry → debitPoints via LC API
 *   4. Publish SFMC expiry notification event per expired member
 *   5. Log batch summary to Batch_Run_Log__c
 *
 * SCHEDULING: PointsExpiryScheduler runs this annually on January 1.
 */
public with sharing class PointsExpiryBatch implements Database.Batchable<SObject>, Database.Stateful {

    private Integer totalExpired    = 0;
    private Integer totalSkipped    = 0;
    private Integer totalFailed     = 0;
    private List<String> failedIds  = new List<String>();

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Only process US members with active LPMs and non-zero points
        return Database.getQueryLocator([
            SELECT Id, FirstName, LastName, Email,
                   Loyalty_Member_Id__c, Country_Code__c
            FROM   Contact
            WHERE  Country_Code__c = 'US'
            AND    Has_Loyalty__c = true
            AND    Loyalty_Member_Id__c != null
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Contact> scope) {
        PointsExpiryService expirySvc = new PointsExpiryService();

        for (Contact c : scope) {
            try {
                if (expirySvc.evaluateExpiryEligibility(c.Id)) {
                    expirySvc.processExpiry(c.Id);
                    totalExpired++;
                } else {
                    totalSkipped++;
                }
            } catch (Exception e) {
                totalFailed++;
                failedIds.add(c.Id + ': ' + e.getMessage());
                System.debug(LoggingLevel.ERROR, 'PointsExpiryBatch failed for ' + c.Id + ': ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        Batch_Run_Log__c log = new Batch_Run_Log__c(
            Batch_Type__c      = 'PointsExpiryBatch',
            Completed_At__c    = DateTime.now(),
            Total_Processed__c = totalExpired + totalSkipped + totalFailed,
            Total_Succeeded__c = totalExpired,
            Total_Failed__c    = totalFailed,
            Error_Summary__c   = failedIds.isEmpty() ? null : String.join(failedIds, '\n').left(131072),
            Apex_Job_Id__c     = String.valueOf(bc.getJobId())
        );
        insert log;

        System.debug('PointsExpiryBatch finished. Expired: ' + totalExpired
            + ', Skipped: ' + totalSkipped + ', Failed: ' + totalFailed);
    }
}
