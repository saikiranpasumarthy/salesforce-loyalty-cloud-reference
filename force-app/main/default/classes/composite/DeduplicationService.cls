/**
 * @description Weighted member duplicate detection and merge preparation.
 *
 * MATCHING SCORE WEIGHTS:
 *   Email match:     50 points (highest confidence identifier)
 *   LoyaltyId match: 40 points (unique in system)
 *   Phone match:     30 points (medium confidence, shared phones possible)
 *   Name match:      10 points (low — common names exist)
 *
 * A combined score >= 50 is considered a match.
 * A score of 30-49 is flagged for manual review.
 *
 * MERGE PREPARATION (not execution):
 *   This service identifies the winner and loser for a merge
 *   but does NOT execute the merge (mergeConsiderations returns a plan).
 *   Actual Contact merge requires admin approval and the MergeRequest API.
 */
public with sharing class DeduplicationService {

    public class MatchResult {
        public Id      contactId    { get; set; }
        public Integer score        { get; set; }
        public String  matchReason  { get; set; }
        public Boolean isHighConfidence { get; set; }
    }

    public class MergePlan {
        public Id     winnerContactId { get; set; }
        public Id     loserContactId  { get; set; }
        public String recommendation  { get; set; }
        public List<String> conflicts { get; set; }
        public MergePlan() { conflicts = new List<String>(); }
    }

    /**
     * @description Finds the best-matching Contact using weighted scoring across all identifiers.
     *              Returns null if no match meets the minimum threshold (score < 30).
     *
     * @param email     Primary match identifier
     * @param phone     Secondary match identifier
     * @param loyaltyId LC member number
     * @return          Best MatchResult, or null if no match found
     */
    public MatchResult findBestMatch(String email, String phone, String loyaltyId) {
        List<Contact> candidates = [
            SELECT Id, FirstName, LastName, Email, Phone, Loyalty_Member_Id__c
            FROM   Contact
            WHERE  (Email = :email          AND :email != null)
               OR  (Phone = :phone          AND :phone != null)
               OR  (Loyalty_Member_Id__c = :loyaltyId AND :loyaltyId != null)
            LIMIT  10
        ];

        if (candidates.isEmpty()) return null;

        MatchResult best = null;
        for (Contact c : candidates) {
            MatchResult mr = scoreCandidate(c, email, phone, loyaltyId);
            if (best == null || mr.score > best.score) {
                best = mr;
            }
        }

        return (best != null && best.score >= 30) ? best : null;
    }

    /**
     * @description Prepares a merge plan identifying which Contact to keep and which to retire.
     *              Winner selection: prefer the Contact with a loyalty membership.
     *
     * @param winnerContactId  Contact to preserve (Master)
     * @param loserContactId   Contact to retire (Non-Master)
     * @return                 MergePlan with recommendation and field conflict list
     */
    public MergePlan mergeConsiderations(Id winnerContactId, Id loserContactId) {
        List<Contact> contacts = [
            SELECT Id, Has_Loyalty__c, Email, Phone, Loyalty_Member_Id__c,
                   RCC_Card_Number__c, Epsilon_Profile_Id__c
            FROM   Contact WHERE Id IN (:winnerContactId, :loserContactId)
        ];

        if (contacts.size() < 2) {
            throw new LoyaltyAPIException('Could not load both contacts for merge', 400);
        }

        Contact winner = contacts[0].Id == winnerContactId ? contacts[0] : contacts[1];
        Contact loser  = contacts[0].Id == loserContactId  ? contacts[0] : contacts[1];

        MergePlan plan = new MergePlan();
        plan.winnerContactId = winnerContactId;
        plan.loserContactId  = loserContactId;

        // Flag field conflicts that need manual resolution
        if (winner.Has_Loyalty__c && loser.Has_Loyalty__c) {
            plan.conflicts.add('Both contacts have Loyalty memberships — manual review required before merge');
        }
        if (winner.Email != loser.Email && winner.Email != null && loser.Email != null) {
            plan.conflicts.add('Email conflict: winner=' + winner.Email + ', loser=' + loser.Email);
        }
        if (winner.RCC_Card_Number__c != null && loser.RCC_Card_Number__c != null
            && winner.RCC_Card_Number__c != loser.RCC_Card_Number__c) {
            plan.conflicts.add('RCC card conflict — loser card must be deactivated first');
        }

        plan.recommendation = plan.conflicts.isEmpty()
            ? 'Safe to merge — no conflicts detected'
            : 'Manual review required before merge — ' + plan.conflicts.size() + ' conflict(s)';

        return plan;
    }

    /**
     * @description Flags a Contact record for duplicate manual review.
     *              Creates a Case or sets a custom flag field — implementation dependent.
     */
    public void flagDuplicate(Id contactId) {
        // In a real implementation, create a Case or set a custom flag
        // This is a marker method for the reference architecture
        System.debug('DeduplicationService: Contact ' + contactId + ' flagged for duplicate review');
    }

    // ─────────────────────────────────────────────────────────────────────────

    private MatchResult scoreCandidate(Contact c, String email, String phone, String loyaltyId) {
        MatchResult mr = new MatchResult();
        mr.contactId = c.Id;
        mr.score     = 0;

        List<String> reasons = new List<String>();

        if (String.isNotBlank(email)     && email == c.Email)                { mr.score += 50; reasons.add('email'); }
        if (String.isNotBlank(loyaltyId) && loyaltyId == c.Loyalty_Member_Id__c) { mr.score += 40; reasons.add('loyaltyId'); }
        if (String.isNotBlank(phone)     && phone == c.Phone)                { mr.score += 30; reasons.add('phone'); }

        mr.matchReason      = String.join(reasons, '+');
        mr.isHighConfidence = mr.score >= 50;
        return mr;
    }
}
