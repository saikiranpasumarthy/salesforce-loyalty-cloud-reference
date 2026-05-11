# Component Map

## LWC → Apex Controller → Service → LC API Endpoint → Custom Objects → Events

### loyaltyEnrollmentForm

| Layer | Details |
|---|---|
| **LWC** | `c/loyaltyEnrollmentForm` |
| **Apex Controllers** | `LoyaltyEnrollmentController.enrollMember`, `LoyaltyEnrollmentController.checkEmailExists` |
| **Services** | `LoyaltyEnrollmentService` → `LoyaltyAPIClient` |
| **LC API Endpoints** | `POST /connect/loyalty/programs/{name}/members` |
| **Custom Objects Written** | `Contact` (Has_Loyalty__c, Loyalty_Member_Id__c, Loyalty_Member_Type__c) |
| **Platform Events Published** | `Loyalty_Enrollment_Event__e` |
| **CMDT Read** | `Loyalty_Program_Config__mdt` (Default) |

---

### loyaltyJoinCta

| Layer | Details |
|---|---|
| **LWC** | `c/loyaltyJoinCta` |
| **Apex Controllers** | `LoyaltyEnrollmentController.enrollMember` |
| **Services** | `LoyaltyEnrollmentService` → `LoyaltyAPIClient` |
| **LC API Endpoints** | `POST /connect/loyalty/programs/{name}/members` |
| **Custom Objects Written** | `Contact` (Has_Loyalty__c, Loyalty_Member_Id__c) |
| **Platform Events Published** | `Loyalty_Enrollment_Event__e` |
| **Wire Adapter** | Wire to `Contact.Has_Loyalty__c` (self-hides when true) |

---

### loyaltyMemberDashboard

| Layer | Details |
|---|---|
| **LWC** | `c/loyaltyMemberDashboard` — embeds `loyaltyPointsAdjustment` |
| **Apex Controllers** | `LoyaltyTransactionController.getSessionLoyaltyData`, `LoyaltyTransactionController.refreshLoyaltyData` |
| **Services** | `LoyaltySessionCacheService` → `LoyaltyMemberService`, `LoyaltyVoucherService` |
| **LC API Endpoints** | `GET /member-benefits`, `GET /member-vouchers` |
| **Custom Objects Read** | `Contact` (Loyalty_Member_Id__c) |
| **Cache** | Org Cache `local.LoyaltyMemberData`, TTL 1800s |

---

### loyaltyPointsAdjustment (sub-component, isExposed: false)

| Layer | Details |
|---|---|
| **LWC** | `c/loyaltyPointsAdjustment` — rendered inside loyaltyMemberDashboard |
| **@api** | `lpmId` (required) |
| **Apex Controllers** | `LoyaltyTransactionController.adjustPoints` |
| **Services** | `LoyaltyTransactionService.creditPoints` or `debitPoints` |
| **LC API Endpoints** | `POST /program-processes/Credit%20Points` or `POST /program-processes/Debit%20Points` |
| **Custom Objects Written** | None directly; LC creates TJ internally |

---

### loyaltyPointsBalance

| Layer | Details |
|---|---|
| **LWC** | `c/loyaltyPointsBalance` |
| **Apex Controllers** | `LoyaltyTransactionController.getSessionLoyaltyData` |
| **Services** | `LoyaltySessionCacheService` → `LoyaltyMemberService.getRewardsPoints` |
| **LC API Endpoints** | `GET /member-benefits` |
| **Cache** | 5-min client-side; also reads Session Cache |

---

### loyaltyVoucherList

| Layer | Details |
|---|---|
| **LWC** | `c/loyaltyVoucherList` |
| **Apex Controllers** | `LoyaltyTransactionController.getSessionLoyaltyData` |
| **Services** | `LoyaltySessionCacheService` → `LoyaltyVoucherService.getMemberVouchers` |
| **LC API Endpoints** | `GET /member-vouchers` |
| **Client-side filter** | Active / Redeemed / Expired (no server call per tab change) |

---

### loyaltyTransactionHistory

| Layer | Details |
|---|---|
| **LWC** | `c/loyaltyTransactionHistory` |
| **@api** | `lpmId`, `recordId` |
| **Apex Controllers** | `LoyaltyTransactionController.getTransactionHistory` |
| **Services** | `LoyaltyTransactionService.getTransactionHistory` |
| **LC API Endpoints** | `GET /transaction-journals` (with date/type query params) |
| **Pagination** | Client-side page cursor; 10 records per page |

---

### loyaltyPromoEnrollment

| Layer | Details |
|---|---|
| **LWC** | `c/loyaltyPromoEnrollment` |
| **@api** | `lpmId` |
| **Apex Controllers** | `LoyaltyPromotionController.getMemberPromotions`, `enrollForPromotion`, `optOutFromPromotion` |
| **Services** | `LoyaltyPromotionService` |
| **LC API Endpoints** | `GET /member-promotions`, `POST /program-processes/Enroll%20Promotions`, `POST /program-processes/Opt%20Out%20Promotion` |

---

### loyaltyTierManagement

| Layer | Details |
|---|---|
| **LWC** | `c/loyaltyTierManagement` |
| **@api** | `lpmId`, `currentTier` |
| **Apex Controllers** | `LoyaltyTierController.updateMemberTier` |
| **Services** | `LoyaltyMemberService.updateMemberTier` |
| **LC API Endpoints** | `POST /program-processes/Update%20Member%20Tier` |
| **Permission Required** | `Loyalty_Admin` permission set |

---

### loyaltyBarcodeDisplay

| Layer | Details |
|---|---|
| **LWC** | `c/loyaltyBarcodeDisplay` |
| **@api** | `recordId` (Contact Id) |
| **Apex Controllers** | None — wire adapter reads Contact directly |
| **Wire Adapter** | `getRecord` wired to `Loyalty_Member_Id__c` |
| **Static Resource** | `JsBarcode` (required) |
| **LC API Endpoints** | None |

---

### loyaltyDataService (shared service module)

| Layer | Details |
|---|---|
| **LWC** | `c/loyaltyDataService` (isExposed: false) |
| **Exports** | `getLoyaltyData(lpmId)`, `refreshLoyaltyDataForContact(lpmId)`, `clearLoyaltyCache(lpmId)` |
| **Apex Controllers** | `LoyaltyTransactionController.getSessionLoyaltyData` |
| **Cache** | In-memory Map; 30-min TTL; shared across components in same page |
| **Used by** | `loyaltyMemberDashboard`, `loyaltyPointsBalance`, `loyaltyVoucherList` |

---

## REST API Controllers

| Controller | URL | Method | Callers |
|---|---|---|---|
| `LoyaltyCompositeAPIController` | `/services/apexrest/loyalty/member/*` | GET | OMS, external portals |
| `LoyaltyLookupController` | `/services/apexrest/loyalty/lookup` | POST | POS / Xstore |
| `PrivacyDeletionAPIController` | `/services/apexrest/privacy/delete/*` | POST | OneTrust |

---

## Batch Classes

| Batch | Scheduler | Trigger | Objects Written |
|---|---|---|---|
| `RCCCardBatchProcessor` | `RCCBatchScheduler` (nightly 02:00) | Manual or scheduled | `Contact`, `RCC_Import_Record__c`, `Batch_Run_Log__c` |
| `PointsExpiryBatch` | `PointsExpiryScheduler` (Jan 1) | Manual or scheduled | `Batch_Run_Log__c`; LC debit via API |

---

## Platform Event Handlers

| Event | Handler Class | Objects Written |
|---|---|---|
| `Order_Fulfilment_Event__e` | `OrderFulfilmentEventHandler` | `Order_Points_Status__c` (Awarded) |
| `Order_Cancellation_Event__e` | `OrderCancellationEventHandler` | `Order_Points_Status__c` (Reversed) |
| `Loyalty_Enrollment_Event__e` | `Welcome_Email_Trigger_Flow` | None (sends email via SFMC) |

---

## Custom Metadata Consumers

| CMDT Type | Consumer Classes |
|---|---|
| `Loyalty_Program_Config__mdt` | `LoyaltyAPIClient`, `LoyaltyEnrollmentController`, `LoyaltyCartEvaluationService`, `PointsExpiryService`, `RCCCardBatchProcessor` |
| `Tier_Mapping__mdt` | `TierMappingService` |
| `Loyalty_Exclusion_Rule__mdt` | `LoyaltyCartEvaluationService` |
