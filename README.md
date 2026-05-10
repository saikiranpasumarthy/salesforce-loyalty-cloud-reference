# Salesforce Loyalty Cloud Reference Implementation

Production-grade SFDX reference repository for a **Salesforce Loyalty Management (SLM) + Service Cloud** integration. Covers enrollment, points accrual, voucher management, RCC batch processing, privacy/GDPR deletion, tier management, cart evaluation, and deduplication.

---

## Table of Contents

1. [Project Structure](#1-project-structure)
2. [Prerequisites](#2-prerequisites)
3. [Quick Start — Scratch Org](#3-quick-start--scratch-org)
4. [Connected App & Named Credential](#4-connected-app--named-credential)
5. [Deployment Order (Sandbox / Production)](#5-deployment-order-sandbox--production)
6. [Running Tests](#6-running-tests)
7. [LWC Components Reference](#7-lwc-components-reference)
8. [Batch Jobs](#8-batch-jobs)
9. [Platform Events](#9-platform-events)
10. [Privacy / GDPR Workflow](#10-privacy--gdpr-workflow)
11. [Postman Collection](#11-postman-collection)
12. [Architecture Overview](#12-architecture-overview)
13. [Known Limitations & TODOs](#13-known-limitations--todos)

---

## 1. Project Structure

```
force-app/main/default/
├── classes/
│   ├── api/                    # LoyaltyAPIClient + 8 service classes
│   ├── batch/                  # RCCCardBatchProcessor, PointsExpiryBatch/Scheduler
│   ├── cache/                  # LoyaltySessionCacheService
│   ├── composite/              # Composite REST API + DeduplicationService
│   ├── controllers/            # @AuraEnabled controllers for LWC
│   ├── dto/                    # Request/Response DTO classes
│   ├── enrollment/             # ContactMatchService, LoyaltyEnrollmentService
│   ├── exceptions/             # Typed exception hierarchy
│   ├── orders/                 # OrderFulfilmentEventHandler, OrderCancellationEventHandler
│   ├── privacy/                # PrivacyDeletionService + REST controller
│   └── tiers/                  # TierMappingService, PointsExpiryService
├── customMetadata/             # CMDT records (programs, exclusion rules, tier mappings)
├── flows/                      # Welcome Email, Privacy Handler, RCC Attribute Sync
├── labels/                     # CustomLabels.labels-meta.xml
├── lwc/                        # 11 LWC components
├── namedCredentials/           # Loyalty_Cloud_API
├── objects/
│   ├── Contact/fields/         # 13 custom fields
│   ├── Batch_Run_Log__c/
│   ├── Loyalty_Exclusion_Rule__mdt/
│   ├── Loyalty_Program_Config__mdt/
│   ├── Order_Points_Status__c/
│   ├── Privacy_Audit_Log__c/
│   ├── Privacy_Request__c/
│   ├── RCC_Import_Record__c/
│   └── Tier_Mapping__mdt/
├── permissionsets/             # Loyalty_Agent, Loyalty_Admin, Loyalty_Integration_User
└── platformEvents/             # Enrollment, Fulfilment, Cancellation events

docs/
├── architecture/
│   ├── data-model.md           # All objects, fields, relationships
│   ├── api-integration.md      # LC API endpoints, Named Credential, error mapping
│   └── sequence-diagrams.md    # ASCII sequence diagrams for 6 key flows
└── postman/
    └── Loyalty_Cloud_API.postman_collection.json
```

---

## 2. Prerequisites

| Tool | Version |
|---|---|
| Salesforce CLI (`sf`) | 2.x |
| Node.js | 18+ (for linting only) |
| Java | 11+ (for Apex compilation in CI) |
| Salesforce DX DevHub | Enabled in your org |

---

## 3. Quick Start — Scratch Org

```bash
# 1. Authenticate to your Dev Hub
sf org login web --set-default-dev-hub --alias MyHub

# 2. Create a scratch org (30-day expiry)
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias loyalty-scratch \
  --duration-days 30 \
  --set-default

# 3. Deploy all metadata
sf project deploy start \
  --source-dir force-app \
  --target-org loyalty-scratch

# 4. Assign permission set to your user
sf org assign permset \
  --name Loyalty_Admin \
  --target-org loyalty-scratch

# 5. Run all tests
sf apex run test \
  --target-org loyalty-scratch \
  --code-coverage \
  --result-format human \
  --wait 10

# 6. Open the org
sf org open --target-org loyalty-scratch
```

### Scratch org definition

Create `config/project-scratch-def.json`:

```json
{
  "orgName": "Loyalty Cloud Reference",
  "edition": "Developer",
  "features": ["EnableSetPasswordInApi", "PlatformEvents"],
  "settings": {
    "apexSettings": { "enableCompileOnDeploy": true },
    "orgPreferenceSettings": { "s1DesktopEnabled": true }
  }
}
```

---

## 4. Connected App & Named Credential

The `Loyalty_Cloud_API` Named Credential provides token-injected callouts. No Bearer token construction in Apex code.

### Step-by-step setup

1. **Create a Connected App** in the target Salesforce org:
   - Setup → App Manager → New Connected App
   - Enable OAuth: `api`, `refresh_token`, `offline_access`
   - Callback URL: `https://login.salesforce.com/services/oauth2/success`
   - Note the **Consumer Key** and **Consumer Secret**

2. **Create an Auth Provider** (if using OAuth 2.0):
   - Setup → Auth. Providers → New → Salesforce
   - Consumer Key / Secret from step 1

3. **Configure the Named Credential**:
   - Setup → Named Credentials → Loyalty Cloud API
   - URL: `https://<your-org>.my.salesforce.com/services/data/v62.0`
   - Auth Protocol: OAuth 2.0
   - Auth Provider: (the one you created)
   - Start Authentication Flow on Save: ✓

4. **Test**: The `LoyaltyAPIClientTest` class uses `LoyaltyMockHttpCallout` — no real callout required. In a scratch org, all tests run without configuring the Named Credential.

---

## 5. Deployment Order (Sandbox / Production)

Deploy in this order to avoid metadata dependency failures:

```bash
# 1. Custom Objects and Fields
sf project deploy start --metadata CustomObject --target-org MySandbox

# 2. Custom Metadata Types (schema only — no records yet)
sf project deploy start \
  --metadata CustomObject:Loyalty_Program_Config__mdt \
  --metadata CustomObject:Loyalty_Exclusion_Rule__mdt \
  --metadata CustomObject:Tier_Mapping__mdt \
  --target-org MySandbox

# 3. Platform Events
sf project deploy start --metadata CustomObject:Loyalty_Enrollment_Event__e \
  --metadata CustomObject:Order_Fulfilment_Event__e \
  --metadata CustomObject:Order_Cancellation_Event__e \
  --target-org MySandbox

# 4. Labels, Named Credential
sf project deploy start \
  --metadata CustomLabels \
  --metadata NamedCredential:Loyalty_Cloud_API \
  --target-org MySandbox

# 5. All Apex classes
sf project deploy start --metadata ApexClass --target-org MySandbox

# 6. LWC
sf project deploy start --metadata LightningComponentBundle --target-org MySandbox

# 7. Flows
sf project deploy start --metadata Flow --target-org MySandbox

# 8. Custom Metadata Records
sf project deploy start --metadata CustomMetadata --target-org MySandbox

# 9. Permission Sets
sf project deploy start --metadata PermissionSet --target-org MySandbox

# 10. Assign permission sets
sf org assign permset --name Loyalty_Agent       --target-org MySandbox
sf org assign permset --name Loyalty_Admin       --target-org MySandbox
sf org assign permset --name Loyalty_Integration_User --target-org MySandbox
```

---

## 6. Running Tests

```bash
# Run all Loyalty tests with code coverage
sf apex run test \
  --class-names LoyaltyEnrollmentServiceTest,LoyaltyAPIClientTest,ContactMatchServiceTest,\
LoyaltyTransactionServiceTest,LoyaltyVoucherServiceTest,LoyaltySessionCacheServiceTest,\
PrivacyDeletionServiceTest,PointsExpiryServiceTest,DeduplicationServiceTest,\
OrderFulfilmentEventHandlerTest,RCCCardBatchProcessorTest,CheckoutServiceTest \
  --code-coverage \
  --result-format human \
  --wait 15 \
  --target-org loyalty-scratch
```

### Test architecture

All test classes use `LoyaltyMockHttpCallout` — no callouts are made to real LC endpoints.

```apex
// Pattern used in every test class
@IsTest
static void testAccruePoints() {
    Test.setMock(HttpCalloutMock.class,
        LoyaltyMockHttpCallout.forEndpoint('/transaction-journals', 200,
            LoyaltyMockHttpCallout.TRANSACTION_JOURNAL_BODY));
    Test.startTest();
    // ... invoke service
    Test.stopTest();
}
```

The `@TestVisible` pattern on private service constructors allows dependency injection without modifying production code paths:

```apex
// In service class
@TestVisible
private LoyaltyTransactionService(LoyaltyAPIClient client) {
    this.client = client;
}

// In test
LoyaltyAPIClient mockClient = new LoyaltyAPIClient(mockEndpoint);
LoyaltyTransactionService svc = new LoyaltyTransactionService(mockClient);
```

---

## 7. LWC Components Reference

| Component | Exposed | Target | Description |
|---|---|---|---|
| `loyaltyEnrollmentForm` | ✓ | Contact Record Page | Enrollment form with duplicate check on email blur |
| `loyaltyMemberDashboard` | ✓ | Contact Record Page | Points balance, tier badge, progress bar |
| `loyaltyPointsBalance` | ✓ | Contact Record Page | Compact points display with 5-min client cache |
| `loyaltyVoucherList` | ✓ | Contact Record Page | Active/expiring vouchers datatable with row actions |
| `loyaltyPointsAdjustment` | ✓ | Contact Record Page | 2-step modal for agent point adjustments |
| `loyaltyTransactionHistory` | ✓ | Contact Record Page | Paginated transaction journal |
| `loyaltyBarcodeDisplay` | ✓ | Contact Record Page | CODE128 barcode via JsBarcode static resource |
| `loyaltyPromoEnrollment` | ✓ | Contact Record Page | Available promotions with one-click enroll |
| `loyaltyTierManagement` | ✓ | Contact Record Page | Admin tier override with mandatory reason |
| `loyaltyJoinCta` | ✓ | Contact Record Page | Enroll CTA — auto-hides when `Has_Loyalty__c` is true |
| `loyaltyDataService` | ✗ | (utility module) | Module-level JS cache; `getLoyaltyData()`, `refreshLoyaltyDataForContact()` |

### Adding components to a Lightning Record Page

1. Open a Contact record → Edit Page (Lightning App Builder)
2. Drag components from the "Custom" panel to the layout
3. Set `memberType` on `loyaltyJoinCta` (Retail/Pro/Student) if a default is needed

---

## 8. Batch Jobs

### RCC Card Import

```apex
// Run immediately with a CSV file ID
Database.executeBatch(new RCCCardBatchProcessor(csvFileId), 200);

// Or schedule via Apex Anonymous
RCCCardBatchProcessor.scheduleNightlyImport();
```

**Prerequisites:** Upload the CSV as a `ContentDocument` and pass its `Id`. The batch reads the CSV, parses each row via `RCCRecordParser`, matches contacts via `ContactMatchService`, and enrolls matched contacts.

### Points Expiry

```apex
// Schedule annually (3 AM on Jan 1)
PointsExpiryScheduler.scheduleAnnualRun();

// Or run immediately
Database.executeBatch(new PointsExpiryBatch(), 25);
```

The batch skips CA members (`Country_Code__c = 'CA'`) who have a qualifying purchase (`Order_Points_Status__c.Status = 'Awarded'`) within the past 365 days.

---

## 9. Platform Events

### Publishing (external systems → Salesforce)

```apex
// Order management system publishes when an order ships
Order_Fulfilment_Event__e evt = new Order_Fulfilment_Event__e(
    Order_Id__c          = 'ORD-12345',
    Contact_Id__c        = contactId,
    Loyalty_Member_Id__c = memberId,
    Order_Amount__c      = 150.00,
    Order_Date__c        = DateTime.now(),
    Cart_Lines_JSON__c   = JSON.serialize(cartLines)
);
EventBus.publish(evt);
```

### Consuming (Apex Triggers)

```apex
// Trigger on Order_Fulfilment_Event__e
trigger OrderFulfilmentTrigger on Order_Fulfilment_Event__e (after insert) {
    new OrderFulfilmentEventHandler().handleEvents(Trigger.new);
}
```

Add corresponding triggers for `Order_Cancellation_Event__e` and `Loyalty_Enrollment_Event__e` (the enrollment event is consumed by the `Welcome_Email_Trigger_Flow` — no Apex trigger needed unless additional processing is required).

---

## 10. Privacy / GDPR Workflow

### Automated (OneTrust webhook)

OneTrust calls:
```
POST /services/apexrest/privacy/delete/{contactId}
Authorization: Bearer <integration_user_token>
Content-Type: application/json

{
  "oneTrustRequestId": "OT-98765",
  "jurisdiction": "GDPR",
  "requestType": "Erasure"
}
```

The `PrivacyDeletionAPIController` creates a `Privacy_Request__c` record, which triggers `Privacy_Request_Handler_Flow`, which calls `PrivacyDeletionService`.

### Manual (agent-initiated)

1. Open a Contact record → create a `Privacy_Request__c` record with `Request_Type__c = 'Erasure'`
2. Change `Status__c` to `In_Progress` — the flow triggers automatically
3. Monitor `Privacy_Audit_Log__c` child records for step-by-step progress

### 4-Gate process

| Gate | Action | Blocked by |
|---|---|---|
| 1 | Check for open orders | Any order in status: Pending/Processing/Shipped |
| 2 | Cancel all active vouchers | (errors swallowed — best effort) |
| 3 | Unenroll from Loyalty Cloud | LC API error |
| 4 | Anonymise Contact | SFDB DML error |

---

## 11. Postman Collection

Import `docs/postman/Loyalty_Cloud_API.postman_collection.json` into Postman.

**Setup:**

1. Set collection variables:
   - `base_url` → your org's My Domain URL
   - `program_name` → your LC program API name
2. Run **Auth → Get Bearer Token** and set `client_id`, `client_secret`, `sf_username`, `sf_password` in your Postman environment
3. The token is automatically stored in `access_token` via the test script

**Requests included:**

- Auth (Bearer token via username-password flow)
- Enrollment: enroll, get member, update attributes, unenroll
- Transactions: accrue, adjust (credit), debit (cancellation reversal), history, expiry
- Vouchers: list, redeem, cancel
- Benefits: get member benefits
- Tiers: list tiers, update member tier
- Promotions: list available, enroll in promotion
- Cart Evaluation: points preview
- Custom REST: composite lookup, phone lookup (POS), privacy deletion

---

## 12. Architecture Overview

```
                    ┌──────────────────────────────┐
                    │   Service Cloud Agent (LWC)  │
                    │  loyaltyMemberDashboard       │
                    │  loyaltyVoucherList           │
                    │  loyaltyPointsAdjustment      │
                    │  loyaltyEnrollmentForm        │
                    └─────────────┬────────────────┘
                                  │ @AuraEnabled
                    ┌─────────────▼────────────────┐
                    │   @AuraEnabled Controllers   │
                    │  LoyaltyEnrollmentController  │
                    │  LoyaltyLoginController       │
                    │  LoyaltyVoucherController     │
                    │  LoyaltyTransactionController │
                    └─────────────┬────────────────┘
                                  │
                    ┌─────────────▼────────────────┐
                    │      Service Layer            │
                    │  LoyaltyEnrollmentService     │
                    │  LoyaltyTransactionService    │
                    │  LoyaltyVoucherService        │
                    │  LoyaltyCartEvaluationService │
                    │  LoyaltySessionCacheService   │◄──── Platform Cache
                    │  TierMappingService           │     (local.LoyaltyMemberData)
                    │  PointsExpiryService          │
                    │  DeduplicationService         │
                    └─────────────┬────────────────┘
                                  │
                    ┌─────────────▼────────────────┐
                    │      LoyaltyAPIClient         │◄── Named Credential
                    │  (single HTTP gateway)        │    Loyalty_Cloud_API
                    └─────────────┬────────────────┘
                                  │ HTTPS
                    ┌─────────────▼────────────────┐
                    │   Salesforce Loyalty Cloud    │
                    │   /connect/loyalty/...        │
                    └──────────────────────────────┘

External Events:
  Order System ──► Order_Fulfilment_Event__e ──► OrderFulfilmentEventHandler
  Order System ──► Order_Cancellation_Event__e ──► OrderCancellationEventHandler
  OneTrust     ──► POST /apexrest/privacy/delete ──► PrivacyDeletionAPIController
  POS Terminal ──► GET  /apexrest/loyalty/member ──► LoyaltyCompositeAPIController
  POS Terminal ──► POST /apexrest/loyalty/lookup ──► LoyaltyLookupController
```

---

## 13. Known Limitations & TODOs

| ID | Priority | Description |
|---|---|---|
| TODO-1 | High | `LoyaltyAPIClient` base URL is read from the Named Credential configuration — update `ENV_BASE_URL` constant if your org's My Domain changes |
| TODO-2 | High | `Welcome_Email_Trigger_Flow` uses `emailSimple` action with a hardcoded plain-text body. Replace with an org-wide Email Template for production |
| TODO-3 | Medium | `RCCCardBatchProcessor` reads the CSV from `ContentDocument`. Add a UI (LWC file upload) or Integration Procedure to populate `RCC_Import_Record__c` records from a SFTP drop |
| TODO-4 | Medium | `DeduplicationService` does not yet write a Task for `REVIEW`-level matches. Add a `Task` insert in `LoyaltyEnrollmentService` when `matchResult.confidence == REVIEW` |
| TODO-5 | Medium | `LoyaltyBarcodeDisplay` requires `JsBarcode` as a Static Resource. Upload `jsbarcode.min.js` from the JsBarcode npm package before deploying to a sandbox |
| TODO-6 | Low | `PointsExpiryBatch` runs annually but does not check whether the batch has already run for the current year. Add a `Batch_Run_Log__c` idempotency check in `start()` |
| TODO-7 | Low | `Privacy_Request_Handler_Flow` calls `PrivacyDeletionController` via an Apex Action — the `logError` action in `RCC_LPM_Attribute_Update_Flow` is a placeholder; wire it to your org's preferred error logging framework |
| TODO-8 | Low | Add `@InvocableMethod` on `LoyaltyEnrollmentService.enroll()` to support Flow-based enrollment in addition to Apex-based enrollment |

---

## Contributing

1. Fork and create a feature branch from `main`
2. Run `sf apex run test` and verify 100% test pass before opening a PR
3. Keep `LoyaltyAPIClient` as the sole HTTP gateway — do not add `Http.send()` calls in service classes
4. All `@AuraEnabled` methods must return a typed wrapper DTO — no raw exceptions to LWC
5. New LWC components that call Apex must import from `c/loyaltyDataService` for cached data, not call the controller directly from `connectedCallback`
