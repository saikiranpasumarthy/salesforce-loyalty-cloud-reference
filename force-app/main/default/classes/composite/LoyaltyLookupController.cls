/**
 * @description REST API endpoint for POS/Xstore customer lookup.
 *              Accepts multiple lookup identifiers and returns matched member data.
 *
 * URL: /services/apexrest/loyalty/lookup
 * Method: POST
 *
 * REQUEST BODY (any combination of identifiers):
 * {
 *   "email": "customer@example.com",
 *   "phone": "+15551234567",
 *   "loyaltyId": "MBR-10001",
 *   "cardNumber": "4111111111111111"
 * }
 *
 * RESPONSE: MemberCompositeResponse or {"found": false}
 *
 * DESIGN: Xstore sends whichever identifiers it has at scan-time.
 *         DeduplicationService finds the best match across all provided identifiers.
 */
@RestResource(urlMapping='/loyalty/lookup')
global with sharing class LoyaltyLookupController {

    @HttpPost
    global static void lookup() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());

            String email     = (String) body.get('email');
            String phone     = (String) body.get('phone');
            String loyaltyId = (String) body.get('loyaltyId');
            String cardNumber = (String) body.get('cardNumber');

            if (String.isBlank(email) && String.isBlank(phone)
                && String.isBlank(loyaltyId) && String.isBlank(cardNumber)) {
                res.statusCode = 400;
                res.responseBody = Blob.valueOf('{"error":"At least one lookup identifier is required"}');
                return;
            }

            Contact matched = findContact(email, phone, loyaltyId, cardNumber);

            if (matched == null) {
                res.statusCode = 200;
                res.responseBody = Blob.valueOf('{"found":false}');
                return;
            }

            // Build composite using session cache for performance
            LoyaltySessionCacheService cacheSvc = new LoyaltySessionCacheService();
            MemberSessionData sessionData = cacheSvc.getMemberData(matched.Id);

            MemberCompositeResponse resp = buildFromSession(matched, sessionData);
            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(resp));

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'LoyaltyLookupController error: ' + e.getMessage());
            res.statusCode = 500;
            res.responseBody = Blob.valueOf('{"error":"Internal server error"}');
        }
    }

    private static Contact findContact(String email, String phone, String loyaltyId, String cardNumber) {
        String normalizedPhone = String.isNotBlank(phone)
            ? phone.replaceAll('[^0-9]', '')
            : null;
        String phoneSearch = normalizedPhone != null
            ? '%' + normalizedPhone.right(10) + '%'
            : '%NOMATCH%';

        List<Contact> contacts = [
            SELECT Id, FirstName, LastName, Has_Loyalty__c, Loyalty_Member_Id__c,
                   Loyalty_Member_Type__c, Country_Code__c, RCC_Active__c, RCC_Card_Number__c
            FROM   Contact
            WHERE  (Email = :email                              AND :email != null)
               OR  (Phone LIKE :phoneSearch                    AND :normalizedPhone != null)
               OR  (Loyalty_Member_Id__c = :loyaltyId          AND :loyaltyId != null)
               OR  (RCC_Card_Number__c = :cardNumber            AND :cardNumber != null)
            LIMIT  1
        ];
        return contacts.isEmpty() ? null : contacts[0];
    }

    private static MemberCompositeResponse buildFromSession(Contact c, MemberSessionData data) {
        MemberCompositeResponse resp = new MemberCompositeResponse();
        resp.contactId        = c.Id;
        resp.sfId             = String.valueOf(c.Id);
        resp.loyaltyId        = data.loyaltyId;
        resp.tier             = data.tier;
        resp.memberType       = data.memberType;
        resp.pointsBalance    = data.pointsBalance;
        resp.pointsToNextTier = data.pointsToNextTier;
        resp.vouchers         = data.availableVouchers;
        resp.isCAMember       = data.isCAMember;
        resp.hasLoyalty       = data.hasLoyalty;
        resp.rccActive        = c.RCC_Active__c;
        return resp;
    }
}
