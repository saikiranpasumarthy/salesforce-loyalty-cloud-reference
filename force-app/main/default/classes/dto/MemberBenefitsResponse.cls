/**
 * @description Parsed response from GET /connect/loyalty/programs/{name}/member-benefits.
 *              Drives the loyaltyPointsBalance and loyaltyMemberDashboard LWC components.
 */
public with sharing class MemberBenefitsResponse {

    /** Current redeemable points balance */
    public Decimal pointsBalance      { get; set; }

    /** Currency name (e.g. 'Reward Points') */
    public String  currencyName       { get; set; }

    /** Current tier (Preferred | Elite) */
    public String  tierName           { get; set; }

    /** Next tier threshold label */
    public String  nextTierName       { get; set; }

    /** Points needed to qualify for the next tier */
    public Decimal pointsToNextTier   { get; set; }

    /** Qualifying points earned in the current tier window */
    public Decimal qualifyingPoints   { get; set; }

    /** Date when current-period points expire (US members: 12-month window) */
    public Date    expiryDate         { get; set; }

    /** True when this member is enrolled in the CA program (points never expire) */
    public Boolean isCAMember         { get; set; }

    /** Timestamp of when this data was retrieved — used by LWC session cache */
    public DateTime lastRefreshed     { get; set; }

    public MemberBenefitsResponse() {
        this.lastRefreshed = DateTime.now();
        this.isCAMember    = false;
    }
}
