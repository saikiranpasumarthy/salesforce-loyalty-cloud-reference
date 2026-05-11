/**
 * @description Service for member-profile operations against the Loyalty Cloud API.
 *              All methods delegate HTTP callouts to LoyaltyAPIClient.
 *
 * Endpoints covered:
 *   GET  /connect/loyalty/programs/{name}/member-benefits          (getRewardsPoints)
 *   GET  /connect/loyalty/programs/{name}/members/{id}             (getMemberProfile)
 *   PUT  /connect/loyalty/programs/{name}/members/{id}             (updateMemberDetails)
 *   POST /program-processes/Update Member Tier                     (updateMemberTier)
 *   POST /program-processes/Unenroll Member                        (unenrollMember)
 */
public with sharing class LoyaltyMemberService {

    private final LoyaltyAPIClient client;

    public LoyaltyMemberService() {
        this.client = new LoyaltyAPIClient();
    }

    // Constructor for test injection
    @TestVisible
    private LoyaltyMemberService(LoyaltyAPIClient client) {
        this.client = client;
    }

    /**
     * @description Returns the member's current points balance, tier, and next-tier information.
     *              This is the primary method called by loyaltyPointsBalance LWC on component load.
     * @param lpmId Loyalty Program Member (LPM) record Id
     */
    public MemberBenefitsResponse getRewardsPoints(String lpmId) {
        String endpoint = '/member-benefits?memberId=' + EncodingUtil.urlEncode(lpmId, 'UTF-8');
        Map<String, Object> raw = client.get(endpoint);
        return parseMemberBenefits(raw);
    }

    /**
     * @description Returns the full member profile from Loyalty Cloud.
     *              Used on agent dashboard load and for validation before transactions.
     */
    public Map<String, Object> getMemberProfile(String lpmId) {
        String endpoint = '/members/' + EncodingUtil.urlEncode(lpmId, 'UTF-8');
        return client.get(endpoint);
    }

    /**
     * @description Applies a partial update to the LPM record in Loyalty Cloud.
     *              Only fields set on the DTO are sent — null fields are excluded.
     *              Triggered by: Contact field updates, RCC card sync, address changes.
     */
    public void updateMemberDetails(String lpmId, MemberUpdateDTO dto) {
        String endpoint = '/members/' + EncodingUtil.urlEncode(lpmId, 'UTF-8');
        String body     = JSON.serialize(dto.toUpdateMap());
        client.put(endpoint, body);
    }

    /**
     * @description Overrides the member's tier in Loyalty Cloud.
     *              Admin-only action — requires Loyalty_Admin permission set.
     *              Audit notes must be captured before calling this method.
     *
     * @param lpmId    Target member
     * @param tierName New tier name — must match a tier configured in the program
     * @param reason   Mandatory audit reason (e.g. 'Agent override: customer loyalty credit')
     */
    public void updateMemberTier(String lpmId, String tierName, String reason) {
        Map<String, Object> payload = new Map<String, Object>{
            'memberId'  => lpmId,
            'tierName'  => tierName,
            'reason'    => reason
        };
        String body = JSON.serialize(payload);
        client.post('/program-processes/Update%20Member%20Tier', body);
    }

    /**
     * @description Unenrolls a member from the loyalty program.
     *              Called by PrivacyDeletionService on GDPR/CCPA deletion requests.
     *              The LPM is set to CANCELLED status — the Contact remains in SFSC.
     *
     * @param lpmId  Target member
     * @param reason Reason code (PRIVACY_REQUEST | AGENT_REQUEST | ACCOUNT_CLOSURE)
     */
    public void unenrollMember(String lpmId, String reason) {
        Map<String, Object> payload = new Map<String, Object>{
            'memberId' => lpmId,
            'reason'   => reason
        };
        client.post('/program-processes/Unenroll%20Member', JSON.serialize(payload));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private parsers
    // ─────────────────────────────────────────────────────────────────────────

    private MemberBenefitsResponse parseMemberBenefits(Map<String, Object> raw) {
        MemberBenefitsResponse resp = new MemberBenefitsResponse();

        // LC returns a loyaltyProgramMemberBenefits wrapper
        Map<String, Object> benefits = raw.containsKey('loyaltyProgramMemberBenefits')
            ? (Map<String, Object>) raw.get('loyaltyProgramMemberBenefits')
            : raw;

        resp.tierName         = (String)  benefits.get('currentTierName');
        resp.nextTierName     = (String)  benefits.get('nextTierName');
        resp.currencyName     = (String)  benefits.get('loyaltyCurrencyName');

        Object bal = benefits.get('currentPointsBalance');
        resp.pointsBalance    = bal != null ? Decimal.valueOf(String.valueOf(bal)) : 0;

        Object pts = benefits.get('pointsToNextTier');
        resp.pointsToNextTier = pts != null ? Decimal.valueOf(String.valueOf(pts)) : 0;

        return resp;
    }
}
