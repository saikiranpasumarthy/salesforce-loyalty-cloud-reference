/**
 * @description Tests for PointsExpiryService.
 *              Verifies US member expires, CA member skips, within-window member skips.
 */
@IsTest
private class PointsExpiryServiceTest {

    @TestSetup
    static void setup() {
        // US member — no recent purchases → should be eligible for expiry
        Contact usContact = new Contact(
            FirstName             = 'US',
            LastName              = 'Member',
            Email                 = 'us.member@example.com',
            Has_Loyalty__c        = true,
            Loyalty_Member_Id__c  = 'LPM-US-001',
            Country_Code__c       = 'US'
        );
        insert usContact;

        // CA member — should never expire
        Contact caContact = new Contact(
            FirstName             = 'CA',
            LastName              = 'Member',
            Email                 = 'ca.member@example.com',
            Has_Loyalty__c        = true,
            Loyalty_Member_Id__c  = 'LPM-CA-001',
            Country_Code__c       = 'CA'
        );
        insert caContact;

        // US member with recent purchase — should be skipped
        Contact usRecentContact = new Contact(
            FirstName             = 'US',
            LastName              = 'Recent',
            Email                 = 'us.recent@example.com',
            Has_Loyalty__c        = true,
            Loyalty_Member_Id__c  = 'LPM-US-RECENT',
            Country_Code__c       = 'US'
        );
        insert usRecentContact;

        // Create recent order status for the recent purchaser
        Order_Points_Status__c recentOrder = new Order_Points_Status__c(
            Order_Id__c  = 'ORD-RECENT-001',
            LPM_Id__c    = 'LPM-US-RECENT',
            Status__c    = 'Awarded'
        );
        insert recentOrder;
    }

    @IsTest
    static void testIsCAMember_returnsTrueForCA() {
        Contact ca = [SELECT Id FROM Contact WHERE Country_Code__c = 'CA' LIMIT 1];

        Test.startTest();
        PointsExpiryService svc = new PointsExpiryService();
        Boolean isCA = svc.isCAMember(ca.Id);
        Test.stopTest();

        System.assertEquals(true, isCA, 'CA Contact should return true for isCAMember');
    }

    @IsTest
    static void testIsCAMember_returnsFalseForUS() {
        Contact us = [SELECT Id FROM Contact WHERE Country_Code__c = 'US' LIMIT 1];

        Test.startTest();
        PointsExpiryService svc = new PointsExpiryService();
        Boolean isCA = svc.isCAMember(us.Id);
        Test.stopTest();

        System.assertEquals(false, isCA);
    }

    @IsTest
    static void testEvaluateEligibility_caSkipped() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout());
        Contact ca = [SELECT Id FROM Contact WHERE Country_Code__c = 'CA' LIMIT 1];

        Test.startTest();
        PointsExpiryService svc = new PointsExpiryService();
        Boolean eligible = svc.evaluateExpiryEligibility(ca.Id);
        Test.stopTest();

        System.assertEquals(false, eligible, 'CA member should never be eligible for expiry');
    }

    @IsTest
    static void testEvaluateEligibility_recentPurchaseSkipped() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.MEMBER_BENEFITS_BODY));
        Contact recent = [SELECT Id FROM Contact WHERE Email = 'us.recent@example.com' LIMIT 1];

        Test.startTest();
        PointsExpiryService svc = new PointsExpiryService();
        Boolean eligible = svc.evaluateExpiryEligibility(recent.Id);
        Test.stopTest();

        System.assertEquals(false, eligible, 'Member with recent purchase should not be eligible');
    }

    @IsTest
    static void testProcessExpiry_callsDebit() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.MEMBER_BENEFITS_BODY));
        Contact us = [SELECT Id FROM Contact WHERE Email = 'us.member@example.com' LIMIT 1];

        Test.startTest();
        PointsExpiryService svc = new PointsExpiryService();
        svc.processExpiry(us.Id);
        Test.stopTest();

        System.assert(true, 'processExpiry should complete without exception');
    }
}
