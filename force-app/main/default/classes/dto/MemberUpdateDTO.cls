/**
 * @description Payload for LoyaltyMemberService.updateMemberDetails.
 *              Only fields included in the map are sent to the LC API (partial update pattern).
 *              Set fields explicitly; null fields are omitted from the API request body.
 */
public with sharing class MemberUpdateDTO {

    public String  email           { get; set; }
    public String  phone           { get; set; }
    public String  firstName       { get; set; }
    public String  lastName        { get; set; }

    /** RCC card active flag — synced when Contact.RCC_Active__c changes */
    public Boolean rccActive       { get; set; }

    /** ISO country code — drives US/CA expiry rule evaluation */
    public String  countryCode     { get; set; }

    /** Member status override: ACTIVE | INACTIVE | SUSPENDED */
    public String  memberStatus    { get; set; }

    /**
     * @description Serialises only non-null fields into a map for the LC API request body.
     *              This prevents unintentional field-clearing on partial updates.
     */
    public Map<String, Object> toUpdateMap() {
        Map<String, Object> m = new Map<String, Object>();
        if (email         != null) m.put('email',         email);
        if (phone         != null) m.put('phone',         phone);
        if (firstName     != null) m.put('firstName',     firstName);
        if (lastName      != null) m.put('lastName',      lastName);
        if (rccActive     != null) m.put('rccActive',     rccActive);
        if (countryCode   != null) m.put('countryCode',   countryCode);
        if (memberStatus  != null) m.put('memberStatus',  memberStatus);
        return m;
    }
}
