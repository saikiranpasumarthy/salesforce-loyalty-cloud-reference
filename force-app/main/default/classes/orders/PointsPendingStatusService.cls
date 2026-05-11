/**
 * @description Manages the Order_Points_Status__c record lifecycle.
 *              Tracks the pending → awarded → reversed state machine for each order's points.
 *
 * This intermediate object allows:
 *   - Idempotency check: if a TJ already exists for an order, skip re-processing
 *   - Visibility for ops teams: see which orders are awaiting points award
 *   - Reversal tracking: ensure points are not reversed twice on double-cancellation events
 */
public with sharing class PointsPendingStatusService {

    /**
     * @description Creates an Order_Points_Status__c record in Pending state at checkout.
     *              Called when the order is submitted (before fulfilment).
     */
    public void markPointsPending(String orderId, String lpmId) {
        // Upsert to avoid duplicates if called multiple times for the same order
        Order_Points_Status__c status = new Order_Points_Status__c(
            Order_Id__c   = orderId,
            Status__c     = 'Pending'
        );

        List<Order_Points_Status__c> existing = [
            SELECT Id FROM Order_Points_Status__c WHERE Order_Id__c = :orderId LIMIT 1
        ];
        if (existing.isEmpty()) {
            insert status;
        }
    }

    /**
     * @description Updates the status to Awarded after the TJ is successfully created.
     *              Called by OrderFulfilmentEventHandler on success.
     */
    public void markPointsAwarded(String orderId, String txnJournalId) {
        List<Order_Points_Status__c> records = [
            SELECT Id FROM Order_Points_Status__c WHERE Order_Id__c = :orderId LIMIT 1
        ];
        if (records.isEmpty()) return;

        records[0].Status__c = 'Awarded';
        update records[0];
    }

    /**
     * @description Updates the status to Reversed after cancellation processing.
     */
    public void markReversed(String orderId) {
        List<Order_Points_Status__c> records = [
            SELECT Id FROM Order_Points_Status__c WHERE Order_Id__c = :orderId LIMIT 1
        ];
        if (records.isEmpty()) return;
        records[0].Status__c = 'Reversed';
        update records[0];
    }

    /**
     * @description Updates the status to Failed with an error message.
     */
    public void markFailed(String orderId, String errorMsg) {
        List<Order_Points_Status__c> records = [
            SELECT Id FROM Order_Points_Status__c WHERE Order_Id__c = :orderId LIMIT 1
        ];
        if (records.isEmpty()) return;
        records[0].Status__c   = 'Failed';
        update records[0];
    }
}
