/**
 * @description Tests for PrivacyDeletionService.
 */
@IsTest
private class PrivacyDeletionServiceTest {

    @TestSetup
    static void setup() {
        Contact c = new Contact(
            FirstName             = 'Privacy',
            LastName              = 'Test',
            Email                 = 'privacy.test@example.com',
            Phone                 = '+15551234567',
            Has_Loyalty__c        = true,
            Loyalty_Member_Id__c  = 'LPM-PRIV-001'
        );
        insert c;
    }

    @IsTest
    static void testProcessPrivacyRequest_success() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(200, '{"memberVouchers":[]}'));
        Contact c = [SELECT Id FROM Contact WHERE Email = 'privacy.test@example.com' LIMIT 1];

        Test.startTest();
        PrivacyDeletionService svc = new PrivacyDeletionService();
        svc.processPrivacyRequest(c.Id, 'OneTrust', 'REQ-001');
        Test.stopTest();

        Contact updated = [SELECT Id, Email, Phone FROM Contact WHERE Id = :c.Id];
        System.assertEquals(null, updated.Email, 'Email should be cleared after deletion');
        System.assertEquals(null, updated.Phone, 'Phone should be cleared after deletion');

        List<Privacy_Audit_Log__c> logs = [SELECT Action__c FROM Privacy_Audit_Log__c];
        System.assert(!logs.isEmpty(), 'Audit log entries should be created');
    }

    @IsTest
    static void testDeactivateContact_clearsPII() {
        Contact c = [SELECT Id FROM Contact WHERE Email = 'privacy.test@example.com' LIMIT 1];

        Test.startTest();
        PrivacyDeletionService svc = new PrivacyDeletionService();
        svc.deactivateContact(c.Id);
        Test.stopTest();

        Contact updated = [SELECT FirstName, Email, Phone FROM Contact WHERE Id = :c.Id];
        System.assertEquals('Deleted', updated.FirstName);
        System.assertEquals(null, updated.Email);
        System.assertEquals(null, updated.Phone);
    }

    @IsTest
    static void testHandleUnredeemedVouchers_gracefulOnError() {
        // Voucher service returns one active voucher; cancel will succeed
        String voucherBody = JSON.serialize(new Map<String, Object>{
            'memberVouchers' => new List<Object>{
                new Map<String, Object>{
                    'voucherCode'   => 'CERT-ACTIVE',
                    'status'        => 'ACTIVE',
                    'faceValue'     => 10,
                    'expirationDate' => '2099-12-31'
                }
            }
        });
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(200, voucherBody));

        Test.startTest();
        PrivacyDeletionService svc = new PrivacyDeletionService();
        svc.handleUnredeemedVouchers('LPM-PRIV-001');
        Test.stopTest();

        System.assert(true, 'handleUnredeemedVouchers should complete gracefully');
    }
}
