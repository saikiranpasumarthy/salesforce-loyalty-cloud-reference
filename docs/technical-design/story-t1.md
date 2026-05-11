# STORY-T1 — Tier Management & Legacy Tier Mapping

**RICEF ID:** T1 (code-inferred; not in RICEF spreadsheet) | **Type:** UI + Services | **Complexity:** Medium | **Module:** SFSC, LC

## Business Purpose
Allow admins to manually override a member's tier in Loyalty Cloud via the `loyaltyTierManagement` LWC, and map the legacy 6-tier program model to the current 2-tier model (Preferred/Elite) via `TierMappingService` — supporting both the RCC batch migration and real-time lookups by POS/downstream systems.

## Assumptions
- `loyaltyTierManagement` is exposed only to users with `Loyalty_Admin` permission set
- Tier override requires a mandatory `reason` string for audit purposes — empty reason blocks save
- `LoyaltyMemberService.updateMemberTier` makes the actual LC API call
- `TierMappingService` reads from `Tier_Mapping__mdt` CMDT; lazy-loaded per Apex transaction
- 8 legacy codes map to 6 combinations of `{Preferred|Elite} × {Retail|Pro|Student}`; `Not_Converted` defaults to Preferred/Retail
- `TierMappingService` is called by `RCCCardBatchProcessor` for tier assignment during batch

## User Flow

### Manual Tier Override:
1. Admin opens Contact record → `loyaltyTierManagement` component visible (Loyalty_Admin audience)
2. Admin sees current tier badge (Preferred = green, Elite = amber)
3. Admin selects new tier from picklist (Preferred / Elite) and enters an override reason
4. Admin clicks "Update Tier" → `LoyaltyTierController.updateMemberTier(lpmId, tier, reason)` called
5. LC API call updates the LPM tier → toast shown → `tierupdated` custom event fired
6. Parent component (e.g., `loyaltyMemberDashboard`) may handle `tierupdated` to trigger a refresh

### Legacy Tier Mapping (batch/integration):
1. `RCCCardBatchProcessor` or integration layer calls `TierMappingService.mapLegacyTier(legacyCode)`
2. CMDT loaded once per transaction: `Tier_Mapping__mdt` → Map by `Legacy_Code__c`
3. Returns `TierResult{tier, memberType}` — default Preferred/Retail if code not found
4. For POS reverse lookup: `getDownstreamGroupCode(tier, memberType)` returns legacy code for POS systems

## Components

**LWC:**
| Component | Purpose |
|---|---|
| `loyaltyTierManagement` | Admin-only tier override modal; picklist (Preferred/Elite) + reason textarea + Update Tier button; fires `tierupdated` custom event on success |

**Apex:**
| Class | Method | Description |
|---|---|---|
| `LoyaltyTierController` | `updateMemberTier(lpmId, tier, reason)` | `@AuraEnabled`; thin wrapper; calls `LoyaltyMemberService.updateMemberTier` |
| `TierMappingService` | `mapLegacyTier(legacyTierCode)` | CMDT lookup → `TierResult{tier, memberType}`; default Preferred/Retail |
| `TierMappingService` | `getDownstreamGroupCode(tier, memberType)` | Reverse map → legacy code for POS compatibility |
| `TierMappingService` | `getAllLegacyCodes()` | Returns all CMDT keys; used for batch migration validation |
| `LoyaltyMemberService` | `updateMemberTier(lpmId, tier, reason)` | `PATCH /loyalty-program-members/{lpmId}` — updates LPM tier in LC |

**Flows:** None (tier management is LWC-driven)

**Platform Events:** None

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Contact` | `Loyalty_Member_Id__c` | None (tier stored in LC, not SFSC) |

**Custom Metadata:**
- `Tier_Mapping__mdt` — 8 records; fields: `Legacy_Code__c`, `Canonical_Tier__c` (Preferred|Elite), `Member_Type__c` (Retail|Pro|Student)

| DeveloperName | Legacy_Code__c | Canonical_Tier__c | Member_Type__c |
|---|---|---|---|
| Upper | Upper | Elite | Retail |
| Base | Base | Preferred | Retail |
| Conversion | Conversion | Preferred | Retail |
| Pro_Elite | Pro_Elite | Elite | Pro |
| Student_Elite | Student_Elite | Elite | Student |
| Pro_Preferred | Pro_Preferred | Preferred | Pro |
| Student_Preferred | Student_Preferred | Preferred | Student |
| Not_Converted | Not_Converted | Preferred | Retail |

**Permission Sets:**
- `Loyalty_Admin` — required for `loyaltyTierManagement` (App Builder Audience + Apex class access)

## API Integration
| Operation | Endpoint | Method | Key Request Fields | Key Response Fields |
|---|---|---|---|---|
| Update member tier | `PATCH /loyalty-program-members/{lpmId}` | PATCH | `tier`, `reason` | 200 OK |

## Execution Sequence

### LWC tier override:
```
1. Admin opens loyaltyTierManagement; current tier shown (passed via @api currentTier)
2. handleTierChange(evt) → selectedTier = 'Elite'
3. handleReasonChange(evt) → overrideReason = 'Annual tier review - meets Elite threshold'
4. handleSave() [isSaveDisabled: false because both selectedTier and overrideReason set]
5.   → updateMemberTier({lpmId, tier:'Elite', reason:'Annual tier review...'})
6.   → LoyaltyTierController.updateMemberTier(lpmId, 'Elite', reason)
7.   → LoyaltyMemberService.updateMemberTier(lpmId, 'Elite', reason)
8.   → LoyaltyAPIClient.patch('/loyalty-program-members/' + lpmId, payload)
9.   → Named Credential PATCH → LC returns 200
10.  → ShowToastEvent('Tier Updated', 'Member tier changed to Elite.', 'success')
11.  → dispatchEvent(new CustomEvent('tierupdated', {detail: {newTier:'Elite'}}))
12.  → selectedTier = ''; overrideReason = ''  [reset form]
```

### Legacy mapping (batch/integration):
```
1. RCCCardBatchProcessor calls TierMappingService.mapLegacyTier('Pro_Elite')
2.   → getTierMap() — static cache miss on first call
3.   → SOQL: Tier_Mapping__mdt [all records] → Map<legacyCode, CMDT>
4.   → tierMap.get('Pro_Elite') → {Canonical_Tier__c='Elite', Member_Type__c='Pro'}
5.   → return TierResult{tier='Elite', memberType='Pro'}
6. Caller sets Contact.Loyalty_Member_Type__c = 'Pro'
   and calls LoyaltyMemberService.updateMemberTier(lpmId, 'Elite', reason)
```

## Manual Setup Required
- `Tier_Mapping__mdt` records deployed (8 records included in source)
- `loyaltyTierManagement` placed on Contact record page in App Builder
  - Audience: `Loyalty_Admin` permission set (restrict visibility to admins only)
  - Wire `@api lpmId` from parent component or set via property panel (requires `Loyalty_Member_Id__c`)
- `Loyalty_Admin` permission set assigned to admin users

## Error Handling
| Error | Handling |
|---|---|
| `selectedTier` or `overrideReason` empty | `isSaveDisabled = true`; button disabled; `handleSave` returns early |
| LC `updateMemberTier` fails | `AuraHandledException` thrown; `errorMessage` set in LWC; inline error shown |
| CMDT returns no record for legacy code | `mapLegacyTier` returns default `TierResult{Preferred, Retail}` |
| `lpmId` not set on LWC | `handleSave` sends null `lpmId` → LC returns 400/404 → error toast |

## Security
- `LoyaltyTierController` — `with sharing`; no explicit permission check in Apex — relies entirely on App Builder Audience for `loyaltyTierManagement` visibility
- `TierMappingService` — `with sharing`; reads CMDT only (no Contact DML)
- CMDT is org-level data; no member-specific PII in tier mappings

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Override to Elite | `lpmId=MBR-001`, `tier='Elite'`, `reason='Approved'` | LC PATCH called; success toast; `tierupdated` event fired |
| Empty reason | `tier='Preferred'`, `reason=''` | Save button disabled; no Apex call |
| LC tier update fails | LC mock returns 500 | `errorMessage` displayed; toast not shown |
| Map legacy `Pro_Elite` | `mapLegacyTier('Pro_Elite')` | Returns `{tier:'Elite', memberType:'Pro'}` |
| Map unknown code | `mapLegacyTier('Unknown')` | Returns default `{tier:'Preferred', memberType:'Retail'}` |
| Reverse lookup | `getDownstreamGroupCode('Elite', 'Pro')` | Returns `'Pro_Elite'` |

## Validation Queries
```sql
-- Tier_Mapping__mdt records deployed
SELECT DeveloperName, Legacy_Code__c, Canonical_Tier__c, Member_Type__c
FROM Tier_Mapping__mdt

-- Members with Elite tier (verify LC sync)
SELECT Id, Loyalty_Member_Type__c, Loyalty_Member_Id__c
FROM Contact WHERE Has_Loyalty__c = true AND Loyalty_Member_Type__c IN ('Pro','Student')

-- Contacts whose tier was recently updated (no audit trail in SFSC — must check LC TJ)
SELECT Id, LastModifiedDate, Loyalty_Member_Type__c FROM Contact
WHERE LastModifiedDate = TODAY AND Has_Loyalty__c = true
```

## Dependencies
- `LoyaltyMemberService.updateMemberTier` — LC PATCH endpoint; must be wired to correct LC program process
- `Tier_Mapping__mdt` records deployed before RCC batch runs
- Story 1.4 — `RCCCardBatchProcessor` calls `TierMappingService.mapLegacyTier` during enrollment

## Known Gaps
- **No admin permission guard in Apex**: `LoyaltyTierController.updateMemberTier` has no `FeatureManagement.checkPermission` or Custom Permission check — any user who can call the Apex class (e.g., via Execute Anonymous) can override any member's tier; security relies solely on App Builder Audience
- **No audit trail in SFSC**: tier changes are applied directly to LC with a `reason` string; no `Tier_Change_History__c` record or `Privacy_Audit_Log__c` entry is written — the change is only visible in LC's TJ history
- **`tierupdated` event not handled by `loyaltyMemberDashboard`**: the dashboard does not listen for this event; the tier display on screen only updates after the next page load or explicit cache refresh
- **PATCH endpoint assumed**: `LoyaltyMemberService.updateMemberTier` is called in `LoyaltyTierController` but the LC API endpoint is not documented in the source — verify against LC API docs for the correct endpoint and payload for tier override
