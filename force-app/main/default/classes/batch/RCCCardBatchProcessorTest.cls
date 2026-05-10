/**
 * @description Tests for RCCCardBatchProcessor.
 */
@IsTest
private class RCCCardBatchProcessorTest {

    @TestSetup
    static void setup() {
        List<RCC_Import_Record__c> records = new List<RCC_Import_Record__c>{
            new RCC_Import_Record__c(
                Card_Number__c = 'RCC-001',
                Status__c      = 'Pending',
                Member_Type__c = 'Retail',
                Email__c       = 'rcc.test1@example.com'
            ),
            new RCC_Import_Record__c(
                Card_Number__c = 'RCC-002',
                Status__c      = 'Pending',
                Member_Type__c = 'Pro',
                Email__c       = 'rcc.test2@example.com'
            ),
            // Invalid record — no email
            new RCC_Import_Record__c(
                Card_Number__c = 'RCC-003',
                Status__c      = 'Pending',
                Member_Type__c = 'Retail'
            )
        };
        insert records;
    }

    @IsTest
    static void testBatch_processesAndUpdatesStatus() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.ENROLLMENT_SUCCESS_BODY));

        Test.startTest();
        RCCCardBatchProcessor batch = new RCCCardBatchProcessor();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Valid records should be Processed; invalid should be Failed
        List<RCC_Import_Record__c> processed = [
            SELECT Status__c FROM RCC_Import_Record__c
        ];

        Integer failedCount = 0;
        for (RCC_Import_Record__c r : processed) {
            if (r.Status__c == 'Failed') failedCount++;
        }

        // At least the invalid record should have failed
        System.assert(failedCount >= 1, 'At least one invalid record should be Failed');
    }

    @IsTest
    static void testBatch_logsRunSummary() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.ENROLLMENT_SUCCESS_BODY));

        Test.startTest();
        RCCCardBatchProcessor batch = new RCCCardBatchProcessor();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        List<Batch_Run_Log__c> logs = [SELECT Id, Batch_Type__c FROM Batch_Run_Log__c];
        System.assertEquals(1, logs.size());
        System.assertEquals('RCC_Card_Import', logs[0].Batch_Type__c);
    }
}
