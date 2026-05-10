/**
 * @description Evaluates a shopping cart for points estimation before order submission.
 *              Provides real-time "You'll earn X points" preview during checkout.
 *
 * ARCHITECTURE NOTE: This service calls simulateTransaction (read-only) rather than
 * executeTransaction, so no LC records are created. The actual TJ is created by
 * OrderFulfilmentEventHandler when the OMS sends the fulfilment event.
 *
 * Exclusion logic: Lines whose categoryName matches an active Loyalty_Exclusion_Rule__mdt
 * record are flagged isExcluded=true before building the evaluation payload.
 */
public with sharing class LoyaltyCartEvaluationService {

    private final LoyaltyTransactionService txnService;

    // Loaded once per transaction to avoid SOQL in loops
    private static Map<String, Boolean> exclusionCache;

    public LoyaltyCartEvaluationService() {
        this.txnService = new LoyaltyTransactionService();
    }

    @TestVisible
    private LoyaltyCartEvaluationService(LoyaltyTransactionService txnService) {
        this.txnService = txnService;
    }

    /**
     * @description Evaluates the given cart and returns estimated points.
     *              Applies exclusion rules before sending to LC.
     */
    public CartEvaluationResponse evaluateCart(CartEvaluationRequest req) {
        // Apply exclusion rules client-side to avoid sending excluded items to LC
        List<CartLineItem> eligibleLines = applyExclusionRules(req.lineItems);

        TransactionJournalDTO dto = buildSimulationDTO(req.lpmId, eligibleLines, req.tenderId);
        Map<String, Object> raw   = txnService.simulateTransaction(dto);

        return parseEvaluationResponse(raw);
    }

    /**
     * @description Builds a CartEvaluationRequest from raw line items for convenience.
     *              Called by checkout controllers before calling evaluateCart.
     */
    public CartEvaluationRequest buildCartRequest(
        List<CartLineItem> lines, String lpmId, String tenderId
    ) {
        CartEvaluationRequest req = new CartEvaluationRequest();
        req.lpmId    = lpmId;
        req.tenderId = tenderId;
        req.lineItems = lines;
        return req;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Private helpers
    // ─────────────────────────────────────────────────────────────────────────

    private List<CartLineItem> applyExclusionRules(List<CartLineItem> lines) {
        Map<String, Boolean> exclusions = getExclusionRules();
        List<CartLineItem> result = new List<CartLineItem>();

        for (CartLineItem li : lines) {
            CartLineItem copy = li.clone(); // avoid mutating the caller's list
            if (exclusions.containsKey(li.categoryName)) {
                copy.isExcluded = exclusions.get(li.categoryName);
            }
            result.add(copy);
        }
        return result;
    }

    private TransactionJournalDTO buildSimulationDTO(
        String lpmId, List<CartLineItem> lines, String tenderId
    ) {
        Loyalty_Program_Config__mdt cfg = [
            SELECT Default_Currency__c FROM Loyalty_Program_Config__mdt
            WHERE DeveloperName = 'Default' LIMIT 1
        ];

        TransactionJournalDTO dto = new TransactionJournalDTO();
        dto.lpmId          = lpmId;
        dto.journalTypeName = 'Purchase';
        dto.activityDate   = String.valueOf(Date.today());
        dto.currencyName   = cfg.Default_Currency__c;
        dto.tenderType     = tenderId;
        dto.lineItems      = lines;
        return dto;
    }

    private CartEvaluationResponse parseEvaluationResponse(Map<String, Object> raw) {
        CartEvaluationResponse resp = new CartEvaluationResponse();

        // The simulation response nests under transactionJournals[0]
        List<Object> journals = (List<Object>) raw.get('transactionJournals');
        if (journals == null || journals.isEmpty()) return resp;

        Map<String, Object> j = (Map<String, Object>) journals[0];
        Object pts = j.get('totalPointsAwarded');
        resp.estimatedPoints = pts != null ? Decimal.valueOf(String.valueOf(pts)) : 0;

        Object bonus = j.get('bonusPoints');
        resp.bonusPoints = bonus != null ? Decimal.valueOf(String.valueOf(bonus)) : 0;

        return resp;
    }

    @TestVisible
    private static Map<String, Boolean> getExclusionRules() {
        if (exclusionCache == null) {
            exclusionCache = new Map<String, Boolean>();
            for (Loyalty_Exclusion_Rule__mdt rule : [
                SELECT Product_Category__c, Is_Excluded__c
                FROM   Loyalty_Exclusion_Rule__mdt
                WHERE  Is_Excluded__c = true
            ]) {
                exclusionCache.put(rule.Product_Category__c, rule.Is_Excluded__c);
            }
        }
        return exclusionCache;
    }
}
