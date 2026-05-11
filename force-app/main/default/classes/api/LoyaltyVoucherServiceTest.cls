/**
 * @description Tests for LoyaltyVoucherService.
 */
@IsTest
private class LoyaltyVoucherServiceTest {

    @IsTest
    static void testGetMemberVouchers_success() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.VOUCHER_LIST_BODY));

        Test.startTest();
        LoyaltyVoucherService svc = new LoyaltyVoucherService();
        List<VoucherDTO> vouchers = svc.getMemberVouchers('LPM001');
        Test.stopTest();

        System.assertEquals(1, vouchers.size());
        System.assertEquals('CERT-001', vouchers[0].voucherCode);
        System.assertEquals(10.00, vouchers[0].value);
        System.assertEquals('ACTIVE', vouchers[0].status);
    }

    @IsTest
    static void testGetMemberVouchers_emptyList() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, '{"memberVouchers":[]}'));

        Test.startTest();
        LoyaltyVoucherService svc = new LoyaltyVoucherService();
        List<VoucherDTO> vouchers = svc.getMemberVouchers('LPM001');
        Test.stopTest();

        System.assertEquals(0, vouchers.size());
    }

    @IsTest
    static void testValidateVoucher_valid() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, '{"isValid":true}'));

        Test.startTest();
        LoyaltyVoucherService svc = new LoyaltyVoucherService();
        Boolean valid = svc.validateVoucher('CERT-001', 'LPM001');
        Test.stopTest();

        System.assertEquals(true, valid);
    }

    @IsTest
    static void testValidateVoucher_expired_throwsVoucherException() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(422, LoyaltyMockHttpCallout.ERROR_422_VOUCHER_EXPIRED));

        Test.startTest();
        LoyaltyVoucherService svc = new LoyaltyVoucherService();
        try {
            svc.validateVoucher('EXPIRED-CERT', 'LPM001');
            System.assert(false, 'Should have thrown LoyaltyVoucherException');
        } catch (LoyaltyVoucherException e) {
            System.assertEquals(422, e.statusCode);
        }
        Test.stopTest();
    }

    @IsTest
    static void testRedeemVoucher_success() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(200, '{"status":"Redeemed"}'));

        Test.startTest();
        LoyaltyVoucherService svc = new LoyaltyVoucherService();
        svc.redeemVoucher('CERT-001', 'LPM001', 'ORD-001');
        Test.stopTest();

        System.assert(true, 'Redeem should complete without exception');
    }

    @IsTest
    static void testCancelVoucher_success() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(200, '{"status":"Cancelled"}'));

        Test.startTest();
        LoyaltyVoucherService svc = new LoyaltyVoucherService();
        svc.cancelVoucher('CERT-001', 'ORDER_CANCELLED');
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testVoucherDTO_expiresWithin() {
        VoucherDTO v = new VoucherDTO();
        v.expiryDate = Date.today().addDays(3);
        v.status     = 'ACTIVE';

        System.assertEquals(true,  v.expiresWithin(7));
        System.assertEquals(false, v.expiresWithin(2));
        System.assertEquals(true,  v.isActive());
    }
}
