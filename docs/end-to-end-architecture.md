# End-to-End Architecture

How all stories connect: the data flows, shared components, integration layers, and critical path from member enrollment through to points expiry.

---

## System Context

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Salesforce Service Cloud (SFSC)                  │
│                                                                     │
│  ┌──────────────┐  ┌─────────────────────────────────────────────┐ │
│  │   LWC Layer  │  │                Apex Layer                   │ │
│  │              │  │                                             │ │
│  │ enrollment   │  │  Controllers   Services       Batch/Sched  │ │
│  │ dashboard    │  │  ─────────── ──────────────   ──────────── │ │
│  │ barcode      │  │  Enrollment  LoyaltyMember    RCCBatch     │ │
│  │ vouchers     │  │  Login       LoyaltyVoucher   PointsExpiry │ │
│  │ tier mgmt    │  │  Txn         LoyaltyTxn       RCCScheduler │ │
│  │ promotions   │  │  Tier        LoyaltyPromo     ExpirySchedul│ │
│  │              │  │  Promo       CartEvaluation               │ │
│  └──────┬───────┘  │  Composite   CheckoutSvc                  │ │
│         │          │  Lookup      PrivacyDelete                │ │
│         │          │  Privacy     SessionCache                 │ │
│         │          └──────────────────┬──────────────────────── │ │
│         └─────────────────────────────┤                         │ │
│                                       │                         │ │
│  ┌────────────────────────────────────┴────────────────────────┐ │ │
│  │   LoyaltyAPIClient (Named Credential: Loyalty_Cloud_API)    │ │ │
│  └────────────────────────────────────┬────────────────────────┘ │ │
│                                       │                           │ │
└───────────────────────────────────────┼───────────────────────────┘ │
                                        │ OAuth 2.0 (Named Credential)
                                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Salesforce Loyalty Cloud (LC)                  │
│                                                                     │
│  LPM (Loyalty Program Member)  |  Transaction Journals              │
│  Vouchers / Certs              |  Promotions                        │
│  Earn Rules (base + RCC bonus) |  Member Benefits (tier/balance)    │
└─────────────────────────────────────────────────────────────────────┘

External Systems:
  OMS / MuleSoft  → publishes Order_Fulfilment_Event__e, Order_Cancellation_Event__e
  POS / Xstore    → calls /loyalty/member/ and /loyalty/lookup REST APIs
  OneTrust        → calls /privacy/delete/ REST API
  Epsilon         → attribution IDs stored on Contact (Epsilon_Profile_Id__c)
```

---

## Primary Data Flow: Enrollment → Session → Checkout → Fulfilment

```
MEMBER ARRIVES AT SFSC / STOREFRONT
           │
           ▼
┌──────────────────────┐
│  ENROLLMENT          │  Stories 1.1, 1.2, 1.3
│  New / Existing /    │
│  Event Registration  │
│                      │
│  ContactMatchService │──→ Match or Create Contact
│  LoyaltyEnrollment   │──→ POST /individual-member-enrollments → LC creates LPM
│  Service             │──→ Update Contact: Has_Loyalty__c=true, Loyalty_Member_Id__c
│                      │──→ Publish Loyalty_Enrollment_Event__e
│                      │
│  RCC Batch           │──→ Sets RCC_Active__c after card import (1.4/1.5/1.6)
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  SESSION CACHE       │  Story 1.7
│  (Platform Cache +   │
│   JS in-memory Map)  │
│                      │
│  On login:           │
│  GET /member-benefits│──→ tier, pointsBalance, pointsToNextTier
│  GET /member-vouchers│──→ List<VoucherDTO>
│                      │
│  Cached as           │
│  MemberSessionData   │
│  TTL = 30 minutes    │
└──────────┬───────────┘
           │  (all downstream components read from here)
           ├──────────────────────────────────────────────────────┐
           │                                                      │
           ▼                                                      ▼
┌──────────────────────┐                          ┌──────────────────────┐
│  REWARDS DASHBOARD   │  Stories 1.9, T1, T2     │  CART / CHECKOUT     │  Stories 1.17, 1.19, 1.20
│                      │                          │                      │
│  loyaltyMemberDash   │ ← reads session cache    │  CartEvaluation      │──→ POST /bulk?simulate=true
│  loyaltyPointsBal    │                          │  (estimate preview)  │     returns estimatedPoints
│  loyaltyVoucherList  │                          │                      │
│  loyaltyTxnHistory   │──→ GET /txn-journals     │  CheckoutService     │──→ POST /Validate%20Voucher
│  loyaltyTierMgmt     │──→ PATCH /lpm/{id}       │  (cert redemption)   │──→ POST /Redeem%20Voucher
│  loyaltyPromoEnroll  │──→ GET/POST /promotions  │                      │
│  loyaltyBarcode      │ ← reads Contact field    │  validateAndRedeem   │──→ POST /Enroll%20Promotions
│                      │                          │  PromoCode           │     (promo code path)
│  Points Adjustment   │──→ POST /Credit%20Points │                      │
│  (admin only)        │──→ POST /Debit%20Points  │  markPointsPending   │──→ Order_Points_Status__c
└──────────────────────┘                          │                      │    Status = Pending
                                                  └──────────┬───────────┘
                                                             │
                                                             ▼
                                                  ┌──────────────────────┐
                                                  │  ORDER FULFILMENT    │  Story 1.25
                                                  │                      │
                                                  │  OMS publishes       │
                                                  │  Order_Fulfilment    │
                                                  │  _Event__e           │
                                                  │         │            │
                                                  │         ▼            │
                                                  │  OrderFulfilment     │
                                                  │  EventHandler        │──→ POST /bulk (execute)
                                                  │                      │    tenderType=RCC (1.19)
                                                  │  Status: Awarded     │
                                                  │                      │
                                                  │  OR (cancellation):  │
                                                  │  Order_Cancellation  │
                                                  │  _Event__e           │
                                                  │         │            │
                                                  │         ▼            │
                                                  │  OrderCancellation   │──→ POST /Cancel%20Voucher
                                                  │  EventHandler        │──→ POST /Debit%20Points
                                                  │                      │
                                                  │  Status: Reversed    │
                                                  └──────────────────────┘
```

---

## Secondary Flows

### Annual Points Expiry (T3)
```
January 1 → PointsExpiryScheduler
  → PointsExpiryBatch
      → US Contacts with active LPMs
      → For each: evaluateExpiryEligibility
          → Skip CA members
          → Check Order_Points_Status__c: any Awarded in last 365 days?
          → Check LC balance > 0
      → If eligible: debitPoints(fullBalance, 'ANNUAL_EXPIRY:{year}')
      → finish(): insert Batch_Run_Log__c
```

### Privacy Deletion (3.1)
```
OneTrust webhook OR Agent sets Privacy_Request__c.Status=In_Progress
  → PrivacyDeletionService
      Phase 1 (callouts):
        → getMemberVouchers → cancel each active voucher
        → unenrollMember (LC)
      Phase 2 (DML):
        → deactivateContact: clear 12 PII fields
        → upsert Privacy_Request__c
        → insert Privacy_Audit_Log__c entries
```

### POS / Xstore Lookup (1.27)
```
Customer scans at POS
  → POST /loyalty/lookup {loyaltyId, cardNumber, email, phone}
  → LoyaltyLookupController
      → findContact (OR SOQL with sentinels)
      → LoyaltySessionCacheService.getMemberData → MemberCompositeResponse
  → POS shows tier + balance + vouchers
```

---

## Shared Components (Highest Coupling)

These classes are imported by the most stories. Changing them has the widest impact:

| Component | Used By Stories | Risk if Changed |
|---|---|---|
| `LoyaltyAPIClient` | All API stories (1.1–3.1) | **Critical** — single HTTP gateway; any auth/URL change breaks everything |
| `LoyaltySessionCacheService` | 1.7, 1.9, 1.27 | **High** — cache key format change breaks all downstream |
| `LoyaltyVoucherService` | 1.7, 1.20, 1.25, 3.1 | **High** — shared across checkout, cancellation, privacy |
| `LoyaltyTransactionService` | 1.9, 1.17, 1.19, 1.25, T3 | **High** — both simulate and execute; points adjust, debit, credit |
| `LoyaltyMemberService` | 1.7, 1.27, T1, T3, 3.1 | **High** — member benefits, tier update, unenroll |
| `PointsPendingStatusService` | 1.25 (core), checkout layer | **Medium** — state machine state writes; all status updates flow through here |
| `loyaltyDataService` (LWC) | 1.7, 1.9, 1.17, 1.20 | **Medium** — JS in-memory cache; all LWC components share one module instance |
| `Loyalty_Program_Config__mdt` | 1.1, 1.17, 1.25, T3 | **Medium** — currency ISO code change breaks all TJ payloads |
| `Loyalty_Exclusion_Rule__mdt` | 1.17, 1.20/1.21 | **Low** — used for both cart exclusions and promo code stubs |

---

## Integration Boundaries

### Inbound to SFSC
| System | Protocol | Endpoint | Stories |
|---|---|---|---|
| OMS / MuleSoft | Salesforce Platform Event | `Order_Fulfilment_Event__e` | 1.25 |
| OMS / MuleSoft | Salesforce Platform Event | `Order_Cancellation_Event__e` | 1.25 |
| POS / Xstore | REST (OAuth 2.0) | `POST /loyalty/lookup` | 1.27 |
| POS / MuleSoft | REST (OAuth 2.0) | `GET /loyalty/member/` | 1.27 |
| OneTrust | REST (OAuth 2.0) | `POST /privacy/delete/` | 3.1 |

### Outbound from SFSC to LC
| Protocol | All endpoints share | Named Credential |
|---|---|---|
| HTTPS REST | Base URL configured in Named Credential | `Loyalty_Cloud_API` |

### Outbound from SFSC to other systems
| System | Mechanism | Story |
|---|---|---|
| Epsilon | `Epsilon_Profile_Id__c` stored on Contact; no active push | 1.3 |
| SFMC | Platform events / triggered emails (via `Welcome_Email_Trigger_Flow`) | 1.1, 1.2, 1.3 |

---

## Critical Missing Pieces

The following are required for the system to function but are **not in the source repository**:

| Item | Impacts | Action Required |
|---|---|---|
| Apex trigger for `Order_Fulfilment_Event__e` | Story 1.25 — points award never fires | Create `OrderFulfilmentTrigger.trigger` that calls `OrderFulfilmentEventHandler.handleFulfilmentEvent(Trigger.new)` |
| Apex trigger for `Order_Cancellation_Event__e` | Story 1.25 — cancellation reversal never fires | Create `OrderCancellationTrigger.trigger` that calls `OrderCancellationEventHandler.handleCancellationEvent(Trigger.new)` |
| `JsBarcode` static resource | Story 1.26 — barcode never renders | Upload `JsBarcode.all.min.js` from https://github.com/lindell/JsBarcode/releases as resource named `JsBarcode` |
| LC Earn Rule for RCC bonus | Story 1.19 — RCC bonus never applies | Configure "RCC Bonus" earn rule in Loyalty Cloud program console; trigger on `tenderType = 'RCC'` |
| `PointsExpiryScheduler` scheduled job | Story T3 — batch never runs | Execute: `System.schedule('Annual Points Expiry', '0 0 2 1 1 ? *', new PointsExpiryScheduler())` |
| `RCCBatchScheduler` scheduled job | Story 1.4 — RCC batch never runs | Execute: `System.schedule('RCC Card Batch', '0 0 4 ? * 2 *', new RCCBatchScheduler())` (weekly Mondays) |

---

## Key Design Patterns

### 1. DML-Before-Callout Separation
**Used in:** `PrivacyDeletionService`, `ContactMatchService`

All LC API calls (callouts) must complete before any DML. The service divides processing into an explicit Phase 1 (callouts only) and Phase 2 (DML only). This is an Apex platform requirement — mixing DML and callouts in the same transaction throws a `System.CalloutException`.

### 2. Sentinel Pattern for SOQL OR Queries
**Used in:** `ContactMatchService`, `LoyaltyLookupController`, `DeduplicationService`

When building OR-based SOQL that accepts optional parameters, null values are replaced with a sentinel string (`'__NULL__'`) that cannot match any real record value. This avoids the need for dynamic SOQL and prevents null parameters from accidentally matching all records.

### 3. Validate-All-Then-Act-All
**Used in:** `CheckoutService.redeemCertificatesAtSubmission`

Before any redemption is attempted, all vouchers are validated in a first pass. If any validation fails, the entire operation aborts before modifying state in LC. This prevents partial redemption states.

### 4. Dual Cache (Org Cache + JS Map)
**Used in:** `LoyaltySessionCacheService` + `loyaltyDataService`

Two cache layers:
- **Org Cache** (Platform Cache): server-side; 30-min TTL; persists across page loads
- **JS Map** (LWC in-memory): client-side; lives until page refresh; prevents repeat Apex calls within a single page session

### 5. Per-Record Error Isolation in Batches
**Used in:** `RCCCardBatchProcessor`, `PointsExpiryBatch`, `OrderFulfilmentEventHandler`

Each record is wrapped in its own try-catch. A single failed record never aborts the containing chunk; it is logged to a running error list and counted in the final summary. The batch continues processing all remaining records.

### 6. State Machine for Order Points
**Used in:** `Order_Points_Status__c` + `PointsPendingStatusService`

```
Checkout calls markPointsPending()
      ↓
Status = Pending (created at checkout)
      ↓
Order_Fulfilment_Event__e received
      ↓
Success → Status = Awarded (TJ Id stored)
Failure → Status = Failed  (error message stored)
      ↓
Order_Cancellation_Event__e received
      ↓
Status = Reversed
```

---

## Data Model Relationships

```
Contact (1)
  ├── Has_Loyalty__c, Loyalty_Member_Id__c (→ LC LPM)
  ├── RCC_Active__c, RCC_Card_Number__c
  ├── Epsilon_Profile_Id__c
  ├── Country_Code__c (CA/US drives expiry exemption)
  │
  ├── Order_Points_Status__c (many) [Contact__c lookup]
  │     Status__c: Pending | Awarded | Failed | Reversed
  │     Order_Id__c, TJ_Id__c, Error_Message__c
  │
  └── Privacy_Request__c (many) [Contact__c lookup]
        Status__c: In_Progress | Completed | Failed
        OneTrust_Request_Id__c, Request_Type__c
        │
        └── Privacy_Audit_Log__c (many) [MD child]
              Action__c, Detail__c, Performed_At__c

Batch_Run_Log__c (standalone)
  Batch_Type__c: RCC_Card_Import | PointsExpiryBatch
  Total_Processed__c, Total_Succeeded__c, Total_Failed__c
```
