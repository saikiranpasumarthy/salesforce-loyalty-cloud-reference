/**
 * @description Platform Cache–backed session data service for loyalty member state.
 *
 * CACHE STRATEGY:
 *   Partition: 'local.LoyaltyMemberData' (Org Cache — shared across users of same org)
 *   Key format: 'LMD_' + contactId (18-char)
 *   TTL: 30 minutes (1800 seconds)
 *
 * WHY ORG CACHE (not Session Cache):
 *   Session Cache is per-user session and cleared on logout. Org Cache persists across
 *   sessions and is appropriate for loyalty data shared across multiple service agent tabs.
 *   TTL of 30 minutes ensures data freshness without excessive LC API calls.
 *
 * FALLBACK: If Platform Cache is unavailable (no cache partition configured), the service
 *   falls back to direct LC API calls. This is handled transparently by isAvailable() check.
 */
public with sharing class LoyaltySessionCacheService {

    private static final String CACHE_PARTITION = 'local.LoyaltyMemberData';
    private static final String KEY_PREFIX       = 'LMD_';
    private static final Integer TTL_SECONDS     = 1800; // 30 minutes

    private final LoyaltyMemberService  memberSvc;
    private final LoyaltyVoucherService voucherSvc;

    public LoyaltySessionCacheService() {
        this.memberSvc  = new LoyaltyMemberService();
        this.voucherSvc = new LoyaltyVoucherService();
    }

    /**
     * @description Returns session loyalty data for the given Contact.
     *              Checks cache first; if miss or stale, fetches from LC API and repopulates.
     *
     * @param contactId SFSC Contact Id (15 or 18 char)
     * @return          Populated MemberSessionData, or empty object if Contact has no loyalty
     */
    public MemberSessionData getMemberData(Id contactId) {
        String cacheKey = buildKey(contactId);

        // Try cache first
        if (isCacheAvailable()) {
            MemberSessionData cached = (MemberSessionData) Cache.Org.get(CACHE_PARTITION, cacheKey);
            if (cached != null && !cached.isStale(30)) {
                return cached;
            }
        }

        // Cache miss — fetch from LC and store
        return refreshMemberData(contactId);
    }

    /**
     * @description Forces a cache refresh by fetching fresh data from LC API.
     *              Called after tier updates, point adjustments, or voucher issuance.
     */
    public MemberSessionData refreshMemberData(Id contactId) {
        Contact c = [
            SELECT Id, Has_Loyalty__c, Loyalty_Member_Id__c, Loyalty_Member_Type__c,
                   Country_Code__c, RCC_Active__c
            FROM   Contact
            WHERE  Id = :contactId
            LIMIT  1
        ];

        MemberSessionData data = new MemberSessionData();
        data.hasLoyalty  = c.Has_Loyalty__c;
        data.memberType  = c.Loyalty_Member_Type__c;
        data.isCAMember  = c.Country_Code__c == 'CA';

        if (!c.Has_Loyalty__c || String.isBlank(c.Loyalty_Member_Id__c)) {
            return data; // no LPM — return empty session data
        }

        data.lpmId = c.Loyalty_Member_Id__c;

        try {
            // Single LC API call for member benefits
            MemberBenefitsResponse benefits = memberSvc.getRewardsPoints(c.Loyalty_Member_Id__c);
            data.tier               = benefits.tierName;
            data.pointsBalance      = benefits.pointsBalance;
            data.nextTierThreshold  = benefits.pointsToNextTier + benefits.pointsBalance;
            data.pointsToNextTier   = benefits.pointsToNextTier;
            data.expiryDate         = benefits.expiryDate;
        } catch (LoyaltyAPIException e) {
            System.debug(LoggingLevel.WARN, 'getMemberData: benefits call failed: ' + e.getMessage());
        }

        try {
            // Second LC API call for active vouchers
            data.availableVouchers = voucherSvc.getMemberVouchers(c.Loyalty_Member_Id__c);
        } catch (LoyaltyAPIException e) {
            System.debug(LoggingLevel.WARN, 'getMemberData: vouchers call failed: ' + e.getMessage());
        }

        // Store in cache
        if (isCacheAvailable()) {
            Cache.Org.put(CACHE_PARTITION, buildKey(contactId), data, TTL_SECONDS);
        }

        return data;
    }

    /**
     * @description Clears cached data for the given Contact.
     *              Called on logout, role change, or explicit agent refresh.
     */
    public void clearMemberData(Id contactId) {
        if (isCacheAvailable()) {
            Cache.Org.remove(CACHE_PARTITION, buildKey(contactId));
        }
    }

    // ─────────────────────────────────────────────────────────────────────────

    private String buildKey(Id contactId) {
        // Strip leading zeros and normalize to 18-char for consistent cache keys
        return KEY_PREFIX + String.valueOf(contactId);
    }

    private Boolean isCacheAvailable() {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            return partition != null;
        } catch (Exception e) {
            return false;
        }
    }
}
