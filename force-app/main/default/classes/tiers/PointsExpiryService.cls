/**
 * @description Evaluates and processes annual points expiry for US members.
 *
 * EXPIRY RULES:
 *   - US members: if no qualifying purchase in the past 12 months, all points expire.
 *   - CA members: points never expire — isCAMember() returns true, skip processing.
 *   - A "qualifying purchase" is defined as an Order_Points_Status__c record with
 *     Status__c = 'Awarded' within the last 12 months (365 days).
 *   - Members with 0 points balance are skipped (no points to expire).
 *
 * Called from: PointsExpiryBatch (bulk processing), and ad-hoc from agent tools.
 */
public with sharing class PointsExpiryService {

    private final LoyaltyTransactionService txnService;
    private final LoyaltyMemberService      memberService;

    public PointsExpiryService() {
        this.txnService    = new LoyaltyTransactionService();
        this.memberService = new LoyaltyMemberService();
    }

    @TestVisible
    private PointsExpiryService(LoyaltyTransactionService txnService, LoyaltyMemberService memberService) {
        this.txnService    = txnService;
        this.memberService = memberService;
    }

    /**
     * @description Returns true if this member's points should be expired in the current run.
     *
     *   Eligible when ALL of:
     *   1. Member is a US member (not CA)
     *   2. No qualifying purchase in the last 12 months
     *   3. Current points balance > 0
     */
    public Boolean evaluateExpiryEligibility(Id contactId) {
        if (isCAMember(contactId)) return false;

        Contact c = [
            SELECT Loyalty_Member_Id__c
            FROM   Contact
            WHERE  Id = :contactId AND Has_Loyalty__c = true LIMIT 1
        ];

        if (c == null || String.isBlank(c.Loyalty_Member_Id__c)) return false;

        // Check qualifying purchase window
        Date lastPurchase = getLastQualifyingPurchaseDate(c.Loyalty_Member_Id__c);
        if (lastPurchase != null && lastPurchase >= Date.today().addDays(-365)) {
            return false; // qualifying purchase within window — skip
        }

        // Check if member has a non-zero balance
        try {
            MemberBenefitsResponse benefits = memberService.getRewardsPoints(c.Loyalty_Member_Id__c);
            return benefits.pointsBalance != null && benefits.pointsBalance > 0;
        } catch (LoyaltyAPIException e) {
            System.debug(LoggingLevel.WARN, 'evaluateExpiryEligibility: cannot read balance: ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Expires all points for the given member by debiting the full balance.
     *              Called only after evaluateExpiryEligibility returns true.
     */
    public void processExpiry(Id contactId) {
        Contact c = [
            SELECT Loyalty_Member_Id__c
            FROM   Contact
            WHERE  Id = :contactId LIMIT 1
        ];

        MemberBenefitsResponse benefits = memberService.getRewardsPoints(c.Loyalty_Member_Id__c);

        if (benefits.pointsBalance == null || benefits.pointsBalance <= 0) return;

        String currencyCode = [
            SELECT Currency_ISO_Code__c FROM Loyalty_Program_Config__mdt
            WHERE DeveloperName = 'Default' LIMIT 1
        ].Currency_ISO_Code__c;

        txnService.debitPoints(
            c.Loyalty_Member_Id__c,
            benefits.pointsBalance,
            currencyCode,
            'ANNUAL_EXPIRY:' + Date.today().year()
        );
    }

    /**
     * @description Returns true when the Contact's country code indicates a CA member.
     *              CA members are permanently exempt from points expiry.
     */
    public Boolean isCAMember(Id contactId) {
        List<Contact> contacts = [
            SELECT Country_Code__c FROM Contact WHERE Id = :contactId LIMIT 1
        ];
        return !contacts.isEmpty() && contacts[0].Country_Code__c == 'CA';
    }

    /**
     * @description Returns the date of the most recent qualifying purchase.
     *              Returns null if no qualifying purchases exist in the system.
     */
    public Date getLastQualifyingPurchaseDate(String lpmId) {
        List<Order_Points_Status__c> records = [
            SELECT CreatedDate
            FROM   Order_Points_Status__c
            WHERE  Contact__c IN (SELECT Id FROM Contact WHERE Loyalty_Member_Id__c = :lpmId)
            AND    Status__c = 'Awarded'
            ORDER  BY CreatedDate DESC
            LIMIT  1
        ];
        return records.isEmpty() ? null : records[0].CreatedDate.date();
    }
}
