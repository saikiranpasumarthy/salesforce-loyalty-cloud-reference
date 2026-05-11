/**
 * @description Schedulable class for the annual points expiry batch.
 *
 * To schedule via Anonymous Apex:
 *   System.schedule('Annual Points Expiry', '0 0 3 1 1 ?', new PointsExpiryScheduler());
 *   // Runs at 03:00 AM on January 1 of every year
 */
public with sharing class PointsExpiryScheduler implements Schedulable {

    private static final Integer BATCH_SIZE = 25; // smaller batch size to accommodate LC API callouts

    public void execute(SchedulableContext sc) {
        PointsExpiryBatch batch = new PointsExpiryBatch();
        Database.executeBatch(batch, BATCH_SIZE);
    }
}
