/**
 * @description Tests for LoyaltyAPIClient HTTP handling and error mapping.
 */
@IsTest
private class LoyaltyAPIClientTest {

    @IsTest
    static void testPost_200_returnsMap() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, '{"result":"success","count":5}'));

        Test.startTest();
        LoyaltyAPIClient client = new LoyaltyAPIClient();
        Map<String, Object> result = client.post('/test-endpoint', '{"key":"value"}');
        Test.stopTest();

        System.assertEquals('success', result.get('result'));
        System.assertEquals(5, Integer.valueOf(String.valueOf(result.get('count'))));
    }

    @IsTest
    static void testGet_200_returnsMap() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, '{"items":["a","b"]}'));

        Test.startTest();
        LoyaltyAPIClient client = new LoyaltyAPIClient();
        Map<String, Object> result = client.get('/test-get');
        Test.stopTest();

        System.assertNotEquals(null, result.get('items'));
    }

    @IsTest
    static void testPost_400_throwsAPIException() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(400, LoyaltyMockHttpCallout.ERROR_400_BODY));

        Test.startTest();
        LoyaltyAPIClient client = new LoyaltyAPIClient();
        try {
            client.post('/test-400', '{}');
            System.assert(false, 'Should have thrown LoyaltyAPIException');
        } catch (LoyaltyAPIException e) {
            System.assertEquals(400, e.statusCode);
            System.assertEquals('BAD_REQUEST', e.errorCode);
        }
        Test.stopTest();
    }

    @IsTest
    static void testPost_422_insufficientBalance_throwsTransactionException() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(422, LoyaltyMockHttpCallout.ERROR_422_INSUFFICIENT_BALANCE));

        Test.startTest();
        LoyaltyAPIClient client = new LoyaltyAPIClient();
        try {
            client.post('/debit', '{}');
            System.assert(false, 'Should have thrown LoyaltyTransactionException');
        } catch (LoyaltyTransactionException e) {
            System.assertEquals(422, e.statusCode);
        }
        Test.stopTest();
    }

    @IsTest
    static void testPost_422_voucherExpired_throwsVoucherException() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(422, LoyaltyMockHttpCallout.ERROR_422_VOUCHER_EXPIRED));

        Test.startTest();
        LoyaltyAPIClient client = new LoyaltyAPIClient();
        try {
            client.post('/voucher', '{}');
            System.assert(false, 'Should have thrown LoyaltyVoucherException');
        } catch (LoyaltyVoucherException e) {
            System.assertEquals(422, e.statusCode);
        }
        Test.stopTest();
    }

    @IsTest
    static void testPost_emptyBody_returnsEmptyMap() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(200, ''));

        Test.startTest();
        LoyaltyAPIClient client = new LoyaltyAPIClient();
        Map<String, Object> result = client.post('/empty', '{}');
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(0, result.size());
    }
}
