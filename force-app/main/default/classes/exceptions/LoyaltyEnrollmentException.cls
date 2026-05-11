/**
 * @description Thrown when a loyalty enrollment attempt cannot proceed.
 *
 * Common causes:
 *   - DUPLICATE_MEMBER : A Contact/LPM already exists for this email or phone.
 *   - MISSING_FIELDS   : Required enrollment fields (email, firstName, lastName) absent.
 *   - INVALID_PROGRAM  : The specified loyalty program does not exist.
 *   - ENROLLMENT_LIMIT : Member is already enrolled in maximum allowed programs.
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
public with sharing class LoyaltyEnrollmentException extends LoyaltyAPIException {

    /** Structured reason code — use in switch/if logic for recovery branching. */
    public EnrollmentErrorCode reason { get; private set; }

    public enum EnrollmentErrorCode {
        DUPLICATE_MEMBER,
        MISSING_FIELDS,
        INVALID_PROGRAM,
        ENROLLMENT_LIMIT,
        UNKNOWN
    }

    public LoyaltyEnrollmentException(String message, EnrollmentErrorCode reason) {
        this(message, null, null, null);
        this.reason = reason;
    }

    public LoyaltyEnrollmentException(String message, Integer statusCode, String errorCode, String rawResponse) {
        super(message, statusCode, errorCode, rawResponse);
        this.reason = EnrollmentErrorCode.UNKNOWN;
    }
}
