/**
 * @description Tests for RCCCardBatchProcessor.
 */
@IsTest
private class RCCCardBatchProcessorTest {

    @TestSetup
    static void setup() {
        List<RCC_Import_Record__c> records = new List<RCC_Import_Record__c>{
            new RCC_Import_Record__c(
                Card_Number__c       = 'RCC-001',
                Card_Status__c       = 'Active',
                Card_Type__c         = 'Retail',
                Email__c             = 'rcc.test1@example.com',
                Phone__c             = '+15551110001',
                First_Name__c        = 'Alice',
                Last_Name__c         = 'Smith',
                Processing_Status__c = 'Pending',
                Import_Date__c       = DateTime.now()
            ),
            new RCC_Import_Record__c(
                Card_Number__c       = 'RCC-002',
                Card_Status__c       = 'Active',
                Card_Type__c         = 'Pro',
                Email__c             = 'rcc.test2@example.com',
                Phone__c             = '+15551110002',
                First_Name__c        = 'Bob',
                Last_Name__c         = 'Jones',
                Processing_Status__c = 'Pending',
                Import_Date__c       = DateTime.now()
            ),
            // Invalid record — no email or phone
            new RCC_Import_Record__c(
                Card_Number__c       = 'RCC-003',
                Card_Status__c       = 'Active',
                Card_Type__c         = 'Retail',
                First_Name__c        = 'Invalid',
                Last_Name__c         = 'Record',
                Processing_Status__c = 'Pending',
                Import_Date__c       = DateTime.now()
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
            SELECT Processing_Status__c FROM RCC_Import_Record__c
        ];

        Integer failedCount = 0;
        for (RCC_Import_Record__c r : processed) {
            if (r.Processing_Status__c == 'Failed') failedCount++;
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

        List<Batch_Run_Log__c> logs = [SELECT Id, Batch_Name__c FROM Batch_Run_Log__c];
        System.assertEquals(1, logs.size());
        System.assertEquals('RCCCardBatchProcessor', logs[0].Batch_Name__c);
    }
}
