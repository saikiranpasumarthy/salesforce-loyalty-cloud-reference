/**
 * @description Thrown for Transaction Journal (TJ) operation failures.
 *
 * Common causes:
 *   - INSUFFICIENT_BALANCE : Debit request exceeds available points balance.
 *   - INVALID_JOURNAL_TYPE : The journalTypeName does not exist in the program configuration.
 *   - INVALID_CURRENCY     : The currency name is not configured for this program.
 *   - DUPLICATE_REFERENCE  : A TJ with the same orderId / reference already exists.
 *   - MEMBER_INACTIVE      : The LPM is unenrolled or suspended; no TJ allowed.
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
public with sharing class LoyaltyTransactionException extends LoyaltyAPIException {

    public TransactionErrorCode reason { get; private set; }

    public enum TransactionErrorCode {
        INSUFFICIENT_BALANCE,
        INVALID_JOURNAL_TYPE,
        INVALID_CURRENCY,
        DUPLICATE_REFERENCE,
        MEMBER_INACTIVE,
        UNKNOWN
    }

    public LoyaltyTransactionException(String message, TransactionErrorCode reason) {
        super(message, 422, reason.name(), null);
        this.reason = reason;
    }

    public LoyaltyTransactionException(String message, Integer statusCode, String errorCode, String rawResponse) {
        super(message, statusCode, errorCode, rawResponse);
        this.reason = TransactionErrorCode.UNKNOWN;
    }
}
