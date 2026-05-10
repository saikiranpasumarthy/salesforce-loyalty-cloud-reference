/**
 * @description Test class for LoyaltyEnrollmentController AuraEnabled methods.
 */
@IsTest
private class LoyaltyEnrollmentControllerTest {

    @TestSetup
    static void setup() {
        List<Contact> contacts = new List<Contact>{
            // For duplicate-detection test (has loyalty already)
            new Contact(
                FirstName            = 'Loyalty',
                LastName             = 'Member',
                Email                = 'loyalty.member@example.com',
                Has_Loyalty__c       = true,
                Loyalty_Member_Id__c = 'MBR-CTRL001'
            ),
            // For testEnrollMember_success — pre-created so matchOrCreateContact finds it without DML
            new Contact(
                FirstName = 'Jane',
                LastName  = 'Doe',
                Email     = 'jane.doe@example.com',
                Phone     = '+15551112222'
            ),
            // For testEnrollExistingContact_success — a Contact with no loyalty
            new Contact(
                FirstName      = 'No',
                LastName       = 'Loyalty',
                Email          = 'noloyalty@example.com',
                Has_Loyalty__c = false
            )
        };
        insert contacts;
    }

    @IsTest
    static void testEnrollMember_success() {
        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.ENROLLMENT_SUCCESS_BODY));

        Test.startTest();
        EnrollmentResponse resp = LoyaltyEnrollmentController.enrollMember(
            'Jane', 'Doe', 'jane.doe@example.com', '+15551112222', 'Retail', 5, 14
        );
        Test.stopTest();

        System.assertEquals(true, resp.success, 'Controller enrollment should succeed');
    }

    @IsTest
    static void testEnrollMember_duplicate_returnsError() {
        Test.setMock(HttpCalloutMock.class, new LoyaltyMockHttpCallout());

        Test.startTest();
        EnrollmentResponse resp = LoyaltyEnrollmentController.enrollMember(
            'Loyalty', 'Member', 'loyalty.member@example.com', null, 'Retail', null, null
        );
        Test.stopTest();

        System.assertEquals(false, resp.success);
        System.assertEquals('DUPLICATE_MEMBER', resp.errorCode);
    }

    @IsTest
    static void testCheckEmailExists_found() {
        Test.startTest();
        Boolean exists = LoyaltyEnrollmentController.checkEmailExists('loyalty.member@example.com');
        Test.stopTest();

        System.assertEquals(true, exists);
    }

    @IsTest
    static void testCheckEmailExists_notFound() {
        Test.startTest();
        Boolean exists = LoyaltyEnrollmentController.checkEmailExists('nobody@example.com');
        Test.stopTest();

        System.assertEquals(false, exists);
    }

    @IsTest
    static void testCheckEmailExists_blank_returnsFalse() {
        Test.startTest();
        Boolean exists = LoyaltyEnrollmentController.checkEmailExists('');
        Test.stopTest();

        System.assertEquals(false, exists);
    }

    @IsTest
    static void testEnrollExistingContact_success() {
        List<Contact> contacts = [SELECT Id FROM Contact WHERE Has_Loyalty__c = false LIMIT 1];
        System.assert(!contacts.isEmpty(), 'Expected a no-loyalty Contact in TestSetup');
        Contact c = contacts[0];

        Test.setMock(HttpCalloutMock.class,
            new LoyaltyMockHttpCallout(200, LoyaltyMockHttpCallout.ENROLLMENT_SUCCESS_BODY));

        Test.startTest();
        EnrollmentResponse resp = LoyaltyEnrollmentController.enrollExistingContact(c.Id, 'Retail');
        Test.stopTest();

        System.assertEquals(true, resp.success);
    }
}
