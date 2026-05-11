/**
 * @description Schedulable class that triggers the RCC card batch processor.
 *
 * To schedule via Anonymous Apex:
 *   System.schedule('RCC Nightly Batch', '0 0 2 * * ?', new RCCBatchScheduler());
 *   // Runs daily at 02:00 AM
 *
 * Batch size of 50 balances:
 *   - LC API callout limits per transaction (100 max)
 *   - Heap and CPU time for Contact + LPM upserts
 *   - Allowing parallel batch chunks without callout contention
 */
public with sharing class RCCBatchScheduler implements Schedulable {

    private static final Integer BATCH_SIZE = 50;

    public void execute(SchedulableContext sc) {
        RCCCardBatchProcessor batch = new RCCCardBatchProcessor();
        Database.executeBatch(batch, BATCH_SIZE);
    }
}
