# Mock vs Real — Component & Integration Audit

## Legend
- **Real** — Calls live LC API via Named Credential; production-ready once OAuth is configured
- **Needs Config** — Code is correct but requires manual setup before it works
- **Stub** — Method exists but body is placeholder/no-op
- **Incomplete** — Partially implemented; key paths missing
- **Assumed** — References an external system/object that may not exist

---

## LWC Components

| Component | Status | Notes |
|---|---|---|
| `loyaltyEnrollmentForm` | **Needs Config** | Apex calls are Real; LWC page not activated in App Builder |
| `loyaltyJoinCta` | **Needs Config** | Apex calls are Real; requires App Builder placement + visibility rule |
| `loyaltyMemberDashboard` | **Needs Config** | Real API calls; blocked by Named Credential OAuth config + Cache partition |
| `loyaltyPointsAdjustment` | **Real** | Correct two-step flow; all API paths wired |
| `loyaltyPointsBalance` | **Needs Config** | Real; same cache partition dependency |
| `loyaltyVoucherList` | **Needs Config** | Real; requires Cache partition; `@api lpmId` wiring gap |
| `loyaltyTransactionHistory` | **Needs Config** | Real; `@api lpmId` not auto-derived from recordId — requires wrapper or code change |
| `loyaltyPromoEnrollment` | **Needs Config** | Real; same `@api lpmId` wiring issue |
| `loyaltyTierManagement` | **Needs Config** | Real API; no admin permission check in JS; no App Builder audience restriction |
| `loyaltyBarcodeDisplay` | **Needs Config** | Real wire adapter; requires JsBarcode static resource |
| `loyaltyDataService` | **Real** | In-memory cache works correctly; delegates to Apex which delegates to LC |

---

## Apex Controllers (AuraEnabled)

| Class | Status | Notes |
|---|---|---|
| `LoyaltyEnrollmentController` | **Real** | All 3 methods fully implemented; CMDT query correct |
| `LoyaltyTransactionController` | **Real** | `getTransactionHistory`, `getSessionLoyaltyData`, `adjustPoints`, `refreshLoyaltyData` all wired |
| `LoyaltyPromotionController` | **Real** | All 3 methods route to `LoyaltyPromotionService` |
| `LoyaltyTierController` | **Real** | Single method; correct; no permission guard (see missing-items.md) |
| `PrivacyDeletionController` | **Real** | `@AuraEnabled` methods exist; REST endpoint separate class |
| `LoyaltyLoginController` | **Real** | Session management for agent login |

---

## Apex Services

| Class | Status | Notes |
|---|---|---|
| `LoyaltyAPIClient` | **Needs Config** | HTTP calls are correctly structured; blocked by Named Credential OAuth |
| `LoyaltyEnrollmentService` | **Real** | Full enrollment + match/create flow |
| `LoyaltyMemberService` | **Real** | All 5 methods (getRewardsPoints, getMemberProfile, updateMemberDetails, updateMemberTier, unenrollMember) |
| `LoyaltyTransactionService` | **Real** | executeTransaction, simulateTransaction, getTransactionHistory, creditPoints, debitPoints |
| `LoyaltyVoucherService` | **Real** | getMemberVouchers, validateVoucher, redeemVoucher, cancelVoucher, issueVoucher |
| `LoyaltyPromotionService` | **Real** | getMemberPromotions, enrollForPromotion, optOutFromPromotion |
| `LoyaltyCartEvaluationService` | **Real** | evaluateCart, exclusion rules applied from CMDT |
| `LoyaltySessionCacheService` | **Needs Config** | Code correct; requires Platform Cache partition `local.LoyaltyMemberData` |
| `ContactMatchService` | **Real** | Match by email/phone/RCC; change-detection prevents unnecessary DML |
| `TierMappingService` | **Real** | CMDT-driven; 8 tier mappings deployed |
| `PointsExpiryService` | **Real** | Eligibility check + expiry via debitPoints |
| `CheckoutService` | **Incomplete** | `redeemCertificatesAtSubmission`: validate-all-then-redeem-all correct; no partial-failure rollback |
| `DeduplicationService.findBestMatch` | **Real** | Weighted scoring, correct |
| `DeduplicationService.mergeConsiderations` | **Real** | Returns merge plan; does not execute merge (by design) |
| `DeduplicationService.flagDuplicate` | **Stub** | Body is `System.debug(...)` only — does not actually flag anything |
| `PrivacyDeletionService` | **Real** | Full two-phase callout/DML separation; all PII cleared correctly |
| `PrivacyAuditLogger` | **Real** | Inserts audit logs with correct MasterDetail parent |

---

## REST API Controllers

| Controller | Endpoint | Status | Notes |
|---|---|---|---|
| `LoyaltyCompositeAPIController` | `GET /services/apexrest/loyalty/member/*` | **Real** | Assembles benefits + vouchers; needs Loyalty_Integration_User perm set on caller |
| `LoyaltyLookupController` | `POST /services/apexrest/loyalty/lookup` | **Real** | POS lookup by email/phone/loyaltyId/cardNumber |
| `PrivacyDeletionAPIController` | `POST /services/apexrest/privacy/delete/*` | **Real** | OneTrust webhook handler; full deletion flow |

---

## Batch & Scheduled Classes

| Class | Status | Notes |
|---|---|---|
| `RCCCardBatchProcessor` | **Needs Config** | LC API calls are real; batch not scheduled yet; email goes to hardcoded address |
| `RCCBatchScheduler` | **Needs Config** | Must be scheduled via Execute Anonymous (see manual-setup.md) |
| `PointsExpiryBatch` | **Needs Config** | Real expiry logic; not scheduled yet; no completion email (unlike RCC batch) |
| `PointsExpiryScheduler` | **Needs Config** | Must be scheduled via Execute Anonymous |
| `RCCRecordParser` | **Real** | Validation logic complete |

---

## Flows

| Flow | Status | Notes |
|---|---|---|
| `Privacy_Request_Handler_Flow` | **Needs Config** | Deployed inactive; must be activated |
| `RCC_LPM_Attribute_Update_Flow` | **Needs Config** | Deployed inactive; must be activated |
| `Welcome_Email_Trigger_Flow` | **Assumed** | Deployed inactive; depends on SFMC or org email template that may not exist |

---

## Platform Events

| Event | Publisher | Subscriber | Status |
|---|---|---|---|
| `Loyalty_Enrollment_Event__e` | `LoyaltyEnrollmentService` | `Welcome_Email_Trigger_Flow` | **Needs Config** — flow must be activated |
| `Order_Fulfilment_Event__e` | OMS (external) | `OrderFulfilmentEventHandler` | **Assumed** — OMS must publish this event; trigger must exist |
| `Order_Cancellation_Event__e` | OMS (external) | `OrderCancellationEventHandler` | **Assumed** — same; OMS trigger wires not in this repo |

---

## Infrastructure

| Item | Status | Notes |
|---|---|---|
| Named Credential `Loyalty_Cloud_API` | **Needs Config** | Deployed with NoAuthentication; must switch to OAuth 2.0 |
| Platform Cache `local.LoyaltyMemberData` | **Needs Config** | Partition must be created manually |
| Permission Set `Loyalty_Admin` | **Real** | Deployed; must be assigned to users |
| Permission Set `Loyalty_Agent` | **Real** | Deployed; must be assigned to agents |
| Permission Set `Loyalty_Integration_User` | **Real** | Deployed; must be assigned to service account |
| CMDT `Loyalty_Program_Config__mdt` (Default) | **Real** | Deployed with correct values |
| CMDT `Tier_Mapping__mdt` (8 records) | **Real** | Deployed; all 8 legacy codes present |
| CMDT `Loyalty_Exclusion_Rule__mdt` (4 records) | **Real** | Deployed; Fuel, Gift Cards, Tobacco, Generic Brand |
| Static Resource `JsBarcode` | **Needs Config** | Must be present in org for barcode component |

---

## Summary Counts

| Status | Count |
|---|---|
| Real (works as-is after OAuth config) | 26 |
| Needs Config (setup action required) | 20 |
| Stub (incomplete implementation) | 1 |
| Incomplete (partial implementation) | 1 |
| Assumed (depends on external system not in repo) | 3 |
