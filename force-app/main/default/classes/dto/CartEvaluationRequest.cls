/**
 * @description Request payload for LoyaltyCartEvaluationService.evaluateCart.
 *              Sent pre-checkout to give the customer a points-earn preview before order submission.
 *
 * The evaluation is non-committing — it simulates the TJ without creating a record.
 * This powers the "You'll earn X points with this order" display in checkout.
 */
public with sharing class CartEvaluationRequest {

    /** LPM Id of the logged-in member */
    public String            lpmId           { get; set; }

    /** Cart line items; excluded lines are filtered before sending to LC */
    public List<CartLineItem> lineItems       { get; set; }

    /** Tender identifier (RCC / Standard) — unlocks RCC bonus earn rate if applicable */
    public String            tenderId        { get; set; }

    /** Voucher codes the customer intends to apply — affects adjusted total calculation */
    public List<String>      appliedVouchers { get; set; }

    /** ISO currency code for the order total */
    public String            currencyIsoCode { get; set; }

    public CartEvaluationRequest() {
        this.lineItems       = new List<CartLineItem>();
        this.appliedVouchers = new List<String>();
    }
}
