# Story Mapping

Full component inventory across all stories. Each row lists the story, its primary artifacts, and the LC API calls it makes.

---

## Story Index

| Story ID | Title | Type | Complexity |
|---|---|---|---|
| 1.1 | New Account Enrollment | Services | Complex |
| 1.2 | Existing User Enrollment | Services | Medium |
| 1.3 | Enrollment via Event (Epsilon Attribution) | API | Medium |
| 1.4/1.5/1.6 | RCC Card Batch (Retail, Pro, Cancellation) | Batch | Complex |
| 1.7 | Session Cache / Login Loyalty Data | API | Medium |
| 1.8/1.9/1.10/1.11 | Rewards Dashboard (Welcome, Balance, Student, Pro) | UI | Medium |
| 1.17 | Points Earn Preview (Cart Simulation) | API | Medium |
| 1.19 | Award Bonus Points – RCC Tender | API | Medium |
| 1.20/1.21 | Certificate Redemption + Promo Code Validation | API | Complex/Medium |
| 1.25 | Order Points Award & Reversal | Services | Complex |
| 1.26 | App Barcode – Loyalty ID | UI | Low |
| 1.27 | Composite API / POS Lookup / Deduplication | API | Complex |
| 3.1 | Privacy Deletion (OneTrust / GDPR / CCPA) | API + Flow | Complex |
| T1 | Tier Management & Legacy Tier Mapping | UI + Services | Medium |
| T2 | Promotion Enrollment Management | UI + API | Medium |
| T3 | Annual Points Expiry Batch | Batch | Medium |

---

## LWC Components by Story

| LWC Component | Story | `@api` Props | Exposed? |
|---|---|---|---|
| `loyaltyEnrollmentForm` | 1.1 | `memberType` | Yes |
| `loyaltyJoinCta` | 1.2 | `contactId`, `memberType` | Yes |
| `loyaltyDataService` | 1.7 (shared) | — | No (service module) |
| `loyaltyMemberDashboard` | 1.9 | `recordId` (via wire) | Yes |
| `loyaltyPointsBalance` | 1.9 | `lpmId` | Yes |
| `loyaltyVoucherList` | 1.9, 1.20 | `lpmId` | Yes |
| `loyaltyTransactionHistory` | 1.9 | `lpmId` | Yes |
| `loyaltyPointsAdjustment` | 1.9 | `lpmId` (embedded in dashboard) | No |
| `loyaltyBarcodeDisplay` | 1.26 | `recordId` | Yes |
| `loyaltyTierManagement` | T1 | `lpmId`, `currentTier` | Yes |
| `loyaltyPromoEnrollment` | T2 | `lpmId` | Yes |

---

## Apex Classes by Story

| Class | Story | Category |
|---|---|---|
| `LoyaltyEnrollmentController` | 1.1, 1.2, 1.3 | Controller |
| `LoyaltyEnrollmentService` | 1.1, 1.2, 1.3 | Service |
| `ContactMatchService` | 1.1, 1.3, 1.27 | Service |
| `RCCCardBatchProcessor` | 1.4/1.5/1.6 | Batch |
| `RCCRecordParser` | 1.4/1.5/1.6 | Utility |
| `RCCBatchScheduler` | 1.4/1.5/1.6 | Scheduler |
| `TierMappingService` | 1.4, T1 | Service |
| `LoyaltyLoginController` | 1.7, 1.9 | Controller |
| `LoyaltySessionCacheService` | 1.7, 1.9, 1.27 | Cache Service |
| `LoyaltyTransactionController` | 1.9 | Controller |
| `LoyaltyTransactionService` | 1.9, 1.17, 1.19, 1.25, T3 | Service |
| `LoyaltyCartEvaluationService` | 1.17, 1.19 | Service |
| `CheckoutService` | 1.20/1.21 | Service |
| `LoyaltyVoucherService` | 1.7, 1.20, 1.25, 3.1 | Service |
| `LoyaltyPromotionService` | 1.20/1.21, T2 | Service |
| `LoyaltyPromotionController` | T2 | Controller |
| `OrderFulfilmentEventHandler` | 1.25 | Event Handler |
| `OrderCancellationEventHandler` | 1.25 | Event Handler |
| `PointsPendingStatusService` | 1.25 | Service |
| `LoyaltyCompositeAPIController` | 1.27 | REST Controller |
| `LoyaltyLookupController` | 1.27 | REST Controller |
| `DeduplicationService` | 1.27 | Service |
| `PrivacyDeletionAPIController` | 3.1 | REST Controller |
| `PrivacyDeletionController` | 3.1 | Invocable Controller |
| `PrivacyDeletionService` | 3.1 | Service |
| `PrivacyAuditLogger` | 3.1 | Utility |
| `LoyaltyTierController` | T1 | Controller |
| `LoyaltyMemberService` | 1.7, 1.27, T1, T3, 3.1 | Service |
| `PointsExpiryService` | T3 | Service |
| `PointsExpiryBatch` | T3 | Batch |
| `PointsExpiryScheduler` | T3 | Scheduler |
| `LoyaltyAPIClient` | All API stories | Infrastructure |

---

## Flows by Story

| Flow | Story | Trigger | Action |
|---|---|---|---|
| `Welcome_Email_Trigger_Flow` | 1.1, 1.2, 1.3 | `Loyalty_Enrollment_Event__e` platform event | Query Contact → send welcome email |
| `RCC_LPM_Attribute_Update_Flow` | 1.4, 1.7 | Contact after-save (`Has_Loyalty__c` or `Loyalty_Member_Type__c` changed) | Call `syncMemberAttributes` @InvocableMethod → cache refresh |
| `Privacy_Request_Handler_Flow` | 3.1 | `Privacy_Request__c` after-save (`Status__c = 'In_Progress'`) | Call `PrivacyDeletionController` @InvocableMethod → update status |

---

## Platform Events by Story

| Event | Story | Publisher | Consumer |
|---|---|---|---|
| `Loyalty_Enrollment_Event__e` | 1.1, 1.2, 1.3 | `LoyaltyEnrollmentService` (Apex) | `Welcome_Email_Trigger_Flow` |
| `Order_Fulfilment_Event__e` | 1.25 | OMS / MuleSoft | `OrderFulfilmentEventHandler` (requires Apex trigger) |
| `Order_Cancellation_Event__e` | 1.25 | OMS / MuleSoft | `OrderCancellationEventHandler` (requires Apex trigger) |

---

## Custom Objects / Fields by Story

| Object | Stories | Role |
|---|---|---|
| `Contact` | All stories | Central member record; `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `Loyalty_Member_Type__c`, `Country_Code__c`, `RCC_Active__c`, `RCC_Card_Number__c`, `Epsilon_Profile_Id__c` |
| `Order_Points_Status__c` | 1.25, T3 | State machine: Pending → Awarded / Failed → Reversed |
| `Privacy_Request__c` | 3.1 | Master record for deletion requests |
| `Privacy_Audit_Log__c` | 3.1 | MD child of `Privacy_Request__c`; immutable audit trail |
| `Batch_Run_Log__c` | 1.4, T3 | Batch execution summary |
| `Order` | 3.1 | Checked for open orders before deletion |

---

## Custom Metadata Types by Story

| CMDT | Stories | Records |
|---|---|---|
| `Loyalty_Program_Config__mdt` | 1.1, 1.17, 1.25, T3 | `Default`: `Program_API_Name__c='LevelUp'`, `Currency_ISO_Code__c='USD'`, `Max_Enrollments_Per_Day__c=5000`, `Points_Expiry_Days__c=365` |
| `Tier_Mapping__mdt` | 1.4, T1 | 8 records; maps legacy 6-tier codes to Preferred/Elite × Retail/Pro/Student |
| `Loyalty_Exclusion_Rule__mdt` | 1.17, 1.20/1.21 | 4 records: Exclude_Fuel, Exclude_Gift_Cards, Exclude_Tobacco, Exclude_Generic_Brand; also used as promo code lookup stub |

---

## REST API Endpoints by Story

| Endpoint | Method | Stories |
|---|---|---|
| `/individual-member-enrollments` | POST | 1.1, 1.2, 1.3 |
| `/member-benefits?memberId={lpmId}` | GET | 1.7, 1.9, 1.27, T3 |
| `/member-vouchers?memberId={lpmId}` | GET | 1.7, 1.20, 1.27, 3.1 |
| `/transaction-journals/bulk` | POST | 1.17, 1.19, 1.25 |
| `/program-processes/Validate%20Voucher` | POST | 1.20 |
| `/program-processes/Redeem%20Voucher` | POST | 1.20 |
| `/program-processes/Cancel%20Voucher` | POST | 1.20, 1.25, 3.1 |
| `/program-processes/Enroll%20Promotions` | POST | 1.20/1.21, T2 |
| `/program-processes/Opt%20Out%20Promotion` | POST | T2 |
| `/program-processes/Debit%20Points` | POST | 1.9, 1.25, T3 |
| `/program-processes/Credit%20Points` | POST | 1.9 |
| `/program-processes/Unenroll%20Member` | POST | 3.1 |
| `/member-promotions?memberId={lpmId}` | GET | T2 |
| `/transaction-journals` | GET | 1.9 |
| `/transaction-journals/{id}/promotions` | GET | T2 |
| `/transaction-ledger-summary?memberId={lpmId}` | GET | 1.9 |
| `PATCH /loyalty-program-members/{lpmId}` | PATCH | T1 |
| `/services/apexrest/loyalty/member/` | GET | 1.27 |
| `/services/apexrest/loyalty/lookup` | POST | 1.27 |
| `/services/apexrest/privacy/delete/` | POST | 3.1 |

---

## Static Resources

| Resource | Story | Purpose |
|---|---|---|
| `JsBarcode` | 1.26 | CODE128 barcode rendering library; must be uploaded manually |

---

## Permission Sets Summary

| Permission Set | Stories | Who Gets It |
|---|---|---|
| `Loyalty_Agent` | 1.1, 1.2, 1.7, 1.9, 1.17, 1.20 | All agents working on loyalty |
| `Loyalty_Admin` | 1.9, 1.25, 3.1, T1, T3 | Admins who adjust points, tiers, run batches |
| `Loyalty_Integration_User` | 1.27, 3.1 | POS/OneTrust service accounts |
