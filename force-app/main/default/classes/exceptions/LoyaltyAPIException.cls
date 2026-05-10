/**
 * @description Base exception for all Loyalty Cloud API errors.
 *              All service-layer exceptions extend this class so callers
 *              can catch a single type for generic error handling, then
 *              narrow to subtype when specific recovery is needed.
 *
 * Usage pattern:
 *   try {
 *       loyaltyMemberService.getRewardsPoints(lpmId);
 *   } catch (LoyaltyVoucherException e) {
 *       // handle voucher-specific error
 *   } catch (LoyaltyAPIException e) {
 *       // handle any other LC API error
 *   }
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
public virtual with sharing class LoyaltyAPIException extends Exception {

    /** HTTP status code returned by the Loyalty Cloud API, if applicable. */
    public Integer statusCode { get; private set; }

    /** Machine-readable error code from the LC API response body (e.g. 'NOT_FOUND'). */
    public String errorCode { get; private set; }

    /** Raw response body for debugging; never surfaced to end users. */
    public String rawResponse { get; private set; }

    /**
     * @description Constructs an API exception with full context from an HTTP response.
     * @param message     Human-readable description of the error.
     * @param statusCode  HTTP status code (400, 401, 404, 422, 500 …).
     * @param errorCode   LC API error code string.
     * @param rawResponse The raw JSON response body, stored for debug logging.
     */
    public LoyaltyAPIException(String message, Integer statusCode, String errorCode, String rawResponse) {
        this(message);
        this.statusCode  = statusCode;
        this.errorCode   = errorCode;
        this.rawResponse = rawResponse;
    }

    /**
     * @description Constructs an API exception with just a message and status code.
     *              Use when no structured error body is available (e.g. network timeout).
     */
    public LoyaltyAPIException(String message, Integer statusCode) {
        this(message, statusCode, null, null);
    }
}
