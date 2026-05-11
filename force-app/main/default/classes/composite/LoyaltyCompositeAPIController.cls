/**
 * @description REST API endpoint that returns a unified member profile in a single call.
 *              Designed to reduce POS/web integration overhead from 3-4 calls to 1.
 *
 * URL: /services/apexrest/loyalty/member/
 * Method: GET
 * Query param: contactId=003XXXXXXXXXXXXXXXXX  OR  loyaltyId=MBR-10001
 *
 * RESPONSE: MemberCompositeResponse JSON
 *
 * INTERNAL ASSEMBLY:
 *   1. ContactMatchService — find SFSC Contact
 *   2. LoyaltyMemberService.getRewardsPoints — points + tier
 *   3. LoyaltyVoucherService.getMemberVouchers — active vouchers
 *   Results merged into a single MemberCompositeResponse
 */
@RestResource(urlMapping='/loyalty/member/*')
global with sharing class LoyaltyCompositeAPIController {

    @HttpGet
    global static void getMemberData() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String contactId = req.params.get('contactId');
            String loyaltyId = req.params.get('loyaltyId');

            if (String.isBlank(contactId) && String.isBlank(loyaltyId)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('{"error":"contactId or loyaltyId is required"}');
                return;
            }

            // Resolve Contact
            Contact c = resolveContact(contactId, loyaltyId);
            if (c == null) {
                res.statusCode = 404;
                res.responseBody = Blob.valueOf('{"error":"Member not found"}');
                return;
            }

            // Assemble composite response
            MemberCompositeResponse composite = assembleComposite(c);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(composite));

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'LoyaltyCompositeAPIController error: ' + e.getMessage());
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('{"error":"Internal server error"}');
        }
    }

    private static Contact resolveContact(String contactId, String loyaltyId) {
        if (String.isNotBlank(contactId)) {
            List<Contact> contacts = [
                SELECT Id, FirstName, LastName, Has_Loyalty__c, Loyalty_Member_Id__c,
                       Loyalty_Member_Type__c, Country_Code__c, RCC_Active__c
                FROM   Contact WHERE Id = :contactId LIMIT 1
            ];
            return contacts.isEmpty() ? null : contacts[0];
        }

        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Has_Loyalty__c, Loyalty_Member_Id__c,
                   Loyalty_Member_Type__c, Country_Code__c, RCC_Active__c
            FROM   Contact WHERE Loyalty_Member_Id__c = :loyaltyId LIMIT 1
        ];
        return contacts.isEmpty() ? null : contacts[0];
    }

    private static MemberCompositeResponse assembleComposite(Contact c) {
        MemberCompositeResponse resp = new MemberCompositeResponse();
        resp.contactId   = c.Id;
        resp.sfId        = String.valueOf(c.Id);
        resp.hasLoyalty  = c.Has_Loyalty__c;
        resp.memberType  = c.Loyalty_Member_Type__c;
        resp.isCAMember  = c.Country_Code__c == 'CA';
        resp.rccActive   = c.RCC_Active__c;

        if (!c.Has_Loyalty__c || String.isBlank(c.Loyalty_Member_Id__c)) {
            return resp;
        }

        resp.loyaltyId = c.Loyalty_Member_Id__c;

        try {
            LoyaltyMemberService memberSvc = new LoyaltyMemberService();
            MemberBenefitsResponse benefits = memberSvc.getRewardsPoints(c.Loyalty_Member_Id__c);
            resp.tier              = benefits.tierName;
            resp.pointsBalance     = benefits.pointsBalance;
            resp.nextTierThreshold = benefits.pointsBalance + benefits.pointsToNextTier;
            resp.pointsToNextTier  = benefits.pointsToNextTier;
        } catch (LoyaltyAPIException e) {
            System.debug(LoggingLevel.WARN, 'Composite: benefits call failed: ' + e.getMessage());
        }

        try {
            LoyaltyVoucherService voucherSvc = new LoyaltyVoucherService();
            resp.vouchers = voucherSvc.getMemberVouchers(c.Loyalty_Member_Id__c);
        } catch (LoyaltyAPIException e) {
            System.debug(LoggingLevel.WARN, 'Composite: vouchers call failed: ' + e.getMessage());
        }

        return resp;
    }
}
