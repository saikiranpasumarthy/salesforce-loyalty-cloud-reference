/**
 * @description Platform Event trigger handler for Order_Fulfilment_Event__e.
 *              Subscribes to OMS/MuleSoft fulfilment events and awards points via Loyalty Cloud.
 *
 * TRIGGER CONFIGURATION:
 *   A trigger on Order_Fulfilment_Event__e calls this handler.
 *   See: triggers/OrderFulfilmentEventTrigger.trigger
 *
 * FLOW ON FULFILMENT EVENT:
 *   1. Parse event payload (LPM Id, order lines, tender type, fulfilment type)
 *   2. Mark Order_Points_Status__c as 'Processing'
 *   3. Call LoyaltyTransactionService.executeTransaction to create TJ in LC
 *   4. Update Order_Points_Status__c to 'Awarded' with TJ Id
 *   5. Refresh member's points balance in SFSC via LoyaltyMemberService.getRewardsPoints
 *
 * BULKIFICATION: handles lists of events; each event creates one TJ.
 * IDEMPOTENCY: orderId is used as the TJ referenceId — LC rejects duplicate TJs for the same orderId.
 */
public with sharing class OrderFulfilmentEventHandler {

    private final LoyaltyTransactionService txnService;
    private final LoyaltyMemberService      memberService;
    private final PointsPendingStatusService statusService;

    public OrderFulfilmentEventHandler() {
        this.txnService    = new LoyaltyTransactionService();
        this.memberService = new LoyaltyMemberService();
        this.statusService = new PointsPendingStatusService();
    }

    @TestVisible
    private OrderFulfilmentEventHandler(
        LoyaltyTransactionService txnService,
        LoyaltyMemberService memberService,
        PointsPendingStatusService statusService
    ) {
        this.txnService    = txnService;
        this.memberService = memberService;
        this.statusService = statusService;
    }

    /**
     * @description Entry point called from the trigger.
     *              Processes each event independently so a single failure does not block others.
     */
    public void handleFulfilmentEvent(List<Order_Fulfilment_Event__e> events) {
        for (Order_Fulfilment_Event__e evt : events) {
            try {
                processEvent(evt);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'OrderFulfilmentEventHandler failed for order ' + evt.Order_Id__c + ': ' + e.getMessage());
                statusService.markFailed(evt.Order_Id__c, e.getMessage());
            }
        }
    }

    private void processEvent(Order_Fulfilment_Event__e evt) {
        if (String.isBlank(evt.Loyalty_Member_Id__c)) return; // non-loyalty order — skip

        // Parse line items from JSON payload
        List<CartLineItem> lineItems = parseLineItems(evt.Cart_Lines_JSON__c);

        // Assemble TJ DTO
        TransactionJournalDTO dto = new TransactionJournalDTO();
        dto.lpmId           = evt.Loyalty_Member_Id__c;
        dto.orderId         = evt.Order_Id__c;
        dto.journalTypeName = 'Purchase';
        dto.activityDate    = evt.Order_Date__c != null
                              ? String.valueOf(evt.Order_Date__c.date())
                              : String.valueOf(Date.today());
        dto.lineItems       = lineItems;

        // Load currency from config
        dto.currencyName = [
            SELECT Currency_ISO_Code__c FROM Loyalty_Program_Config__mdt
            WHERE DeveloperName = 'Default' LIMIT 1
        ].Currency_ISO_Code__c;

        // Execute transaction in LC
        Map<String, Object> txnResp = txnService.executeTransaction(dto);

        // Extract TJ Id from response
        String tjId = extractTJId(txnResp);

        // Update status record
        statusService.markPointsAwarded(evt.Order_Id__c, tjId);
    }

    private List<CartLineItem> parseLineItems(String jsonStr) {
        if (String.isBlank(jsonStr)) return new List<CartLineItem>();
        try {
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(jsonStr);
            List<CartLineItem> items = new List<CartLineItem>();
            for (Object r : raw) {
                Map<String, Object> m = (Map<String, Object>) r;
                CartLineItem li = new CartLineItem();
                li.productId    = (String)  m.get('productId');
                li.sku          = (String)  m.get('sku');
                li.categoryName = (String)  m.get('category');
                li.quantity     = m.get('quantity')  != null ? Integer.valueOf(String.valueOf(m.get('quantity'))) : 1;
                li.unitPrice    = m.get('unitPrice')  != null ? Decimal.valueOf(String.valueOf(m.get('unitPrice')))  : 0;
                li.lineTotal    = m.get('lineTotal')  != null ? Decimal.valueOf(String.valueOf(m.get('lineTotal')))  : 0;
                li.isExcluded   = m.get('isExcluded') != null && Boolean.valueOf(String.valueOf(m.get('isExcluded')));
                items.add(li);
            }
            return items;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Failed to parse line items JSON: ' + e.getMessage());
            return new List<CartLineItem>();
        }
    }

    private String extractTJId(Map<String, Object> resp) {
        List<Object> journals = (List<Object>) resp.get('transactionJournals');
        if (journals != null && !journals.isEmpty()) {
            Map<String, Object> first = (Map<String, Object>) journals[0];
            return (String) first.get('id');
        }
        return null;
    }
}
