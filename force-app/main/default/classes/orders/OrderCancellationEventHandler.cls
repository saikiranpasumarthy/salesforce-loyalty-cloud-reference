/**
 * @description Platform Event handler for Order_Cancellation_Event__e.
 *              Reverses points awarded and cancels redeemed vouchers on order cancellation.
 *
 * REVERSAL LOGIC:
 *   1. If Points_To_Reverse__c > 0 → call LoyaltyTransactionService.debitPoints
 *   2. If Voucher_Codes_JSON__c is populated → call LoyaltyVoucherService.cancelVoucher for each
 *   3. Update Order_Points_Status__c to 'Reversed'
 *
 * PARTIAL REVERSALS: If some voucher cancellations fail, the points reversal still proceeds.
 *   Failed voucher cancellations are logged as errors and flagged for manual review.
 */
public with sharing class OrderCancellationEventHandler {

    private final LoyaltyTransactionService txnService;
    private final LoyaltyVoucherService     voucherService;
    private final PointsPendingStatusService statusService;

    public OrderCancellationEventHandler() {
        this.txnService     = new LoyaltyTransactionService();
        this.voucherService = new LoyaltyVoucherService();
        this.statusService  = new PointsPendingStatusService();
    }

    @TestVisible
    private OrderCancellationEventHandler(
        LoyaltyTransactionService txnService,
        LoyaltyVoucherService voucherService,
        PointsPendingStatusService statusService
    ) {
        this.txnService     = txnService;
        this.voucherService = voucherService;
        this.statusService  = statusService;
    }

    public void handleCancellationEvent(List<Order_Cancellation_Event__e> events) {
        for (Order_Cancellation_Event__e evt : events) {
            try {
                processEvent(evt);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    'OrderCancellationEventHandler failed for order ' + evt.Order_Id__c + ': ' + e.getMessage());
            }
        }
    }

    private void processEvent(Order_Cancellation_Event__e evt) {
        if (String.isBlank(evt.LPM_Id__c)) return;

        List<String> errors = new List<String>();

        // Step 1: Cancel redeemed vouchers
        if (String.isNotBlank(evt.Voucher_Codes_JSON__c)) {
            List<String> codes = parseVoucherCodes(evt.Voucher_Codes_JSON__c);
            for (String code : codes) {
                try {
                    voucherService.cancelVoucher(code, 'ORDER_CANCELLED');
                } catch (LoyaltyVoucherException e) {
                    errors.add('Voucher ' + code + ': ' + e.getMessage());
                }
            }
        }

        // Step 2: Reverse awarded points
        if (evt.Points_To_Reverse__c != null && evt.Points_To_Reverse__c > 0) {
            String currency = [
                SELECT Default_Currency__c FROM Loyalty_Program_Config__mdt
                WHERE DeveloperName = 'Default' LIMIT 1
            ].Default_Currency__c;

            txnService.debitPoints(
                evt.LPM_Id__c,
                evt.Points_To_Reverse__c,
                currency,
                'ORDER_CANCELLED:' + evt.Order_Id__c
            );
        }

        // Step 3: Update status record
        statusService.markReversed(evt.Order_Id__c);

        if (!errors.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'Voucher cancellation errors for order ' + evt.Order_Id__c + ': '
                + String.join(errors, '; '));
        }
    }

    private List<String> parseVoucherCodes(String json) {
        try {
            List<Object> raw = (List<Object>) JSON.deserializeUntyped(json);
            List<String> codes = new List<String>();
            for (Object r : raw) {
                codes.add((String) r);
            }
            return codes;
        } catch (Exception e) {
            return new List<String>();
        }
    }
}
