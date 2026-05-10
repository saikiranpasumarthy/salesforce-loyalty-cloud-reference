# API Integration Architecture

## Named Credential

All Loyalty Cloud callouts use the `Loyalty_Cloud_API` Named Credential. The credential injects the OAuth Bearer token automatically — no manual `Authorization` header construction in Apex.

```
callout:Loyalty_Cloud_API/connect/loyalty/programs/{name}/members
```

The `LoyaltyAPIClient` class constructs the full URL, strips the base URL portion (extracted from Named Credential configuration), and passes the remainder as the endpoint path to the Named Credential. This pattern ensures the base URL stays in Setup and never in code.

---

## LoyaltyAPIClient — Base HTTP Layer

**File:** `force-app/main/default/classes/api/LoyaltyAPIClient.cls`

All HTTP communication flows through this single class. Service classes never call `Http.send()` directly.

### Key behaviours

| Behaviour | Implementation |
|---|---|
| Retry on 401 | Single retry after session refresh; `MAX_RETRIES = 1` |
| Error mapping | `handleError()` inspects `errorCode` JSON field — maps to typed exception subclass |
| Timeout | 30 seconds (`req.setTimeout(30000)`) |
| Content-Type | `application/json` on all requests |
| Named Credential | `callout:Loyalty_Cloud_API` prefix; path extracted via `substringAfter(baseUrl)` |

### Error code → exception mapping

| LC Error Code (contains) | Exception thrown |
|---|---|
| `INSUFFICIENT_BALANCE` | `LoyaltyTransactionException(INSUFFICIENT_BALANCE)` |
| `INVALID_JOURNAL_TYPE` | `LoyaltyTransactionException(INVALID_JOURNAL_TYPE)` |
| `VOUCHER_EXPIRED` | `LoyaltyVoucherException(VOUCHER_EXPIRED)` |
| `VOUCHER_ALREADY_REDEEMED` | `LoyaltyVoucherException(ALREADY_REDEEMED)` |
| `VOUCHER_NOT_FOUND` | `LoyaltyVoucherException(VOUCHER_NOT_FOUND)` |
| `MEMBER_MISMATCH` | `LoyaltyVoucherException(MEMBER_MISMATCH)` |
| Other | `LoyaltyAPIException(statusCode, errorCode, rawResponse)` |

---

## LC API Endpoints Used

All endpoints follow the pattern:
```
/connect/loyalty/programs/{programName}/{resource}
```
where `{programName}` comes from `Loyalty_Program_Config__mdt.Program_API_Name__c`.

### Enrollment

| Method | Path | Used by |
|---|---|---|
| POST | `/members` | `LoyaltyEnrollmentService.enroll()` |
| GET | `/members/{memberId}` | `LoyaltyLoginController.getSessionLoyaltyData()` |
| DELETE | `/members/{memberId}` | `PrivacyDeletionService.unenrollFromLC()` |
| PATCH | `/members/{memberId}/attributes` | `LoyaltyLoginController.syncMemberAttributes()` |

### Points / Transactions

| Method | Path | Used by |
|---|---|---|
| POST | `/transaction-journals` | `LoyaltyTransactionService.accruePoints()`, `adjustPoints()` |
| GET | `/transaction-journals` | `LoyaltyTransactionService.getTransactionHistory()` |

### Vouchers

| Method | Path | Used by |
|---|---|---|
| GET | `/members/{memberId}/vouchers` | `LoyaltyVoucherService.getVouchers()` |
| POST | `/vouchers/{voucherId}/redeem` | `LoyaltyVoucherService.redeemVoucher()` |
| POST | `/vouchers/{voucherId}/cancel` | `LoyaltyVoucherService.cancelVoucher()` |

### Tiers

| Method | Path | Used by |
|---|---|---|
| GET | `/tiers` | `LoyaltyTierManagementService.getAvailableTiers()` |
| PUT | `/members/{memberId}/tier` | `LoyaltyTierManagementService.updateTier()` |

### Benefits

| Method | Path | Used by |
|---|---|---|
| GET | `/members/{memberId}/benefits` | `LoyaltyMemberBenefitsService.getBenefits()` |

### Cart Evaluation

| Method | Path | Used by |
|---|---|---|
| POST | `/cart/evaluate` | `LoyaltyCartEvaluationService.evaluateCart()` |

### Promotions

| Method | Path | Used by |
|---|---|---|
| GET | `/promotions` | `LoyaltyPromotionService.getAvailablePromotions()` |
| POST | `/promotions/{promoId}/enroll` | `LoyaltyPromotionService.enrollInPromotion()` |

---

## REST Endpoints Exposed by This Package

These endpoints are consumed by external systems (POS, OneTrust, CDP).

### GET `/services/apexrest/loyalty/member/{loyaltyMemberId}`

**Class:** `LoyaltyCompositeAPIController`

Returns a composite member response: Contact fields + current benefits + active vouchers. Single-request pattern for POS terminals to avoid multiple roundtrips.

**Response:**
```json
{
  "memberId": "M-00012345",
  "tier": "Elite",
  "pointsBalance": 4250,
  "memberType": "Retail",
  "benefits": [...],
  "vouchers": [...],
  "lastRefreshed": "2025-03-15T14:30:00Z"
}
```

---

### POST `/services/apexrest/loyalty/lookup`

**Class:** `LoyaltyLookupController`

Phone-number lookup for POS terminals that don't have a loyalty ID. Accepts a phone number, returns the member's `loyaltyId` and `tier`.

**Request:**
```json
{ "phone": "+14155550123" }
```

**Response:**
```json
{ "loyaltyId": "M-00012345", "tier": "Preferred", "found": true }
```

---

### POST `/services/apexrest/privacy/delete/{contactId}`

**Class:** `PrivacyDeletionAPIController`

OneTrust webhook endpoint. Triggers the 4-gate deletion workflow.

**Request:**
```json
{
  "oneTrustRequestId": "OT-98765",
  "jurisdiction": "GDPR",
  "requestType": "Erasure"
}
```

**Response (200):**
```json
{
  "status": "completed",
  "systemsUpdated": ["Loyalty Cloud", "Salesforce Contact"],
  "timestamp": "2025-03-15T14:30:00Z"
}
```

**Response (422 — business error, e.g. open orders):**
```json
{
  "status": "blocked",
  "reason": "Open orders must be resolved before deletion",
  "timestamp": "2025-03-15T14:30:00Z"
}
```

---

## Session Cache

**Class:** `LoyaltySessionCacheService`

**Partition:** `local.LoyaltyMemberData` (Org Cache)

**TTL:** 1800 seconds (30 minutes — matches LWC `loyaltyDataService` module cache)

**Key pattern:** `LMD_{contactId}`

The cache stores serialised `MemberSessionData` DTO instances. On cache miss, `LoyaltyLoginController.getSessionLoyaltyData()` calls LC and repopulates. Cache is explicitly invalidated by `refreshLoyaltyData()` and cleared on enrollment and tier change.

**Fallback:** if the `local.LoyaltyMemberData` partition is not configured in the org, `LoyaltySessionCacheService.isCacheAvailable()` returns false and all calls fall back to direct LC API calls without caching.

---

## Exception Hierarchy

```
LoyaltyAPIException
├── LoyaltyEnrollmentException (EnrollmentErrorCode enum)
│     DUPLICATE_MEMBER, MISSING_FIELDS, INVALID_PROGRAM,
│     ENROLLMENT_LIMIT, UNKNOWN
├── LoyaltyVoucherException (VoucherErrorCode enum)
│     VOUCHER_EXPIRED, ALREADY_REDEEMED, VOUCHER_NOT_FOUND,
│     VOUCHER_CANCELLED, INSUFFICIENT_VALUE, MEMBER_MISMATCH
└── LoyaltyTransactionException (TransactionErrorCode enum)
      INSUFFICIENT_BALANCE, INVALID_JOURNAL_TYPE,
      DUPLICATE_TRANSACTION, MEMBER_NOT_FOUND,
      PROGRAM_NOT_ACTIVE, UNKNOWN
```

All controller classes (`@AuraEnabled`) catch `LoyaltyAPIException` and its subclasses and return typed wrapper DTOs — they never rethrow to LWC. This ensures LWC components always receive a `{success, errorMessage, errorCode}` shape regardless of what happens in the service layer.

---

## Deduplication Scoring

`DeduplicationService` assigns a weighted match score before enrollment:

| Match dimension | Score contribution |
|---|---|
| Email exact match | +50 |
| Loyalty ID exact match | +40 |
| Phone (normalised E.164) match | +30 |
| Epsilon Profile ID match | +20 |

**Decision thresholds:**

| Score | Action |
|---|---|
| ≥ 50 | `HIGH_CONFIDENCE` — block enrollment, flag for manual review |
| 30–49 | `REVIEW` — proceed but create a deduplication task |
| < 30 | `NO_MATCH` — proceed normally |
