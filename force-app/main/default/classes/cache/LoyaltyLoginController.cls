/**
 * @description AuraEnabled controller called on authenticated session start to pre-load loyalty data.
 *              Designed for login-time hydration of the loyaltyDataService LWC utility module.
 *
 * PERFORMANCE NOTE: getSessionLoyaltyData triggers at most 2 LC API calls (benefits + vouchers)
 * and uses the Platform Cache for subsequent calls within the 30-minute TTL window.
 */
public with sharing class LoyaltyLoginController {

    private final LoyaltySessionCacheService cacheService;

    public LoyaltyLoginController() {
        this.cacheService = new LoyaltySessionCacheService();
    }

    /**
     * @description Entry point for login-time loyalty data hydration.
     *              Called from loyaltyDataService.js on component connectedCallback.
     *
     * @param contactId SFSC Contact Id (passed from the authenticated page context)
     * @return          MemberSessionData object; hasLoyalty=false if not enrolled
     */
    @AuraEnabled(cacheable=false)  // cacheable=false because data changes on point earn/redeem
    public static MemberSessionData getSessionLoyaltyData(Id contactId) {
        try {
            LoyaltySessionCacheService svc = new LoyaltySessionCacheService();
            return svc.getMemberData(contactId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'getSessionLoyaltyData error: ' + e.getMessage());
            return new MemberSessionData();
        }
    }

    /**
     * @description Lightweight check — returns true if the Contact has an active LPM.
     *              Used by loyaltyJoinCta LWC to show/hide the "Join Rewards" CTA.
     *              Cacheable = true because enrollment status rarely changes within a session.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean hasLoyaltyMembership(Id contactId) {
        try {
            List<Contact> contacts = [
                SELECT Has_Loyalty__c
                FROM   Contact
                WHERE  Id = :contactId
                LIMIT  1
            ];
            return !contacts.isEmpty() && contacts[0].Has_Loyalty__c;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * @description Forces a cache refresh for the given Contact.
     *              Called by agent after making changes (tier override, point adjustment).
     *
     * @return Refreshed MemberSessionData
     */
    @AuraEnabled
    public static MemberSessionData refreshLoyaltyData(Id contactId) {
        try {
            LoyaltySessionCacheService svc = new LoyaltySessionCacheService();
            return svc.refreshMemberData(contactId);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'refreshLoyaltyData error: ' + e.getMessage());
            return new MemberSessionData();
        }
    }
}
