/**
 * @description Represents a single line item in a cart or order.
 *              Used in TransactionJournalDTO.lineItems and CartEvaluationRequest.lineItems.
 *
 * The Loyalty Cloud rules engine evaluates each line's category to determine:
 *   - Whether the line is eligible for points earn (isExcluded lines are skipped)
 *   - Which earn rate multiplier applies (standard / RCC / promo bonus)
 */
public with sharing class CartLineItem {

    /** SFCC / OMS product Id */
    public String  productId    { get; set; }

    /** Product SKU for display on TJ records */
    public String  sku          { get; set; }

    /** LC product category name — matched against Loyalty_Exclusion_Rule__mdt */
    public String  categoryName { get; set; }

    public Integer quantity     { get; set; }

    /** Per-unit price before discounts */
    public Decimal unitPrice    { get; set; }

    /** unitPrice × quantity — the amount on which points are calculated */
    public Decimal lineTotal    { get; set; }

    /**
     * @description True when this line should be excluded from points calculation.
     *              Set by CheckoutService.buildFulfilmentPayload based on
     *              Loyalty_Exclusion_Rule__mdt records for the product category.
     */
    public Boolean isExcluded   { get; set; }

    public CartLineItem() {
        this.quantity   = 1;
        this.isExcluded = false;
    }
}
