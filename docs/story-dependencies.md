# Story Dependencies

Per-story listing of hard and soft dependencies. **Hard** = will fail at runtime without the dependency. **Soft** = degrades gracefully or is only relevant in certain paths.

---

## 1.1 — New Account Enrollment

| Dependency | Type | Reason |
|---|---|---|
| Named Credential `Loyalty_Cloud_API` | Hard | All LC API calls fail without OAuth token |
| `Loyalty_Program_Config__mdt` Default record | Hard | `Program_API_Name__c` required for LC enrollment endpoint |
| `ContactMatchService` | Hard | Called inside `enrollNewMember` to match or create Contact |
| `Welcome_Email_Trigger_Flow` | Soft | Welcome email not sent without flow, but enrollment succeeds |
| `Loyalty_Agent` permission set | Hard | Apex class access denied without it |

---

## 1.2 — Existing User Enrollment

| Dependency | Type | Reason |
|---|---|---|
| Story 1.1 infrastructure | Hard | Shares `LoyaltyEnrollmentService`; same Named Credential requirement |
| Contact already exists in SFSC | Hard | `enrollExistingMember(contactId, ...)` requires a real Contact Id |
| `Loyalty_Program_Config__mdt` Default | Hard | Program name for LC API |
| Story 1.7 | Soft | After enrollment, session cache is stale until next login or explicit refresh |

---

## 1.3 — Enrollment via Event (Epsilon Attribution)

| Dependency | Type | Reason |
|---|---|---|
| Story 1.1 | Hard | Identical code path; story 1.3 is an extension |
| `Contact.Epsilon_Profile_Id__c` field | Hard | Field must exist on Contact schema |
| Epsilon system | Soft | `epsilonProfileId` may be null; enrollment still completes |

---

## 1.4/1.5/1.6 — RCC Card Batch

| Dependency | Type | Reason |
|---|---|---|
| `Batch_Run_Log__c` custom object | Hard | `finish()` DML insert fails without this object |
| `Tier_Mapping__mdt` records (8) | Hard | Tier assignment fails without CMDT records |
| `LoyaltyEnrollmentService` | Hard | Calls `enrollExistingMember` for each RCC card holder |
| Named Credential `Loyalty_Cloud_API` | Hard | LC enrollment API |
| `RCC_LPM_Attribute_Update_Flow` | Soft | Cache refresh after batch update; without it, agents see stale data |
| Story 1.7 | Soft | Cache refresh only meaningful if session cache is active |
| `RCCBatchScheduler` scheduled job | Hard | Batch never runs without scheduler; must be manually scheduled |

---

## 1.7 — Session Cache / Login Loyalty Data

| Dependency | Type | Reason |
|---|---|---|
| Named Credential `Loyalty_Cloud_API` | Hard | Both LC API calls fail without it |
| Platform Cache partition `local.LoyaltyMemberData` | Soft | Falls back to direct LC calls on every request if partition missing |
| `Contact.Has_Loyalty__c`, `Loyalty_Member_Id__c` | Hard | Fields must exist; cache returns empty if these are null |
| `LoyaltyMemberService.getRewardsPoints` | Hard | Benefits call is one of the two primary cache-fill operations |
| `LoyaltyVoucherService.getMemberVouchers` | Hard | Voucher call is the second cache-fill operation |
| Stories 1.8/1.9/1.17/1.19/1.20/1.25/1.26/1.27 | Soft | All downstream stories consume the session cache; they degrade gracefully on cache miss |

---

## 1.8/1.9/1.10/1.11 — Rewards Dashboard

| Dependency | Type | Reason |
|---|---|---|
| Story 1.7 | Hard | Dashboard reads from `loyaltyDataService` JS cache populated at login |
| `loyaltyDataService` LWC module | Hard | Shared service module; all 5 dashboard LWCs import from it |
| Named Credential `Loyalty_Cloud_API` | Hard | Cache miss triggers direct LC calls |
| `LoyaltyTransactionService.getTransactionHistory` | Hard | `loyaltyTransactionHistory` component fails without this |
| Story 1.26 | Soft | `loyaltyBarcodeDisplay` is a sibling component; dashboard functions without it |

---

## 1.17 — Points Earn Preview

| Dependency | Type | Reason |
|---|---|---|
| Story 1.7 | Hard | `lpmId` comes from session data; without it, LC returns 400 |
| `Loyalty_Exclusion_Rule__mdt` (4 records) | Hard | Exclusion rules not applied without CMDT; all items sent to LC (not a hard failure, but incorrect behavior) |
| `Loyalty_Program_Config__mdt` Default | Hard | `Currency_ISO_Code__c` required for TJ payload |
| Named Credential `Loyalty_Cloud_API` | Hard | Simulation call fails |
| Story 1.19 | Soft | RCC bonus preview only works if `tenderId = 'RCC'` is passed; base simulation works without story 1.19 |

---

## 1.19 — Award Bonus Points: RCC Tender

| Dependency | Type | Reason |
|---|---|---|
| Story 1.4 | Hard | `RCC_Active__c` field set by RCC batch; without it, RCC bonus cannot be offered |
| Story 1.17 | Soft | Cart simulation shows RCC bonus; fulfilment works without simulation being correct |
| Story 1.25 | Hard | TJ is created at fulfilment; `tenderType` field must be set by `OrderFulfilmentEventHandler` |
| LC Earn Rule for RCC | Hard | Bonus not applied unless the "RCC Bonus" earn rule is configured in LC program console |

---

## 1.20/1.21 — Certificate Redemption + Promo Code

| Dependency | Type | Reason |
|---|---|---|
| Story 1.7 | Hard | Member voucher list loaded at login; `lpmId` from session |
| Story 1.25 | Hard | Cancellation reversal calls `cancelVoucher`; both must deploy together |
| `Loyalty_Exclusion_Rule__mdt` | Soft | Used as promo code lookup stub (story 1.21); not required for certificate redemption (1.20) |
| Named Credential `Loyalty_Cloud_API` | Hard | All voucher API calls |
| `LoyaltyVoucherService` | Hard | `validateVoucher`, `redeemVoucher`, `cancelVoucher` all required |

---

## 1.25 — Order Points Award & Reversal

| Dependency | Type | Reason |
|---|---|---|
| Apex trigger on `Order_Fulfilment_Event__e` | **Critical** | Handler class exists but trigger file is NOT in repo; must be created separately |
| Apex trigger on `Order_Cancellation_Event__e` | **Critical** | Same — trigger not in repo |
| `CheckoutService.markPointsPending` | Hard | Must be called at checkout before fulfilment; otherwise `markPointsAwarded` silently no-ops |
| `Loyalty_Program_Config__mdt` Default | Hard | Currency required for TJ payload |
| Named Credential `Loyalty_Cloud_API` | Hard | TJ execution and debit calls |
| Story 1.20 | Hard | `LoyaltyVoucherService.cancelVoucher` used in cancellation reversal |
| Story 1.7 | Soft | Session cache refresh not called after points award; balance stays stale |

---

## 1.26 — App Barcode

| Dependency | Type | Reason |
|---|---|---|
| `JsBarcode` static resource | Hard | Component renders nothing without the library |
| `Contact.Loyalty_Member_Id__c` | Hard | Barcode has nothing to encode without the loyalty ID |
| Story 1.1/1.2 | Soft | Member must be enrolled for `Loyalty_Member_Id__c` to be populated |

---

## 1.27 — Composite API / POS Lookup / Deduplication

| Dependency | Type | Reason |
|---|---|---|
| Story 1.7 | Hard | `LoyaltyLookupController` uses `LoyaltySessionCacheService`; without it, falls back to direct LC calls |
| Named Credential `Loyalty_Cloud_API` | Hard | Composite API makes LC calls |
| `LoyaltyMemberService.getRewardsPoints` | Hard | Composite API benefits call |
| `LoyaltyVoucherService.getMemberVouchers` | Hard | Composite API voucher call |
| Connected App for POS OAuth | Hard | REST endpoints require auth; unauthenticated callers get 401 |

---

## 3.1 — Privacy Deletion

| Dependency | Type | Reason |
|---|---|---|
| `Privacy_Request__c` custom object | Hard | `ensurePrivacyRequest` DML fails without object |
| `Privacy_Audit_Log__c` custom object | Hard | All audit log inserts fail without object; MD child of `Privacy_Request__c` |
| Named Credential `Loyalty_Cloud_API` | Hard | `cancelVoucher` and `unenrollMember` calls |
| `LoyaltyVoucherService.getMemberVouchers` | Hard | Phase 1 voucher cancellation |
| `LoyaltyMemberService.unenrollMember` | Hard | Phase 1 LC unenroll |
| `Privacy_Request_Handler_Flow` | Soft | Flow-triggered path only; API path (OneTrust webhook) works independently |
| Connected App for OneTrust OAuth | Hard | `PrivacyDeletionAPIController` requires authenticated callin |

---

## T1 — Tier Management

| Dependency | Type | Reason |
|---|---|---|
| `Tier_Mapping__mdt` (8 records) | Hard | `mapLegacyTier` returns default for all codes if CMDT missing |
| `LoyaltyMemberService.updateMemberTier` | Hard | Tier override calls LC; method must be implemented |
| `Loyalty_Admin` permission set + App Builder Audience | Hard | Without audience, all agents can see and use the tier override |
| Story 1.4 | Soft | `TierMappingService` called by RCC batch; T1 also exposes it standalone |

---

## T2 — Promotion Enrollment

| Dependency | Type | Reason |
|---|---|---|
| Story 1.7 | Hard | `lpmId` from session data required; component no-ops if null |
| Named Credential `Loyalty_Cloud_API` | Hard | All promotion API calls |
| LC promotions configured in program | Hard | No promotions to list or enroll in without LC configuration |
| Story 1.20/1.21 | Soft | `enrollForPromotion` is shared with `CheckoutService.validateAndRedeemPromoCode`; T2 functions independently |

---

## T3 — Annual Points Expiry Batch

| Dependency | Type | Reason |
|---|---|---|
| `Batch_Run_Log__c` custom object | Hard | `finish()` fails without object |
| `Order_Points_Status__c.Contact__c` field | Hard | `getLastQualifyingPurchaseDate` subquery references this field; must be populated by story 1.25 |
| `Loyalty_Program_Config__mdt` Default | Hard | Currency required for `debitPoints` call |
| Named Credential `Loyalty_Cloud_API` | Hard | Balance check and debit calls |
| Story 1.25 | Hard | `Order_Points_Status__c` records with `Status='Awarded'` are the qualifying purchase source |
| `PointsExpiryScheduler` scheduled job | Hard | Batch never runs automatically without scheduler |
| `LoyaltyTransactionService.debitPoints` | Hard | Points expiry mechanism |

---

## Deploy Order

Based on hard dependencies, deploy in this sequence:

```
1. Infrastructure
   - Named Credential: Loyalty_Cloud_API (OAuth 2.0)
   - Platform Cache partition: local.LoyaltyMemberData
   - Static Resource: JsBarcode

2. Custom Metadata
   - Loyalty_Program_Config__mdt (Default record)
   - Tier_Mapping__mdt (8 records)
   - Loyalty_Exclusion_Rule__mdt (4 records)

3. Custom Objects
   - Order_Points_Status__c
   - Privacy_Request__c
   - Privacy_Audit_Log__c
   - Batch_Run_Log__c

4. Core Services (no story dependencies)
   - LoyaltyAPIClient
   - LoyaltyMemberService
   - LoyaltyVoucherService
   - LoyaltyTransactionService
   - LoyaltyPromotionService
   - ContactMatchService
   - TierMappingService

5. Enrollment Layer (stories 1.1, 1.2, 1.3)
   - LoyaltyEnrollmentService
   - LoyaltyEnrollmentController
   - loyaltyEnrollmentForm LWC
   - loyaltyJoinCta LWC
   - Welcome_Email_Trigger_Flow

6. Session Cache Layer (story 1.7)
   - LoyaltySessionCacheService
   - LoyaltyLoginController
   - loyaltyDataService LWC module
   - RCC_LPM_Attribute_Update_Flow

7. RCC Batch (story 1.4/1.5/1.6)
   - RCCRecordParser
   - RCCCardBatchProcessor
   - RCCBatchScheduler

8. Dashboard + Barcode (stories 1.9, 1.26)
   - LoyaltyTransactionController
   - loyaltyMemberDashboard, loyaltyPointsBalance, loyaltyVoucherList,
     loyaltyTransactionHistory, loyaltyPointsAdjustment LWCs
   - loyaltyBarcodeDisplay LWC (requires JsBarcode static resource)

9. Cart + Checkout (stories 1.17, 1.19, 1.20/1.21)
   - LoyaltyCartEvaluationService
   - CheckoutService
   - PointsPendingStatusService

10. Order Fulfilment (story 1.25)
    - OrderFulfilmentEventHandler
    - OrderCancellationEventHandler
    - **Create Apex triggers** for Order_Fulfilment_Event__e and Order_Cancellation_Event__e

11. Tier & Promotion (stories T1, T2)
    - LoyaltyTierController
    - loyaltyTierManagement LWC
    - LoyaltyPromotionController
    - loyaltyPromoEnrollment LWC

12. Points Expiry (story T3)
    - PointsExpiryService
    - PointsExpiryBatch
    - PointsExpiryScheduler (schedule manually)

13. Composite / POS APIs (story 1.27)
    - DeduplicationService
    - LoyaltyCompositeAPIController
    - LoyaltyLookupController
    - Connected App for POS OAuth

14. Privacy Deletion (story 3.1)
    - PrivacyAuditLogger
    - PrivacyDeletionService
    - PrivacyDeletionController
    - PrivacyDeletionAPIController
    - Privacy_Request_Handler_Flow
    - Connected App for OneTrust OAuth
```
