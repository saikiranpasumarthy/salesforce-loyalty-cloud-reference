/**
 * @description Returned by LoyaltyEnrollmentService to controllers and LWC wires.
 *              Always returned (never thrown) — callers check success flag.
 */
public with sharing class EnrollmentResponse {

    /** True when LPM was successfully created in Loyalty Cloud */
    public Boolean success           { get; set; }

    /** The Salesforce ID of the Contact record (new or matched) */
    public Id      contactId         { get; set; }

    /** Loyalty Management Individual Member (LPM) record Id */
    public Id      lpmId             { get; set; }

    /** Human-readable loyalty membership number shown on barcode / receipts */
    public String  loyaltyId         { get; set; }

    /** Membership number (may differ from loyaltyId in some program configurations) */
    public String  membershipNumber  { get; set; }

    /** Initial tier assigned at enrollment (typically 'Preferred') */
    public String  tier              { get; set; }

    /** Set when success = false — user-safe message for display */
    public String  errorMessage      { get; set; }

    /** Set when success = false — machine-readable error code for programmatic handling */
    public String  errorCode         { get; set; }

    /** Convenience factory for a successful response */
    public static EnrollmentResponse ok(Id contactId, Id lpmId, String loyaltyId, String tier) {
        EnrollmentResponse r = new EnrollmentResponse();
        r.success          = true;
        r.contactId        = contactId;
        r.lpmId            = lpmId;
        r.loyaltyId        = loyaltyId;
        r.membershipNumber = loyaltyId;
        r.tier             = tier;
        return r;
    }

    /** Convenience factory for a failed response */
    public static EnrollmentResponse fail(String message, String code) {
        EnrollmentResponse r = new EnrollmentResponse();
        r.success      = false;
        r.errorMessage = message;
        r.errorCode    = code;
        return r;
    }
}
