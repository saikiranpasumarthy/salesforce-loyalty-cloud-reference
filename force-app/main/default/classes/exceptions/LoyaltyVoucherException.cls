/**
 * @description Thrown for certificate/voucher operation failures.
 *
 * Common causes:
 *   - VOUCHER_EXPIRED        : The voucher's expiry date has passed.
 *   - ALREADY_REDEEMED       : Voucher has already been fully applied.
 *   - VOUCHER_NOT_FOUND      : No voucher exists for the given code + member combination.
 *   - VOUCHER_CANCELLED      : Voucher was previously cancelled (e.g. on order reversal).
 *   - INSUFFICIENT_VALUE     : Voucher value is less than the minimum required for this order.
 *   - MEMBER_MISMATCH        : Voucher belongs to a different loyalty member.
 */
@SuppressWarnings('PMD.AvoidGlobalModifier')
public with sharing class LoyaltyVoucherException extends LoyaltyAPIException {

    public VoucherErrorCode reason { get; private set; }

    public enum VoucherErrorCode {
        VOUCHER_EXPIRED,
        ALREADY_REDEEMED,
        VOUCHER_NOT_FOUND,
        VOUCHER_CANCELLED,
        INSUFFICIENT_VALUE,
        MEMBER_MISMATCH,
        UNKNOWN
    }

    public LoyaltyVoucherException(String message, VoucherErrorCode reason) {
        super(message, 422, reason.name(), null);
        this.reason = reason;
    }

    public LoyaltyVoucherException(String message, Integer statusCode, String errorCode, String rawResponse) {
        super(message, statusCode, errorCode, rawResponse);
        this.reason = VoucherErrorCode.UNKNOWN;
    }
}
