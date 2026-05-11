/**
 * @description AuraEnabled controller for loyaltyTransactionHistory and loyaltyPointsAdjustment LWCs.
 *              Thin wrapper around LoyaltyTransactionService — no business logic here.
 */
public with sharing class LoyaltyTransactionController {

    /**
     * @description Returns paginated transaction history for a member.
     *
     * @param lpmId       Target member LPM Id
     * @param fromDate    ISO date string (YYYY-MM-DD) start filter
     * @param toDate      ISO date string (YYYY-MM-DD) end filter
     * @param typeFilter  Optional journal type filter (e.g. 'Purchase', 'Expiry')
     * @param pageSize    Number of records per page
     * @param pageToken   Pagination cursor from previous response
     * @return            Raw LC response map (serialized to JSON by the platform)
     */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getTransactionHistory(
        String  lpmId,
        String  fromDate,
        String  toDate,
        String  typeFilter,
        Integer pageSize,
        String  pageToken
    ) {
        try {
            Date fromDt = String.isBlank(fromDate) ? null : Date.valueOf(fromDate);
            Date toDt   = String.isBlank(toDate)   ? null : Date.valueOf(toDate);
            LoyaltyTransactionService svc = new LoyaltyTransactionService();
            return svc.getTransactionHistory(lpmId, fromDt, toDt, pageSize != null ? pageSize : 25);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Agent appeasement: credit or debit points for a member.
     *
     * @param lpmId          Target member LPM Id
     * @param adjustmentType 'Credit' or 'Debit'
     * @param amount         Positive integer number of points
     * @param reason         Mandatory audit reason
     * @param notes          Optional agent notes
     */
    @AuraEnabled
    public static void adjustPoints(
        String  lpmId,
        String  adjustmentType,
        Integer amount,
        String  reason,
        String  notes
    ) {
        try {
            String currencyName = [
                SELECT Currency_ISO_Code__c FROM Loyalty_Program_Config__mdt
                WHERE  DeveloperName = 'Default' LIMIT 1
            ].Currency_ISO_Code__c;

            LoyaltyTransactionService svc = new LoyaltyTransactionService();
            String auditReason = reason + (String.isBlank(notes) ? '' : ' — ' + notes);

            if (adjustmentType == 'Credit') {
                svc.creditPoints(lpmId, amount, currencyName, null, auditReason);
            } else {
                svc.debitPoints(lpmId, amount, currencyName, auditReason);
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
