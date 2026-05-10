/**
 * @description Tests for LoyaltyMemberService.
 */
@IsTest
private class LoyaltyMemberServiceTest {

    @IsTest
    static void testGetRewardsPoints_success() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.MEMBER_BENEFITS_BODY));

        Test.startTest();
        LoyaltyMemberService svc = new LoyaltyMemberService();
        MemberBenefitsResponse resp = svc.getRewardsPoints('LPM001');
        Test.stopTest();

        System.assertEquals(1500,       resp.pointsBalance);
        System.assertEquals('Preferred', resp.tierName);
        System.assertEquals('Elite',     resp.nextTierName);
        System.assertEquals(3500,        resp.pointsToNextTier);
    }

    @IsTest
    static void testGetRewardsPoints_apiError_throws() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(404, '{"message":"Member not found","errorCode":"NOT_FOUND"}'));

        Test.startTest();
        LoyaltyMemberService svc = new LoyaltyMemberService();
        try {
            svc.getRewardsPoints('BAD_LPM');
            System.assert(false, 'Should have thrown');
        } catch (LoyaltyAPIException e) {
            System.assertEquals(404, e.statusCode);
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateMemberDetails_success() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(200, '{}'));

        MemberUpdateDTO dto = new MemberUpdateDTO();
        dto.rccActive = true;
        dto.countryCode = 'US';

        Test.startTest();
        LoyaltyMemberService svc = new LoyaltyMemberService();
        svc.updateMemberDetails('LPM001', dto);
        Test.stopTest();

        // No exception = success
        System.assert(true, 'updateMemberDetails should complete without exception');
    }

    @IsTest
    static void testUnenrollMember_success() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(200, '{"status":"Cancelled"}'));

        Test.startTest();
        LoyaltyMemberService svc = new LoyaltyMemberService();
        svc.unenrollMember('LPM001', 'PRIVACY_REQUEST');
        Test.stopTest();

        System.assert(true, 'unenrollMember should complete without exception');
    }

    @IsTest
    static void testUpdateMemberTier_success() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout(200, '{}'));

        Test.startTest();
        LoyaltyMemberService svc = new LoyaltyMemberService();
        svc.updateMemberTier('LPM001', 'Elite', 'Agent override test');
        Test.stopTest();

        System.assert(true);
    }
}
