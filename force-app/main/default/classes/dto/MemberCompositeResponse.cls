/**
 * @description Unified member response returned by the composite REST API endpoint.
 *              Designed to reduce multiple LC API calls to a single SFSC REST call for
 *              POS systems (Xstore) and web storefront login-time hydration.
 *
 * The composite response is assembled by LoyaltyCompositeAPIController from:
 *   - ContactMatchService (SFSC Contact data)
 *   - LoyaltyMemberService.getMemberProfile + getRewardsPoints
 *   - LoyaltyVoucherService.getMemberVouchers
 */
public with sharing class MemberCompositeResponse {

    /** SFSC Contact record Id */
    public Id               contactId           { get; set; }

    /** Salesforce 18-digit Id (alias for contactId — kept for POS system backward compat) */
    public String           sfId                { get; set; }

    /** Loyalty Cloud member number (displayed on barcode) */
    public String           loyaltyId           { get; set; }

    /** Current tier: Preferred | Elite */
    public String           tier                { get; set; }

    /** Member type: Retail | Pro | Student */
    public String           memberType          { get; set; }

    /** Current redeemable points balance */
    public Decimal          pointsBalance       { get; set; }

    /** Threshold for next tier qualification */
    public Decimal          nextTierThreshold   { get; set; }

    /** Points still needed to reach next tier */
    public Decimal          pointsToNextTier    { get; set; }

    /** Active vouchers available for redemption */
    public List<VoucherDTO> vouchers            { get; set; }

    /** True when member is enrolled in the Canadian program (points do not expire) */
    public Boolean          isCAMember          { get; set; }

    /** True when a linked LPM record exists for this Contact */
    public Boolean          hasLoyalty          { get; set; }

    /** RCC card active flag */
    public Boolean          rccActive           { get; set; }

    /** ISO timestamp of when this composite was assembled */
    public String           assembledAt         { get; set; }

    public MemberCompositeResponse() {
        this.vouchers    = new List<VoucherDTO>();
        this.isCAMember  = false;
        this.hasLoyalty  = false;
        this.rccActive   = false;
        this.assembledAt = DateTime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }
}
