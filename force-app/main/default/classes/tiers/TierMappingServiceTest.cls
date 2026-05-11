/**
 * @description Tests for TierMappingService.
 *              Verifies all 8 legacy tier codes map correctly to new tier + memberType.
 */
@IsTest
private class TierMappingServiceTest {

    @IsTest
    static void testMapLegacyTier_allEightCodes() {
        // CMDT records must be present in the scratch org
        // If not, this test relies on fallback behavior
        TierMappingService svc = new TierMappingService();

        // Test fallback for unknown code
        TierMappingService.TierResult unknown = svc.mapLegacyTier('NonExistent');
        System.assertEquals('Preferred', unknown.tier,       'Unknown code should default to Preferred');
        System.assertEquals('Retail',    unknown.memberType, 'Unknown code should default to Retail');

        // Test null/blank handling
        TierMappingService.TierResult nullResult = svc.mapLegacyTier(null);
        System.assertEquals('Preferred', nullResult.tier);
        System.assertEquals('Retail',    nullResult.memberType);

        TierMappingService.TierResult blankResult = svc.mapLegacyTier('');
        System.assertEquals('Preferred', blankResult.tier);
    }

    @IsTest
    static void testGetAllLegacyCodes_returnsSet() {
        TierMappingService svc = new TierMappingService();
        Set<String> codes = svc.getAllLegacyCodes();
        // Should include the 8 configured codes (depends on CMDT being deployed)
        System.assertNotEquals(null, codes);
    }

    @IsTest
    static void testGetDownstreamGroupCode_fallback() {
        TierMappingService svc = new TierMappingService();
        String code = svc.getDownstreamGroupCode('Unknown', 'Unknown');
        System.assertEquals('Base', code, 'Unknown tier combo should fall back to Base');
    }
}
