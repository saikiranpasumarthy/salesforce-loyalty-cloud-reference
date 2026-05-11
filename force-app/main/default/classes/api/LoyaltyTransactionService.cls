/**
 * @description Service for Transaction Journal operations — the heart of points earn/burn.
 *
 * Endpoints covered:
 *   POST /transaction-journals/bulk   (executeTransaction / simulateTransaction)
 *   POST /program-processes/Credit Points
 *   POST /program-processes/Debit Points
 *   GET  /transaction-journals        (getTransactionHistory)
 *   GET  /transaction-ledger-summary  (getLedgerSummary)
 *
 * KEY DESIGN: executeTransaction vs. simulateTransaction
 *   - simulate: read-only; returns estimated points without creating TJ records
 *   - execute:  creates TJ records; used at order fulfilment
 *   Both use the same payload shape — only the endpoint path differs.
 */
public with sharing class LoyaltyTransactionService {

    private final LoyaltyAPIClient client;

    public LoyaltyTransactionService() {
        this.client = new LoyaltyAPIClient();
    }

    @TestVisible
    private LoyaltyTransactionService(LoyaltyAPIClient client) {
        this.client = client;
    }

    /**
     * @description Executes a Transaction Journal — commits points earn/redeem to LC.
     *              Called by OrderFulfilmentEventHandler when an order ships.
     */
    public Map<String, Object> executeTransaction(TransactionJournalDTO dto) {
        return client.post('/transaction-journals/bulk', JSON.serialize(buildTxnBody(dto, false)));
    }

    /**
     * @description Simulates a TJ without committing — used for cart points preview.
     *              Powers the CartEvaluationService and checkout UI points estimate.
     */
    public Map<String, Object> simulateTransaction(TransactionJournalDTO dto) {
        return client.post('/transaction-journals/bulk', JSON.serialize(buildTxnBody(dto, true)));
    }

    /**
     * @description Directly credits points to a member — bypasses earn rules.
     *              Used for agent appeasement and manual adjustments from loyaltyPointsAdjustment LWC.
     *
     * @param lpmId        Target member
     * @param points       Positive number of points to credit
     * @param currencyName Currency name as configured in LC (e.g. 'Reward Points')
     * @param activityDate ISO date string for the event (defaults to today if blank)
     * @param reason       Mandatory audit reason
     */
    public void creditPoints(String lpmId, Decimal points, String currencyName, String activityDate, String reason) {
        if (points <= 0) {
            throw new LoyaltyTransactionException(
                'Credit amount must be positive',
                LoyaltyTransactionException.TransactionErrorCode.INSUFFICIENT_BALANCE
            );
        }

        Map<String, Object> payload = new Map<String, Object>{
            'memberId'      => lpmId,
            'pointsAmount'  => points,
            'currencyName'  => currencyName,
            'activityDate'  => String.isBlank(activityDate) ? String.valueOf(Date.today()) : activityDate,
            'reason'        => reason,
            'journalType'   => 'Manual Adjustment Credit'
        };
        client.post('/program-processes/Credit%20Points', JSON.serialize(payload));
    }

    /**
     * @description Directly debits points from a member's balance.
     *              Used for points expiry, manual corrections, and order cancellation reversals.
     *
     * @throws LoyaltyTransactionException (INSUFFICIENT_BALANCE) when points < requested debit
     */
    public void debitPoints(String lpmId, Decimal points, String currencyName, String reason) {
        if (points <= 0) {
            throw new LoyaltyTransactionException(
                'Debit amount must be positive',
                LoyaltyTransactionException.TransactionErrorCode.INSUFFICIENT_BALANCE
            );
        }

        Map<String, Object> payload = new Map<String, Object>{
            'memberId'     => lpmId,
            'pointsAmount' => points,
            'currencyName' => currencyName,
            'reason'       => reason,
            'journalType'  => 'Manual Adjustment Debit'
        };
        client.post('/program-processes/Debit%20Points', JSON.serialize(payload));
    }

    /**
     * @description Returns paginated transaction history for a member.
     *
     * @param lpmId    Target member
     * @param fromDate Inclusive start date filter
     * @param toDate   Inclusive end date filter
     * @param pageSize Number of records per page (default 25, max 100)
     */
    public Map<String, Object> getTransactionHistory(
        String lpmId, Date fromDate, Date toDate, Integer pageSize
    ) {
        String endpoint = '/transaction-journals?memberId=' + EncodingUtil.urlEncode(lpmId, 'UTF-8');
        if (fromDate != null) endpoint += '&fromDate=' + String.valueOf(fromDate);
        if (toDate   != null) endpoint += '&toDate='   + String.valueOf(toDate);
        endpoint += '&pageSize=' + (pageSize != null ? pageSize : 25);

        return client.get(endpoint);
    }

    /**
     * @description Returns the points ledger summary — total earned, redeemed, expired.
     *              Used on the agent dashboard summary panel.
     */
    public Map<String, Object> getLedgerSummary(String lpmId) {
        String endpoint = '/transaction-ledger-summary?memberId=' + EncodingUtil.urlEncode(lpmId, 'UTF-8');
        return client.get(endpoint);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private Map<String, Object> buildTxnBody(TransactionJournalDTO dto, Boolean simulate) {
        List<Map<String, Object>> lineItems = new List<Map<String, Object>>();
        for (CartLineItem li : dto.lineItems) {
            if (li.isExcluded) continue;
            lineItems.add(new Map<String, Object>{
                'productId'    => li.productId,
                'sku'          => li.sku,
                'category'     => li.categoryName,
                'quantity'     => li.quantity,
                'unitPrice'    => li.unitPrice,
                'lineTotal'    => li.lineTotal
            });
        }

        Map<String, Object> txn = new Map<String, Object>{
            'journalTypeName'         => dto.journalTypeName,
            'activityDate'            => dto.activityDate,
            'memberId'                => dto.lpmId,
            'referenceId'             => dto.orderId,
            'loyaltyCurrencyName'     => dto.currencyName,
            'simulate'                => simulate,
            'transactionJournalLines' => lineItems
        };

        if (dto.pointsAdjusted != null) txn.put('pointsAdjusted', dto.pointsAdjusted);
        if (dto.tenderType     != null) txn.put('tenderType',      dto.tenderType);
        if (dto.fulfilmentType != null) txn.put('fulfilmentType',  dto.fulfilmentType);

        // Wrap in bulk structure
        return new Map<String, Object>{
            'transactionJournals' => new List<Map<String, Object>>{ txn }
        };
    }
}
