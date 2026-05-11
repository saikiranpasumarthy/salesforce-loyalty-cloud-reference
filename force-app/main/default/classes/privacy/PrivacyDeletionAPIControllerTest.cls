/**
 * @description Tests for PrivacyDeletionAPIController REST endpoint.
 */
@IsTest
private class PrivacyDeletionAPIControllerTest {

    @TestSetup
    static void setup() {
        Contact c = new Contact(
            FirstName             = 'API',
            LastName              = 'TestUser',
            Email                 = 'api.privacy@example.com',
            Has_Loyalty__c        = true,
            Loyalty_Member_Id__c  = 'LPM-API-001'
        );
        insert c;
    }

    @IsTest
    static void testDoDelete_validRequest_returns200() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(200, '{"memberVouchers":[]}'));
        Contact c = [SELECT Id FROM Contact WHERE Email = 'api.privacy@example.com' LIMIT 1];

        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'contactId'   => c.Id,
            'requestId'   => 'ONETRUST-001',
            'requestType' => 'DELETION'
        }));

        RestContext.request  = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PrivacyDeletionAPIController.doDelete();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> resp = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString()
        );
        System.assertEquals('SUCCESS', resp.get('status'));
    }

    @IsTest
    static void testDoDelete_missingContactId_returns400() {
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'requestId'   => 'ONETRUST-002',
            'requestType' => 'DELETION'
        }));

        RestContext.request  = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PrivacyDeletionAPIController.doDelete();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest
    static void testDoDelete_wrongRequestType_returns400() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];
        RestRequest req = new RestRequest();
        req.requestBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'contactId'   => c.Id,
            'requestId'   => 'ONETRUST-003',
            'requestType' => 'EXPORT'  // Wrong type
        }));

        RestContext.request  = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        PrivacyDeletionAPIController.doDelete();
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
    }
}
