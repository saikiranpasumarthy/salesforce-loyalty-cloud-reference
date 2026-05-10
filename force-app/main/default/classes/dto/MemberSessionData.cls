/**
 * @description Platform Cache–serialisable wrapper for session-level loyalty data.
 *              Stored in the 'LoyaltyMemberData' cache partition under key 'LMD_{contactId}'.
 *              TTL: 30 minutes (configurable in cache partition setup).
 *
 * This object is designed to be cheap to construct from multiple LC API responses
 * and cheap to JSON-serialize for cache storage.
 */
public with sharing class MemberSessionData {

    public String           lpmId               { get; set; }
    public String           loyaltyId           { get; set; }
    public String           tier                { get; set; }
    public String           memberType          { get; set; }
    public Decimal          pointsBalance       { get; set; }
    public Decimal          nextTierThreshold   { get; set; }
    public Decimal          pointsToNextTier    { get; set; }
    public Date             expiryDate          { get; set; }
    public Boolean          isCAMember          { get; set; }
    public Boolean          hasLoyalty          { get; set; }

    /** Available vouchers — cached to avoid a second LC API call per page load */
    public List<VoucherDTO> availableVouchers   { get; set; }

    /** UTC timestamp when this session data was last loaded from LC */
    public DateTime         lastRefreshed       { get; set; }

    public MemberSessionData() {
        this.isCAMember        = false;
        this.hasLoyalty        = false;
        this.availableVouchers = new List<VoucherDTO>();
        this.lastRefreshed     = DateTime.now();
    }

    /**
     * @description Returns true if the cached data is older than the given minute threshold.
     *              LWC components call this before deciding whether to use cached vs. fresh data.
     */
    public Boolean isStale(Integer maxAgeMinutes) {
        if (lastRefreshed == null) return true;
        Long ageMs = DateTime.now().getTime() - lastRefreshed.getTime();
        return ageMs > (maxAgeMinutes * 60 * 1000L);
    }
}
