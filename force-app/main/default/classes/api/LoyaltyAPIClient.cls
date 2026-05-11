/**
 * @description Base HTTP client for all Loyalty Cloud Connect API callouts.
 *
 * ARCHITECTURE NOTE: All LC API service classes (LoyaltyMemberService,
 * LoyaltyVoucherService, etc.) inherit from or delegate to this class.
 * No service class calls Http.send() directly — this ensures:
 *   1. Authentication (Named Credential token injection) is centralized.
 *   2. Error parsing and typed exception mapping is consistent.
 *   3. Retry logic (401 re-auth) is in one place.
 *   4. Mock injection in tests is straightforward (LoyaltyMockHttpCallout).
 *
 * Named Credential: Loyalty_Cloud_API
 * The base URL and program name are loaded from Loyalty_Program_Config__mdt.
 */
public with sharing class LoyaltyAPIClient {

    private static final Integer DEFAULT_TIMEOUT_MS = 30000;
    private static final Integer MAX_RETRIES        = 1;

    private String baseUrl;
    private String programName;
    private Integer timeoutMs;

    // Lazy-loaded config — avoids SOQL on every instantiation
    private static Loyalty_Program_Config__mdt cachedConfig;

    public LoyaltyAPIClient() {
        Loyalty_Program_Config__mdt cfg = getConfig();
        this.baseUrl     = '';
        this.programName = cfg.Program_API_Name__c;
        this.timeoutMs   = DEFAULT_TIMEOUT_MS;
    }

    /**
     * @description Performs an authenticated HTTP POST to the given endpoint path.
     * @param endpointPath Relative path after the base URL (e.g. '/individual-member-enrollments')
     * @param body         JSON-serialized request body string
     * @return             Parsed JSON response as Map<String, Object>
     * @throws LoyaltyAPIException on non-2xx response or network error
     */
    public Map<String, Object> post(String endpointPath, String body) {
        return send('POST', endpointPath, body, 0);
    }

    /**
     * @description Performs an authenticated HTTP GET.
     * @param endpointPath Relative path with any query params already appended
     */
    public Map<String, Object> get(String endpointPath) {
        return send('GET', endpointPath, null, 0);
    }

    /**
     * @description Performs an authenticated HTTP PUT.
     */
    public Map<String, Object> put(String endpointPath, String body) {
        return send('PUT', endpointPath, body, 0);
    }

    /**
     * @description Returns the configured LC program name for use in endpoint construction.
     */
    public String getProgramName() {
        return this.programName;
    }

    /**
     * @description Builds the full Loyalty Cloud API endpoint URL.
     *              Pattern: {baseUrl}/connect/loyalty/programs/{programName}{endpointPath}
     */
    public String buildEndpoint(String endpointPath) {
        return this.baseUrl
               + '/connect/loyalty/programs/'
               + EncodingUtil.urlEncode(this.programName, 'UTF-8')
               + endpointPath;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private Map<String, Object> send(String method, String endpointPath, String body, Integer retryCount) {
        HttpRequest req = buildRequest(method, buildEndpoint(endpointPath), body);
        HttpResponse res;

        try {
            res = new Http().send(req);
        } catch (System.CalloutException e) {
            throw new LoyaltyAPIException('Network error calling Loyalty Cloud: ' + e.getMessage(), 0);
        }

        // Re-authenticate once on 401 (Named Credential token may have expired)
        if (res.getStatusCode() == 401 && retryCount < MAX_RETRIES) {
            return send(method, endpointPath, body, retryCount + 1);
        }

        if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            String responseBody = res.getBody();
            if (String.isBlank(responseBody)) {
                return new Map<String, Object>();
            }
            return (Map<String, Object>) JSON.deserializeUntyped(responseBody);
        }

        handleError(res);
        return null; // unreachable — handleError always throws
    }

    private HttpRequest buildRequest(String method, String fullUrl, String body) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Loyalty_Cloud_API' + fullUrl.substringAfter(this.baseUrl));
        req.setMethod(method);
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(this.timeoutMs);

        if (body != null) {
            req.setBody(body);
        }
        return req;
    }

    /**
     * @description Parses a non-2xx LC API response and throws the appropriate typed exception.
     *              LC error body format: { "message": "...", "errorCode": "..." }
     */
    private void handleError(HttpResponse res) {
        Integer status  = res.getStatusCode();
        String  body    = res.getBody();
        String  message = 'Loyalty Cloud API error ' + status;
        String  code    = null;

        if (String.isNotBlank(body)) {
            try {
                Map<String, Object> err = (Map<String, Object>) JSON.deserializeUntyped(body);
                if (err.containsKey('message'))   message = (String) err.get('message');
                if (err.containsKey('errorCode')) code    = (String) err.get('errorCode');
            } catch (Exception e) {
                // raw body not parseable as JSON — use generic message
            }
        }

        // Map common LC error codes to typed exceptions
        if (code != null) {
            if (code.containsIgnoreCase('INSUFFICIENT_BALANCE') || code.containsIgnoreCase('INSUFFICIENT_STOCK')) {
                throw new LoyaltyTransactionException(message, status, code, body);
            }
            if (code.containsIgnoreCase('VOUCHER')) {
                throw new LoyaltyVoucherException(message, status, code, body);
            }
            if (code.containsIgnoreCase('DUPLICATE') || code.containsIgnoreCase('ENROLLMENT')) {
                throw new LoyaltyEnrollmentException(message, status, code, body);
            }
        }

        throw new LoyaltyAPIException(message, status, code, body);
    }

    private static Loyalty_Program_Config__mdt getConfig() {
        if (cachedConfig == null) {
            cachedConfig = [
                SELECT Program_API_Name__c, Currency_ISO_Code__c, Is_Active__c
                FROM   Loyalty_Program_Config__mdt
                WHERE  DeveloperName = 'Default'
                LIMIT  1
            ];
        }
        return cachedConfig;
    }
}
