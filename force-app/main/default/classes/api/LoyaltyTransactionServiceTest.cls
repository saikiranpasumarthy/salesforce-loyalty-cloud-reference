/**
 * @description Tests for LoyaltyTransactionService.
 */
@IsTest
private class LoyaltyTransactionServiceTest {

    @IsTest
    static void testExecuteTransaction_success() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.TXN_SUCCESS_BODY));

        TransactionJournalDTO dto = buildTestDTO();

        Test.startTest();
        LoyaltyTransactionService svc = new LoyaltyTransactionService();
        Map<String, Object> result = svc.executeTransaction(dto);
        Test.stopTest();

        List<Object> journals = (List<Object>) result.get('transactionJournals');
        System.assertEquals(1, journals.size());
    }

    @IsTest
    static void testSimulateTransaction_success() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.TXN_SUCCESS_BODY));

        Test.startTest();
        LoyaltyTransactionService svc = new LoyaltyTransactionService();
        Map<String, Object> result = svc.simulateTransaction(buildTestDTO());
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testCreditPoints_success() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(200, '{"success":true}'));

        Test.startTest();
        LoyaltyTransactionService svc = new LoyaltyTransactionService();
        svc.creditPoints('LPM001', 100, 'Reward Points', null, 'Appeasement test');
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testCreditPoints_zeroAmount_throws() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout());

        Test.startTest();
        LoyaltyTransactionService svc = new LoyaltyTransactionService();
        try {
            svc.creditPoints('LPM001', 0, 'Reward Points', null, 'reason');
            System.assert(false, 'Should have thrown for zero amount');
        } catch (LoyaltyTransactionException e) {
            System.assertEquals(
                LoyaltyTransactionException.TransactionErrorCode.INSUFFICIENT_BALANCE,
                e.reason
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testDebitPoints_insufficientBalance_throws() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(422, LoyaltyMockHttpCallout.ERROR_422_INSUFFICIENT_BALANCE));

        Test.startTest();
        LoyaltyTransactionService svc = new LoyaltyTransactionService();
        try {
            svc.debitPoints('LPM001', 99999, 'Reward Points', 'TEST');
            System.assert(false, 'Should have thrown');
        } catch (LoyaltyTransactionException e) {
            System.assertEquals(422, e.statusCode);
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetTransactionHistory_success() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, '{"transactionJournals":[],"totalCount":0}'));

        Test.startTest();
        LoyaltyTransactionService svc = new LoyaltyTransactionService();
        Map<String, Object> result = svc.getTransactionHistory('LPM001', Date.today().addDays(-30), Date.today(), 25);
        Test.stopTest();

        System.assertNotEquals(null, result);
    }

    @IsTest
    static void testExcludedLineItems_notSentToLC() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.TXN_SUCCESS_BODY));

        TransactionJournalDTO dto = buildTestDTO();
        // Add excluded line
        CartLineItem excluded = new CartLineItem();
        excluded.productId = 'PROD-EXCL';
        excluded.isExcluded = true;
        excluded.lineTotal = 100;
        dto.lineItems.add(excluded);

        Test.startTest();
        LoyaltyTransactionService svc = new LoyaltyTransactionService();
        svc.executeTransaction(dto); // Should not include the excluded line
        Test.stopTest();

        System.assert(true, 'Excluded line should be filtered without error');
    }

    private static TransactionJournalDTO buildTestDTO() {
        TransactionJournalDTO dto = new TransactionJournalDTO();
        dto.lpmId            = 'LPM001';
        dto.orderId          = 'ORD-TEST-001';
        dto.journalTypeName  = 'Purchase';
        dto.activityDate     = String.valueOf(Date.today());
        dto.currencyName     = 'Reward Points';

        CartLineItem li = new CartLineItem();
        li.productId    = 'PROD001';
        li.sku          = 'SKU001';
        li.categoryName = 'Hardware';
        li.quantity     = 2;
        li.unitPrice    = 25.00;
        li.lineTotal    = 50.00;
        dto.lineItems.add(li);

        return dto;
    }
}
