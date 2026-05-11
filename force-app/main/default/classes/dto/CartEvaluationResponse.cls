/**
 * @description Response from cart evaluation / TJ simulation.
 *              Surfaced in the checkout UI via loyaltyDataService.
 */
public with sharing class CartEvaluationResponse {

    /** Points the member will earn if the order is placed as-is */
    public Decimal estimatedPoints    { get; set; }

    /** Base earn rate based on current tier (points per $1) */
    public Decimal tierEarnRate       { get; set; }

    /** Additional points from active promotions, RCC tender bonus, etc. */
    public Decimal bonusPoints        { get; set; }

    /** Order subtotal after any applied voucher discounts */
    public Decimal adjustedTotal      { get; set; }

    /** Details of each promotion that contributed points */
    public List<PromotionContribution> promotionBreakdown { get; set; }

    public CartEvaluationResponse() {
        this.promotionBreakdown = new List<PromotionContribution>();
    }

    public class PromotionContribution {
        public String  promotionName  { get; set; }
        public Decimal pointsAwarded  { get; set; }
        public String  promotionType  { get; set; }
    }
}
