/**
 * @description AuraEnabled controller for loyaltyTierManagement LWC (admin-only).
 *              Thin wrapper around LoyaltyMemberService.updateMemberTier.
 */
public with sharing class LoyaltyTierController {

    /**
     * @description Overrides the member's tier in Loyalty Cloud.
     *              Admin-only — requires Loyalty_Admin permission set.
     *
     * @param lpmId  Target member LPM Id
     * @param tier   New tier name matching an LC-configured tier
     * @param reason Mandatory audit reason
     */
    @AuraEnabled
    public static void updateMemberTier(String lpmId, String tier, String reason) {
        try {
            LoyaltyMemberService svc = new LoyaltyMemberService();
            svc.updateMemberTier(lpmId, tier, reason);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
