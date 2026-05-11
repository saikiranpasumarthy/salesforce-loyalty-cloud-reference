/**
 * @description Payload object for Transaction Journal execution and simulation calls.
 *              Maps to the Loyalty Cloud Transaction Journals API request body.
 *
 * Key design note: lineItems are required for earn transactions because LC rules
 * evaluate category eligibility per line. For manual credit/debit (appeasement),
 * lineItems is left empty and pointsAdjusted is set directly.
 */
public with sharing class TransactionJournalDTO {

    /** Maps to journalTypeName in the LC API — must match an active Journal Type in LC config */
    public String      journalTypeName  { get; set; }

    /** ISO 8601 date string (YYYY-MM-DD) — when the qualifying event occurred */
    public String      activityDate     { get; set; }

    /** Direct points override for manual adjustments; leave null for rule-based earn */
    public Decimal     pointsAdjusted   { get; set; }

    /** Currency name in LC config (e.g. 'Reward Points') */
    public String      currencyName     { get; set; }

    /** LPM Id of the earning member */
    public String      lpmId            { get; set; }

    /** External order reference (orderId) — used for duplicate-TJ detection */
    public String      orderId          { get; set; }

    /** Line-item detail for earn-on-purchase transactions */
    public List<CartLineItem> lineItems { get; set; }

    /** Fulfilment type qualifier (BOPIS / SDD / Standard) — may drive tier multipliers */
    public String      fulfilmentType   { get; set; }

    /** Optional: tender type (RCC / Standard) — RCC unlocks bonus earn multiplier */
    public String      tenderType       { get; set; }

    /** Optional: reason text for manual adjustments (required by audit policy) */
    public String      reason           { get; set; }

    public TransactionJournalDTO() {
        this.lineItems = new List<CartLineItem>();
    }
}
