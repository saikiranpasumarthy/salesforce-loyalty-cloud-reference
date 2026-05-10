/**
 * @description Maps legacy 6-tier program codes to the new 2-tier model (Preferred/Elite).
 *              Also provides the reverse map for downstream POS and legacy system compatibility.
 *
 * LEGACY TIER MAP (from Tier_Mapping__mdt):
 *   Upper               → Elite   / Retail
 *   Base                → Preferred / Retail
 *   Conversion          → Preferred / Retail
 *   Pro_Elite           → Elite   / Pro
 *   Student_Elite       → Elite   / Student
 *   Pro_Preferred       → Preferred / Pro
 *   Student_Preferred   → Preferred / Student
 *   Not_Converted       → Preferred / Retail
 *
 * This class loads mappings from Tier_Mapping__mdt so the business can update
 * tier logic without a code deployment.
 */
public with sharing class TierMappingService {

    /** Result type returned by mapLegacyTier */
    public class TierResult {
        public String tier       { get; set; } // 'Preferred' | 'Elite'
        public String memberType { get; set; } // 'Retail' | 'Pro' | 'Student'
    }

    // Lazy-loaded from CMDT
    private static Map<String, Tier_Mapping__mdt> tierMap;

    /**
     * @description Maps a legacy tier code to the new tier + memberType pair.
     *
     * @param legacyTierCode  One of the 8 legacy codes
     * @return                TierResult with tier and memberType, or Preferred/Retail as default
     */
    public TierResult mapLegacyTier(String legacyTierCode) {
        Map<String, Tier_Mapping__mdt> map = getTierMap();

        TierResult result = new TierResult();
        result.tier       = 'Preferred'; // safe default
        result.memberType = 'Retail';

        if (String.isBlank(legacyTierCode)) return result;

        Tier_Mapping__mdt mapping = map.get(legacyTierCode.trim());
        if (mapping != null) {
            result.tier       = mapping.New_Tier__c;
            result.memberType = mapping.Member_Type__c;
        }

        return result;
    }

    /**
     * @description Reverse map: given a new tier and member type, returns the legacy group code.
     *              Used when writing back to POS systems that still expect legacy codes.
     *
     * @param tier       'Preferred' | 'Elite'
     * @param memberType 'Retail' | 'Pro' | 'Student'
     * @return           Legacy downstream group code (e.g. 'Upper', 'Pro_Elite')
     */
    public String getDownstreamGroupCode(String tier, String memberType) {
        for (Tier_Mapping__mdt mapping : getTierMap().values()) {
            if (mapping.New_Tier__c == tier && mapping.Member_Type__c == memberType) {
                return mapping.Downstream_Group_Code__c;
            }
        }
        return 'Base'; // fallback
    }

    /**
     * @description Returns all legacy codes as a Set — useful for batch migration validation.
     */
    public Set<String> getAllLegacyCodes() {
        return getTierMap().keySet();
    }

    // ─────────────────────────────────────────────────────────────────────────

    private static Map<String, Tier_Mapping__mdt> getTierMap() {
        if (tierMap == null) {
            tierMap = new Map<String, Tier_Mapping__mdt>();
            for (Tier_Mapping__mdt m : [
                SELECT DeveloperName, Legacy_Code__c, New_Tier__c,
                       Member_Type__c, Downstream_Group_Code__c
                FROM   Tier_Mapping__mdt
            ]) {
                tierMap.put(m.Legacy_Code__c, m);
            }
        }
        return tierMap;
    }
}
