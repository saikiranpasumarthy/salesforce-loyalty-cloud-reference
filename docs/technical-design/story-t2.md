# STORY-T2 — Promotion Enrollment Management

**RICEF ID:** T2 (code-inferred; not in RICEF spreadsheet) | **Type:** UI + API | **Complexity:** Medium | **Module:** SFSC, LC

## Business Purpose
Allow agents to view all LC promotions a member is eligible for or enrolled in, manually enroll the member in opt-in promotions, and opt members out of specific promotions for GDPR preference management or agent-assisted support — all from the Contact record page.

## Assumptions
- LC promotions are configured in the Loyalty Cloud program; this service reads and manages enrollment state
- `loyaltyPromoEnrollment` LWC is agent-facing (SFSC Service Cloud context)
- Promo code → promotion mapping for checkout (story 1.21) uses the same `enrollForPromotion` method but via `CheckoutService`, not this LWC
- `getMemberPromotions` returns LC-managed list; no local caching
- Enrollment status values from LC: `'Enrolled'`, `'Eligible'`, `'NotEligible'` (or similar LC-defined strings)
- `@api lpmId` must be set by the parent page or App Builder binding

## User Flow
1. Agent opens Contact record → `loyaltyPromoEnrollment` mounts
2. `connectedCallback` calls `getMemberPromotions(lpmId)` via Apex
3. LWC renders promotion list with status badges (Enrolled = success/green, others = default)
4. "Enroll" button available for non-enrolled promotions → `handleEnroll(evt)` → `enrollForPromotion`
5. "Opt Out" button available for enrolled promotions → `handleOptOut(evt)` → `optOutFromPromotion`
6. After each action: success toast shown; `loadPromotions()` re-called to refresh the list

## Components

**LWC:**
| Component | Purpose |
|---|---|
| `loyaltyPromoEnrollment` | Displays promotion list; Enroll/Opt-Out buttons per promotion; auto-refreshes list after each action |

**Apex:**
| Class | Method | Description |
|---|---|---|
| `LoyaltyPromotionController` | `getMemberPromotions(lpmId)` | `@AuraEnabled(cacheable=false)`; delegates to `LoyaltyPromotionService.getMemberPromotions` |
| `LoyaltyPromotionController` | `enrollForPromotion(lpmId, promotionId)` | `@AuraEnabled`; delegates to `LoyaltyPromotionService.enrollForPromotion` |
| `LoyaltyPromotionController` | `optOutFromPromotion(lpmId, promotionId)` | `@AuraEnabled`; delegates to `LoyaltyPromotionService.optOutFromPromotion` |
| `LoyaltyPromotionService` | `getMemberPromotions(lpmId)` | `GET /member-promotions?memberId={lpmId}` → `List<Map<String, Object>>` |
| `LoyaltyPromotionService` | `enrollForPromotion(lpmId, promotionId)` | `POST /program-processes/Enroll%20Promotions` |
| `LoyaltyPromotionService` | `optOutFromPromotion(lpmId, promotionId)` | `POST /program-processes/Opt%20Out%20Promotion` |
| `LoyaltyPromotionService` | `getPromotionsByTxn(txnJournalId)` | `GET /transaction-journals/{id}/promotions` — shows which promos contributed to a TJ |

**Flows:** None

**Platform Events:** None

**Objects/Fields:** None written — promotion state is managed entirely in LC

**Permission Sets:**
- `Loyalty_Agent` — view promotions
- `Loyalty_Admin` — enroll/opt-out (implied by business context; no explicit check in Apex)

## API Integration
| Operation | Endpoint | Method | Request | Response |
|---|---|---|---|---|
| Get member promotions | `/member-promotions?memberId={lpmId}` | GET | — | `{memberPromotions:[{promotionId, name, enrollmentStatus, ...}]}` |
| Enroll in promotion | `/program-processes/Enroll%20Promotions` | POST | `{memberId, promotionId}` | 200 OK |
| Opt out of promotion | `/program-processes/Opt%20Out%20Promotion` | POST | `{memberId, promotionId}` | 200 OK |
| Promotions by TJ | `/transaction-journals/{id}/promotions` | GET | — | `{promotions:[{promotionId, pointsAwarded}]}` |

## Execution Sequence
```
1. loyaltyPromoEnrollment.connectedCallback()
   → if (this.lpmId) this.loadPromotions()

2. loadPromotions()
   → isLoading = true
   → getMemberPromotions({lpmId})
   → LoyaltyPromotionController.getMemberPromotions(lpmId)
   → LoyaltyPromotionService.getMemberPromotions(lpmId)
   → LoyaltyAPIClient.get('/member-promotions?memberId=' + urlEncoded(lpmId))
   → Response: {memberPromotions: [{promotionId, name, enrollmentStatus, ...}]}
   → LWC maps to: {canEnroll, canOptOut, statusBadgeClass} per item
   → isLoading = false; render list

3. Agent clicks "Enroll" for promotion PROMO-001:
   → handleEnroll(evt); promoId = 'PROMO-001'
   → enrollForPromotion({lpmId, promotionId:'PROMO-001'})
   → LoyaltyPromotionController.enrollForPromotion(lpmId, 'PROMO-001')
   → LoyaltyPromotionService.enrollForPromotion(lpmId, 'PROMO-001')
   → POST /program-processes/Enroll%20Promotions {memberId, promotionId}
   → 200 OK
   → ShowToastEvent('Enrolled', 'Member enrolled in promotion.', 'success')
   → await this.loadPromotions()  [refresh list]

4. Agent clicks "Opt Out" for enrolled promotion PROMO-002:
   → handleOptOut(evt); promoId = 'PROMO-002'
   → optOutFromPromotion({lpmId, promotionId:'PROMO-002'})
   → POST /program-processes/Opt%20Out%20Promotion {memberId, promotionId}
   → 200 OK
   → ShowToastEvent('Opted Out', 'Member opted out of promotion.', 'success')
   → await this.loadPromotions()  [refresh list]
```

## Manual Setup Required
- `loyaltyPromoEnrollment` placed on Contact record page in App Builder
  - `@api lpmId` must be set — either via dynamic binding `{!Contact.Loyalty_Member_Id__c}` or by a parent wrapper component
  - Visibility: `Has_Loyalty__c = true`
- LC promotions configured in the Loyalty Cloud program console (this component only manages enrollment; promotions must be pre-defined in LC)
- Named Credential `Loyalty_Cloud_API` OAuth configured

## Error Handling
| Error | Handling |
|---|---|
| `getMemberPromotions` fails | Caught; `promotions = []`; component renders empty state (no error toast currently) |
| `enrollForPromotion` fails | `AuraHandledException` → `ShowToastEvent('Error', e.body?.message, 'error')` |
| `optOutFromPromotion` fails | `AuraHandledException` → `ShowToastEvent('Error', e.body?.message, 'error')` |
| `lpmId` not set | `connectedCallback` skips `loadPromotions`; empty list shown; no error |
| LC returns empty `memberPromotions` | `getMemberPromotions` returns `[]`; LWC shows "No promotions available" |

## Security
- `LoyaltyPromotionController` — `with sharing`
- `LoyaltyPromotionService` — `with sharing`
- No SFSC DML; all state changes go to LC via Named Credential
- No explicit admin permission check in Apex — agent with Apex access can call enroll/opt-out

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Member with 2 promotions | `lpmId` set; LC returns 2 promos (1 Enrolled, 1 Eligible) | List shows both; Enrolled has success badge + Opt Out button; Eligible has Enroll button |
| Enroll in promotion | Click Enroll for Eligible promo | LC POST called; success toast; list refreshed |
| Opt out of promotion | Click Opt Out for Enrolled promo | LC POST called; success toast; list refreshed |
| No promotions | LC returns empty list | Empty state shown |
| `lpmId` not set | `@api lpmId` is null | `loadPromotions` not called; empty list |
| LC enroll fails | LC returns 400 | Error toast with LC error message |
| `getPromotionsByTxn` | `txnJournalId` provided | LC returns promos that contributed to that TJ |

## Validation Queries
```sql
-- Members with active loyalty (would see promotions)
SELECT Id, Loyalty_Member_Id__c, Loyalty_Member_Type__c
FROM Contact WHERE Has_Loyalty__c = true LIMIT 20

-- No SFSC records for promotion enrollment — managed in LC
-- Verify via LC /member-promotions API directly for a specific lpmId
```

## Dependencies
- Story 1.7 — `lpmId` must be available from session data or Contact field; component requires it as `@api`
- Story 1.20/1.21 — `enrollForPromotion` is shared with `CheckoutService.validateAndRedeemPromoCode`; same LC process endpoint
- Named Credential `Loyalty_Cloud_API` configured

## Known Gaps
- **Silent failure on `getMemberPromotions` error**: `loadPromotions` catches and returns empty array; no error message displayed to the agent — they see an empty list without knowing if it's genuinely empty or a failed call
- **No SFSC record of enrollment**: promotion enrollment history is only in LC; there is no SFSC audit trail of which agent enrolled the member in which promotion
- **`getPromotionsByTxn` not wired to any LWC**: the method exists in `LoyaltyPromotionService` and `LoyaltyPromotionController` but no component calls it — displayed promotions per transaction are not surfaced in the agent UI
- **`@api lpmId` not auto-derived**: if placed on a Contact record page without dynamic binding, the `lpmId` prop is null and no promotions load; the placing admin must configure the binding in App Builder
