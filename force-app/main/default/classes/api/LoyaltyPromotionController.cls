/**
 * @description AuraEnabled controller for loyaltyPromoEnrollment LWC.
 *              Thin wrapper around LoyaltyPromotionService — no business logic here.
 */
public with sharing class LoyaltyPromotionController {

    /**
     * @description Returns all promotions the member is eligible for or enrolled in.
     *
     * @param lpmId Target member LPM Id
     * @return      List of promotion maps from LC
     */
    @AuraEnabled(cacheable=false)
    public static List<Map<String, Object>> getMemberPromotions(String lpmId) {
        try {
            LoyaltyPromotionService svc = new LoyaltyPromotionService();
            return svc.getMemberPromotions(lpmId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Enrolls the member in a specific promotion.
     *
     * @param lpmId       Target member LPM Id
     * @param promotionId LC promotion identifier
     */
    @AuraEnabled
    public static void enrollForPromotion(String lpmId, String promotionId) {
        try {
            LoyaltyPromotionService svc = new LoyaltyPromotionService();
            svc.enrollForPromotion(lpmId, promotionId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Opts a member out of a specific promotion.
     *
     * @param lpmId       Target member LPM Id
     * @param promotionId LC promotion identifier
     */
    @AuraEnabled
    public static void optOutFromPromotion(String lpmId, String promotionId) {
        try {
            LoyaltyPromotionService svc = new LoyaltyPromotionService();
            svc.optOutFromPromotion(lpmId, promotionId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
