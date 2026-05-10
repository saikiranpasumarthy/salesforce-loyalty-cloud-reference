/**
 * @description REST API endpoint for OneTrust deletion webhook integration.
 *
 * URL: /services/apexrest/privacy/delete/
 * Method: POST
 * Auth: Connected App (OAuth 2.0) — OneTrust calls with a service account token
 *
 * REQUEST BODY:
 * {
 *   "contactId": "003XXXXXXXXXXXXXXXXX",
 *   "requestId": "onetrust-uuid-1234",
 *   "requestType": "DELETION"
 * }
 *
 * RESPONSE (200 SUCCESS):
 * {
 *   "status": "SUCCESS",
 *   "systemsUpdated": ["LoyaltyCloud", "SFSC"],
 *   "timestamp": "2025-01-15T10:30:00Z"
 * }
 *
 * RESPONSE (4xx/5xx ERROR):
 * {
 *   "status": "ERROR",
 *   "message": "Cannot process deletion: Contact has open orders",
 *   "timestamp": "2025-01-15T10:30:00Z"
 * }
 *
 * SECURITY: The calling IP must be allowlisted in Connected App policy.
 *           The service account must have Loyalty_Integration_User permission set.
 */
@RestResource(urlMapping='/privacy/delete/*')
global without sharing class PrivacyDeletionAPIController {

    @HttpPost
    global static void doDelete() {
        RestRequest  req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            // Parse request body
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
            String contactId    = (String) body.get('contactId');
            String requestId    = (String) body.get('requestId');
            String requestType  = (String) body.get('requestType');

            // Validate mandatory fields
            if (String.isBlank(contactId))   throw new LoyaltyAPIException('contactId is required', 400);
            if (String.isBlank(requestId))   throw new LoyaltyAPIException('requestId is required', 400);
            if (requestType != 'DELETION')   throw new LoyaltyAPIException('requestType must be DELETION', 400);

            // Process the deletion
            PrivacyDeletionService svc = new PrivacyDeletionService();
            svc.processPrivacyRequest(contactId, 'OneTrust', requestId);

            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'status'         => 'SUCCESS',
                'systemsUpdated' => new List<String>{'LoyaltyCloud', 'SFSC'},
                'timestamp'      => DateTime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
            }));

        } catch (LoyaltyAPIException e) {
            res.statusCode = e.statusCode != null && e.statusCode > 0 ? e.statusCode : 422;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'status'    => 'ERROR',
                'message'   => e.getMessage(),
                'timestamp' => DateTime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
            }));

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PrivacyDeletionAPIController unhandled: ' + e.getMessage());
            res.statusCode = 500;
            res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                'status'    => 'ERROR',
                'message'   => 'An internal error occurred. Reference: ' + requestId(req),
                'timestamp' => DateTime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
            }));
        }
    }

    private static String requestId(RestRequest req) {
        try {
            Map<String, Object> b = (Map<String, Object>) JSON.deserializeUntyped(req.requestBody.toString());
            return (String) b.get('requestId');
        } catch (Exception e) {
            return 'unknown';
        }
    }
}
