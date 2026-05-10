/**
 * @description Test class for LoyaltyEnrollmentService.
 *              Covers new enrollment, existing member enrollment, duplicate detection, and error paths.
 */
@IsTest
private class LoyaltyEnrollmentServiceTest {

    @TestSetup
    static void setup() {
        // Create a Contact without loyalty for existing-member enrollment tests
        Contact c = new Contact(
            FirstName = 'Test',
            LastName  = 'Member',
            Email     = 'test.member@example.com',
            Phone     = '+15551234567'
        );
        insert c;

        // Create a Contact with loyalty for duplicate check tests
        Contact c2 = new Contact(
            FirstName           = 'Existing',
            LastName            = 'Loyalty',
            Email               = 'existing.loyalty@example.com',
            Has_Loyalty__c      = true,
            Loyalty_Member_Id__c = 'MBR-EXISTING'
        );
        insert c2;
    }

    @IsTest
    static void testEnrollNewMember_success() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.ENROLLMENT_SUCCESS_BODY));

        EnrollmentRequest req = buildRequest('newuser@example.com', 'Retail');

        Test.startTest();
        LoyaltyEnrollmentService svc = new LoyaltyEnrollmentService();
        EnrollmentResponse resp = svc.enrollNewMember(req);
        Test.stopTest();

        System.assertEquals(true,   resp.success,    'Enrollment should succeed');
        System.assertNotEquals(null, resp.loyaltyId,  'Loyalty ID should be set');
        System.assertNotEquals(null, resp.contactId,  'Contact ID should be set');
    }

    @IsTest
    static void testEnrollNewMember_duplicate_throws() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout());

        EnrollmentRequest req = buildRequest('existing.loyalty@example.com', 'Retail');

        Test.startTest();
        LoyaltyEnrollmentService svc = new LoyaltyEnrollmentService();
        try {
            svc.enrollNewMember(req);
            System.assert(false, 'Should have thrown LoyaltyEnrollmentException');
        } catch (LoyaltyEnrollmentException e) {
            System.assertEquals(
                LoyaltyEnrollmentException.EnrollmentErrorCode.DUPLICATE_MEMBER,
                e.reason
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testEnrollExistingMember_success() {
        Contact c = [SELECT Id FROM Contact WHERE Email = 'test.member@example.com' LIMIT 1];
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.ENROLLMENT_SUCCESS_BODY));

        Test.startTest();
        LoyaltyEnrollmentService svc = new LoyaltyEnrollmentService();
        EnrollmentResponse resp = svc.enrollExistingMember(c.Id, 'Retail');
        Test.stopTest();

        System.assertEquals(true, resp.success);
    }

    @IsTest
    static void testEnrollExistingMember_alreadyEnrolled_throws() {
        Contact c = [SELECT Id FROM Contact WHERE Email = 'existing.loyalty@example.com' LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout());

        Test.startTest();
        LoyaltyEnrollmentService svc = new LoyaltyEnrollmentService();
        try {
            svc.enrollExistingMember(c.Id, 'Retail');
            System.assert(false, 'Should have thrown');
        } catch (LoyaltyEnrollmentException e) {
            System.assertEquals(LoyaltyEnrollmentException.EnrollmentErrorCode.DUPLICATE_MEMBER, e.reason);
        }
        Test.stopTest();
    }

    @IsTest
    static void testEnrollNewMember_missingFields_throws() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout());
        EnrollmentRequest req = new EnrollmentRequest();
        req.firstName = 'Test';
        // lastName and email missing

        Test.startTest();
        LoyaltyEnrollmentService svc = new LoyaltyEnrollmentService();
        try {
            svc.enrollNewMember(req);
            System.assert(false, 'Should have thrown for missing fields');
        } catch (LoyaltyEnrollmentException e) {
            System.assertEquals(LoyaltyEnrollmentException.EnrollmentErrorCode.MISSING_FIELDS, e.reason);
        }
        Test.stopTest();
    }

    @IsTest
    static void testEnrollNewMember_apiError_propagates() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(500, LoyaltyMockHttpCallout.ERROR_400_BODY));

        EnrollmentRequest req = buildRequest('apierror@example.com', 'Retail');

        Test.startTest();
        LoyaltyEnrollmentService svc = new LoyaltyEnrollmentService();
        try {
            svc.enrollNewMember(req);
            System.assert(false, 'Should have thrown LoyaltyAPIException');
        } catch (LoyaltyAPIException e) {
            System.assert(e.statusCode >= 400);
        }
        Test.stopTest();
    }

    // ─── helpers ─────────────────────────────────────────────────────────────

    private static EnrollmentRequest buildRequest(String email, String memberType) {
        EnrollmentRequest req = new EnrollmentRequest();
        req.firstName    = 'New';
        req.lastName     = 'User';
        req.email        = email;
        req.phone        = '+15559876543';
        req.memberType   = memberType;
        req.programName  = 'TestProgram';
        req.enrollmentSource = 'TEST';
        return req;
    }
}
