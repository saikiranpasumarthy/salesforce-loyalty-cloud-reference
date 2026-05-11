# STORY-1.27 — Composite API / POS Lookup / Deduplication

**RICEF ID:** 1.27 | **Type:** API | **Complexity:** Complex | **Module:** SFSC, LC

## Business Purpose
Expose REST APIs for POS (Xstore) and MuleSoft integration: (1) a single composite endpoint that returns all member data in one call, reducing POS round-trips from 3–4 to 1; (2) a multi-identifier lookup endpoint that accepts any combination of email, phone, loyalty ID, or card number; (3) a deduplication service for identifying and preparing Contact merge plans.

## Assumptions
- `LoyaltyCompositeAPIController` is called by POS/MuleSoft with either `contactId` or `loyaltyId`
- `LoyaltyLookupController` is the Xstore scan-time endpoint — Xstore sends whatever identifiers it has (card swipe, email lookup, etc.)
- `LoyaltyLookupController` uses `LoyaltySessionCacheService` for performance; avoids duplicate LC API calls
- `DeduplicationService` is a service class, not a REST endpoint — called programmatically or from future admin tooling
- Sentinel pattern (`'__NULL__'`) ensures null params do not match real Contact records in OR-based SOQL
- Partial LC failure in composite response is allowed — benefits or vouchers may be null if their LC call fails

## User Flow

### Composite API (POS / MuleSoft):
1. POS needs member data at point of sale → sends `GET /services/apexrest/loyalty/member/?contactId=003XXX`
2. `LoyaltyCompositeAPIController.getMemberData()` resolves Contact by `contactId` or `loyaltyId`
3. 2 LC calls made in sequence: `getRewardsPoints` + `getMemberVouchers`
4. Response assembled with Contact fields + points balance + vouchers → single JSON response returned

### POS Lookup (Xstore scan):
1. Customer scans loyalty card / provides phone or email at POS
2. Xstore sends `POST /services/apexrest/loyalty/lookup` with `{loyaltyId, cardNumber, email, phone}`
3. `LoyaltyLookupController.lookup()` resolves Contact via OR-based SOQL with sentinel pattern
4. If found: `LoyaltySessionCacheService.getMemberData(contactId)` returns cached data
5. `MemberCompositeResponse` returned including tier, balance, vouchers

### Deduplication (admin tooling):
1. Integration or admin tool calls `DeduplicationService.findBestMatch(email, phone, loyaltyId)`
2. Service scores up to 10 candidate Contacts: email=50, loyaltyId=40, phone=30
3. Returns best `MatchResult` (score ≥30) or null
4. Admin calls `mergeConsiderations(winnerId, loserId)` → `MergePlan` with conflict list returned
5. Actual merge executed separately (requires admin approval + standard SFSC merge API)

## Components

**LWC:** None (API-only)

**Apex:**
| Class | Method | Description |
|---|---|---|
| `LoyaltyCompositeAPIController` | `getMemberData()` | `GET /loyalty/member/*`; resolves Contact by `contactId` or `loyaltyId`; assembles composite |
| `LoyaltyCompositeAPIController` | `resolveContact(contactId, loyaltyId)` | SOQL lookup by Contact Id or `Loyalty_Member_Id__c` |
| `LoyaltyCompositeAPIController` | `assembleComposite(c)` | Calls `getRewardsPoints` + `getMemberVouchers`; partial failure allowed |
| `LoyaltyLookupController` | `lookup()` | `POST /loyalty/lookup`; OR-based SOQL with sentinels; returns `MemberCompositeResponse` or `{"found":false}` |
| `LoyaltyLookupController` | `findContact(email, phone, loyaltyId, cardNumber)` | Sentinel-safe SOQL; normalizes phone to last 10 digits with LIKE |
| `LoyaltyLookupController` | `buildFromSession(c, sessionData)` | Maps `MemberSessionData` to `MemberCompositeResponse` |
| `DeduplicationService` | `findBestMatch(email, phone, loyaltyId)` | Weighted scoring across up to 10 candidate Contacts; threshold 30 |
| `DeduplicationService` | `mergeConsiderations(winnerContactId, loserContactId)` | Returns `MergePlan` with conflict list; does NOT execute merge |
| `DeduplicationService` | `flagDuplicate(contactId)` | Marker method; logs to debug; no DML — implementation stub |

**DTOs:**
- `MemberCompositeResponse` — `contactId`, `sfId`, `loyaltyId`, `tier`, `memberType`, `pointsBalance`, `pointsToNextTier`, `nextTierThreshold`, `vouchers`, `isCAMember`, `hasLoyalty`, `rccActive`
- `DeduplicationService.MatchResult` — `contactId`, `score`, `matchReason`, `isHighConfidence`
- `DeduplicationService.MergePlan` — `winnerContactId`, `loserContactId`, `recommendation`, `List<String> conflicts`

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Contact` | `Id`, `FirstName`, `LastName`, `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `Loyalty_Member_Type__c`, `Country_Code__c`, `RCC_Active__c`, `RCC_Card_Number__c`, `Email`, `Phone`, `Epsilon_Profile_Id__c` | None |

**Permission Sets:**
- `Loyalty_Integration_User` — required for `PrivacyDeletionAPIController` (REST callins); same connected app user for POS/MuleSoft
- `Loyalty_Admin` — for deduplication service usage

## API Integration
| Operation | Endpoint | Method | Request | Response |
|---|---|---|---|---|
| Composite member profile | `/services/apexrest/loyalty/member/` | GET | `?contactId=003XXX` or `?loyaltyId=MBR-001` | `MemberCompositeResponse` JSON |
| POS / Xstore lookup | `/services/apexrest/loyalty/lookup` | POST | `{email, phone, loyaltyId, cardNumber}` | `MemberCompositeResponse` or `{"found":false}` |
| Member benefits (internal) | `/member-benefits?memberId={lpmId}` | GET | — | `tier`, `pointsBalance`, `pointsToNextTier` |
| Member vouchers (internal) | `/member-vouchers?memberId={lpmId}` | GET | — | `List<{voucherCode, status, ...}>` |

## Execution Sequence

### Composite API:
```
1. POS → GET /services/apexrest/loyalty/member/?contactId=003XXX
2. LoyaltyCompositeAPIController.getMemberData()
3.   → resolveContact('003XXX', null)
        → SOQL: Contact WHERE Id = :contactId LIMIT 1
        → return Contact
4.   → assembleComposite(c)
        → resp.contactId = c.Id; resp.hasLoyalty = c.Has_Loyalty__c; ...
        → if Has_Loyalty__c:
            try: LoyaltyMemberService.getRewardsPoints(lpmId) → resp.tier, pointsBalance, nextTierThreshold
            try: LoyaltyVoucherService.getMemberVouchers(lpmId) → resp.vouchers
            each wrapped in try-catch (partial failure allowed)
        → return resp
5.   → JSON.serialize(resp) → HTTP 200
```

### POS Lookup:
```
1. Xstore → POST /services/apexrest/loyalty/lookup
   body: {"loyaltyId":"MBR-10001","cardNumber":"4111..."}
2. LoyaltyLookupController.lookup()
3.   → findContact(email=null, phone=null, loyaltyId='MBR-10001', cardNumber='4111...')
        → normalize phone → null (no phone provided)
        → sentinels: safeEmail='__NULL__', phoneSearch='__NULL__', safeLoyaltyId='MBR-10001', safeCardNumber='4111...'
        → SOQL: Contact WHERE Email='__NULL__' OR Phone LIKE '__NULL__' OR Loyalty_Member_Id__c='MBR-10001' OR RCC_Card_Number__c='4111...'
        → returns matched Contact
4.   → cacheSvc.getMemberData(matched.Id) → MemberSessionData (cache or LC)
5.   → buildFromSession(c, sessionData) → MemberCompositeResponse
6.   → JSON.serialize(resp) → HTTP 200
If no match: HTTP 200 {"found":false}
```

### Deduplication:
```
1. DeduplicationService.findBestMatch('jane@ex.com', '+15555551234', 'MBR-10001')
2.   → sentinel SOQL: Contact WHERE Email=:'jane@ex.com' OR Phone=:'+15555551234' OR Loyalty_Member_Id__c=:'MBR-10001' LIMIT 10
3.   → for each candidate: scoreCandidate(c, email, phone, loyaltyId)
        → email match: +50; loyaltyId match: +40; phone match: +30
4.   → pick best score; if score >= 30 return MatchResult else null

5. DeduplicationService.mergeConsiderations(winnerId, loserId)
6.   → SOQL both Contacts
7.   → check conflicts: dual loyalty, email mismatch, RCC card conflict
8.   → return MergePlan{recommendation, conflicts}
   (no DML; merge must be executed by admin separately)
```

## Manual Setup Required
- Connected App for POS/MuleSoft OAuth 2.0 client credentials flow
- `Loyalty_Integration_User` permission set assigned to the integration service account
- SFSC Site or Connected App remote access configured for POS IP allowlist
- `LoyaltySessionCacheService` Platform Cache partition deployed (story 1.7 dependency)
- Custom field `RCC_Card_Number__c` on Contact must exist for card number lookup

## Error Handling
| Error | Handling |
|---|---|
| Neither `contactId` nor `loyaltyId` provided (Composite) | HTTP 400 `{"error":"contactId or loyaltyId is required"}` |
| Contact not found (Composite) | HTTP 404 `{"error":"Member not found"}` |
| LC `getRewardsPoints` fails (Composite) | `WARN` debug; partial response returned with null tier/balance |
| LC `getMemberVouchers` fails (Composite) | `WARN` debug; partial response returned with null vouchers |
| No identifiers in lookup body | HTTP 400 `{"error":"At least one lookup identifier is required"}` |
| Contact not found (Lookup) | HTTP 200 `{"found":false}` |
| Unhandled exception in either controller | HTTP 500 `{"error":"Internal server error"}` |
| `mergeConsiderations` — Contact not found | `LoyaltyAPIException(400)` thrown |

## Security
- `LoyaltyCompositeAPIController` — `global with sharing`; field-level security via sharing rules
- `LoyaltyLookupController` — `global with sharing`; sentiment sentinel pattern prevents null-match attacks
- `DeduplicationService` — `with sharing`; no REST exposure; called programmatically
- All REST endpoints require OAuth 2.0 Connected App token
- POS IP allowlist configured on the Connected App policy (not enforced in Apex)

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Composite by contactId | `?contactId=003XXX` (enrolled) | 200 with tier, balance, vouchers |
| Composite by loyaltyId | `?loyaltyId=MBR-10001` | 200 with full composite |
| Composite — LC benefits fail | LC mock returns 500 for benefits | 200 partial; `tier=null`, `pointsBalance=null` |
| Composite — Contact not found | Invalid contactId | 404 |
| Lookup — match by loyaltyId | `{"loyaltyId":"MBR-10001"}` | 200 with member data |
| Lookup — match by card number | `{"cardNumber":"4111..."}` | 200 with member data |
| Lookup — no match | All identifiers unknown | 200 `{"found":false}` |
| Lookup — no identifiers | `{}` | 400 error |
| Dedup — email match | Same email, two contacts | Score=50; high confidence match |
| Dedup — dual loyalty conflict | Both contacts have `Has_Loyalty__c=true` | MergePlan with conflict listed |
| Dedup — no match | Different email, phone, loyaltyId | `null` returned (score < 30) |

## Validation Queries
```sql
-- Contacts with loyalty ID (Composite API would return data)
SELECT Id, Loyalty_Member_Id__c, Has_Loyalty__c FROM Contact WHERE Has_Loyalty__c = true LIMIT 20

-- Contacts with RCC card (Lookup by card number)
SELECT Id, RCC_Card_Number__c, Loyalty_Member_Id__c FROM Contact WHERE RCC_Card_Number__c != null LIMIT 10

-- Potential duplicates (same loyalty ID on multiple contacts)
SELECT Loyalty_Member_Id__c, COUNT(Id) dupeCount FROM Contact
WHERE Loyalty_Member_Id__c != null
GROUP BY Loyalty_Member_Id__c HAVING COUNT(Id) > 1

-- Contacts flagged for deduplication investigation
SELECT Id, Email, Phone, Loyalty_Member_Id__c FROM Contact
WHERE Has_Loyalty__c = true
ORDER BY Email NULLS LAST
```

## Dependencies
- Story 1.7 — `LoyaltySessionCacheService` used by `LoyaltyLookupController` for performance
- `LoyaltyMemberService.getRewardsPoints` — shared with stories 1.7, 1.9
- `LoyaltyVoucherService.getMemberVouchers` — shared with stories 1.7, 1.20
- Named Credential `Loyalty_Cloud_API` configured

## Known Gaps
- **`DeduplicationService.flagDuplicate` is a stub**: the method logs to `System.debug` but creates no Case, sets no custom flag, and sends no notification — the flag action is unimplemented
- **`mergeConsiderations` does not execute the merge**: admin must manually trigger a SFSC merge (via the standard Merge Contacts UI or `MergeRequest` API) after reviewing the plan — there is no one-click merge button wired to this service
- **`LoyaltyLookupController` returns LIMIT 1**: if multiple Contacts match the same card number or phone, only the first is returned with no disambiguation — tie-breaking is not implemented
- **No rate limiting**: the POS lookup endpoint has no rate limit in Apex — Salesforce API call limits apply at the org level but there is no per-IP or per-client throttle
- **`assembleComposite` makes 2 sequential LC calls**: for high-traffic POS environments, consider caching via `LoyaltySessionCacheService` (as `LookupController` does) to reduce LC API load
