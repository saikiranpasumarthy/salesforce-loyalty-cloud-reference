/**
 * @description Service for promotion lifecycle operations.
 *
 * Endpoints covered:
 *   GET  /member-promotions                           (getMemberPromotions)
 *   POST /program-processes/Enroll Promotions         (enrollForPromotion)
 *   POST /program-processes/Opt Out Promotion         (optOutFromPromotion)
 *   GET  /transaction-journals/{id}/promotions        (getPromotionsByTxn)
 */
public with sharing class LoyaltyPromotionService {

    private final LoyaltyAPIClient client;

    public LoyaltyPromotionService() {
        this.client = new LoyaltyAPIClient();
    }

    @TestVisible
    private LoyaltyPromotionService(LoyaltyAPIClient client) {
        this.client = client;
    }

    /**
     * @description Returns all promotions the member is eligible for or enrolled in.
     *              Used by loyaltyPromoEnrollment LWC to display and manage promotions.
     */
    public List<Map<String, Object>> getMemberPromotions(String lpmId) {
        Map<String, Object> raw = client.get(
            '/member-promotions?memberId=' + EncodingUtil.urlEncode(lpmId, 'UTF-8')
        );

        List<Object> promos = (List<Object>) raw.get('memberPromotions');
        if (promos == null) return new List<Map<String, Object>>();

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Object p : promos) {
            result.add((Map<String, Object>) p);
        }
        return result;
    }

    /**
     * @description Enrolls the member in a specific promotion.
     *              Agent triggers this from loyaltyPromoEnrollment LWC for opt-in promos.
     */
    public void enrollForPromotion(String lpmId, String promotionId) {
        Map<String, Object> payload = new Map<String, Object>{
            'memberId'    => lpmId,
            'promotionId' => promotionId
        };
        client.post('/program-processes/Enroll%20Promotions', JSON.serialize(payload));
    }

    /**
     * @description Opts a member out of a specific promotion.
     *              Required for GDPR preference management and agent-assisted opt-out.
     */
    public void optOutFromPromotion(String lpmId, String promotionId) {
        Map<String, Object> payload = new Map<String, Object>{
            'memberId'    => lpmId,
            'promotionId' => promotionId
        };
        client.post('/program-processes/Opt%20Out%20Promotion', JSON.serialize(payload));
    }

    /**
     * @description Returns which promotions contributed points to a given transaction.
     *              Displayed in the agent transaction detail view for transparency.
     */
    public List<Map<String, Object>> getPromotionsByTxn(String txnJournalId) {
        Map<String, Object> raw = client.get(
            '/transaction-journals/'
            + EncodingUtil.urlEncode(txnJournalId, 'UTF-8')
            + '/promotions'
        );

        List<Object> promos = (List<Object>) raw.get('promotions');
        if (promos == null) return new List<Map<String, Object>>();

        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Object p : promos) {
            result.add((Map<String, Object>) p);
        }
        return result;
    }
}
