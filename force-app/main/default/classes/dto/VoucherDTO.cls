/**
 * @description Represents a single loyalty certificate/voucher.
 *              Returned by LoyaltyVoucherService.getMemberVouchers and used
 *              throughout the checkout and agent UI flows.
 */
public with sharing class VoucherDTO {

    /** Unique code used at redemption (displayed on member-facing barcode) */
    public String  voucherCode           { get; set; }

    /** Monetary value of the voucher in the program's default currency */
    public Decimal value                 { get; set; }

    /** ISO currency code (USD / CAD) */
    public String  currencyIsoCode       { get; set; }

    /** Date after which the voucher can no longer be redeemed */
    public Date    expiryDate            { get; set; }

    /** Current lifecycle state: ACTIVE | REDEEMED | EXPIRED | CANCELLED */
    public String  status                { get; set; }

    /** Reference to the Voucher Definition that generated this voucher */
    public String  voucherDefinitionId   { get; set; }

    /** Human-readable voucher name (e.g. '$10 Reward Certificate') */
    public String  voucherDefinitionName { get; set; }

    /** Id of the order this voucher was redeemed against (populated after redemption) */
    public String  redeemedOrderId       { get; set; }

    /** LPM Id this voucher belongs to */
    public String  lpmId                 { get; set; }

    /**
     * @description Returns true if the voucher expires within the given number of days.
     *              Used by loyaltyVoucherList LWC to show expiry warning highlight.
     */
    public Boolean expiresWithin(Integer days) {
        if (expiryDate == null) return false;
        return Date.today().daysBetween(expiryDate) <= days && expiryDate >= Date.today();
    }

    public Boolean isActive() {
        return status == 'ACTIVE';
    }
}
