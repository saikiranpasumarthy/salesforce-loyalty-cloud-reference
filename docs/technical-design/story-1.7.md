# STORY-1.7 — Website Login: Loyalty Data Session Cache

**RICEF ID:** 1.7 | **Type:** API | **Complexity:** Medium | **Module:** SFSC, LC

## Business Purpose
On authenticated user login, pre-load loyalty data (points balance, tier, vouchers) from Loyalty Cloud into a Platform Cache–backed session, so all downstream pages (Rewards, Cart, PDP, POS) can read it without repeated LC API calls.

## Assumptions
- Contact Id is available at login time from the authenticated session context
- Platform Cache partition `local.LoyaltyMemberData` exists and is allocated ≥25 MB Org Cache
- Cache TTL is 30 minutes; subsequent calls within TTL return cached data
- Non-loyalty Contacts (no LPM) return an empty `MemberSessionData` without calling LC
- If Platform Cache partition does not exist, falls back to direct LC API calls on every request
- `loyaltyDataService` LWC module is the client-side in-memory cache (30-min TTL) sitting in front of the Apex layer
- Two LC API calls made per cache miss: `GET /member-benefits` + `GET /member-vouchers`

## User Flow
1. User authenticates → page loads → `loyaltyDataService` module's `connectedCallback` fires
2. `getLoyaltyData(lpmId)` checks in-memory JS Map — miss on first load
3. `LoyaltyLoginController.getSessionLoyaltyData(contactId)` called
4. `LoyaltySessionCacheService.getMemberData(contactId)` checks Org Cache — miss on first login
5. LC API called: `GET /member-benefits` → tier, balance, expiry, points-to-next-tier
6. LC API called: `GET /member-vouchers` → active voucher list
7. `MemberSessionData` assembled → stored in Org Cache with 30-min TTL
8. Returned to LWC → `loyaltyDataService` caches in JS Map
9. Downstream components (`loyaltyPointsBalance`, `loyaltyVoucherList`, `loyaltyMemberDashboard`) call `getLoyaltyData(lpmId)` → hit in-memory cache → no further Apex/LC calls
10. On agent cache refresh (after point adjustment etc.) → `refreshLoyaltyData(contactId)` clears both caches and re-fetches

## Components

**LWC:**
- `loyaltyDataService` (isExposed=false) — Shared service module; in-memory Map cache with 30-min TTL; exports `getLoyaltyData`, `refreshLoyaltyDataForContact`, `clearLoyaltyCache`; wraps `LoyaltyLoginController.getSessionLoyaltyData` call

**Apex:**
| Class | Method | Description |
|---|---|---|
| `LoyaltyLoginController` | `getSessionLoyaltyData(contactId)` | `@AuraEnabled(cacheable=false)`; delegates to `LoyaltySessionCacheService.getMemberData` |
| `LoyaltyLoginController` | `hasLoyaltyMembership(contactId)` | `@AuraEnabled(cacheable=true)`; lightweight Contact field check for CTA visibility |
| `LoyaltyLoginController` | `refreshLoyaltyData(contactId)` | `@AuraEnabled`; calls `svc.refreshMemberData` to force cache invalidation |
| `LoyaltyLoginController` | `syncMemberAttributes(requests)` | `@InvocableMethod`; called from `RCC_LPM_Attribute_Update_Flow`; calls `svc.refreshMemberData` |
| `LoyaltySessionCacheService` | `getMemberData(contactId)` | Cache check → LC fetch → cache store; returns `MemberSessionData` |
| `LoyaltySessionCacheService` | `refreshMemberData(contactId)` | Forces LC re-fetch; updates Org Cache |
| `LoyaltySessionCacheService` | `clearMemberData(contactId)` | Removes key from Org Cache |
| `LoyaltyMemberService` | `getRewardsPoints(lpmId)` | `GET /member-benefits` → `MemberBenefitsResponse{tier, balance, pointsToNextTier, expiryDate}` |
| `LoyaltyVoucherService` | `getMemberVouchers(lpmId)` | `GET /member-vouchers` → `List<VoucherDTO>` |

**Flows:**
- `RCC_LPM_Attribute_Update_Flow` — Trigger: Contact after-save (`Has_Loyalty__c` or `Loyalty_Member_Type__c` IsChanged); Action: `LoyaltyLoginController.syncMemberAttributes` → cache refresh

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Contact` | `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `Loyalty_Member_Type__c`, `Country_Code__c`, `RCC_Active__c` | None |
| `Platform Cache` (logical) | `local.LoyaltyMemberData.LMD_{contactId}` | Same key, TTL 1800s |

**Custom Metadata:** None (CMDT used by downstream `LoyaltyMemberService` / `LoyaltyVoucherService` via `LoyaltyAPIClient`)

**Permission Sets:**
- `Loyalty_Agent` or `Loyalty_Admin` — required for `LoyaltyLoginController` class access

## API Integration
| Call | Endpoint | Method | Response Key Fields |
|---|---|---|---|
| Member benefits | `/connect/loyalty/programs/{name}/member-benefits?memberId={lpmId}` | GET | `tierName`, `pointsBalance`, `pointsToNextTier`, `expiryDate` |
| Member vouchers | `/connect/loyalty/programs/{name}/member-vouchers?memberId={lpmId}` | GET | `List<{voucherCode, status, discountAmount, expiryDate}>` |

## Execution Sequence
```
1. Page load → loyaltyDataService.getLoyaltyData(lpmId)
2.   → JS Map check: miss
3. @AuraEnabled: LoyaltyLoginController.getSessionLoyaltyData(contactId)
4. LoyaltySessionCacheService.getMemberData(contactId)
5.   → isCacheAvailable() → Cache.Org.getPartition('local.LoyaltyMemberData')
6.   → partition.get('LMD_' + contactId) → null (cache miss)
7. LoyaltySessionCacheService.refreshMemberData(contactId)
8.   → SOQL: Contact WHERE Id=:contactId (read Has_Loyalty__c, Loyalty_Member_Id__c, etc.)
9.   → if !Has_Loyalty__c → return empty MemberSessionData
10.  → LoyaltyMemberService.getRewardsPoints(lpmId)
11.    → LoyaltyAPIClient.get('/member-benefits?memberId=' + lpmId)
12.    → Named Credential HTTP GET → JSON response
13.    → MemberBenefitsResponse{tier, balance, pointsToNextTier, expiryDate}
14.  → LoyaltyVoucherService.getMemberVouchers(lpmId)
15.    → LoyaltyAPIClient.get('/member-vouchers?memberId=' + lpmId)
16.    → List<VoucherDTO>
17.  → MemberSessionData assembled with all fields
18.  → partition.put('LMD_' + contactId, data, 1800) → stored in Org Cache
19. Return MemberSessionData to controller → to LWC
20. loyaltyDataService: store in JS Map with timestamp
21. Downstream LWC (pointsBalance, voucherList, dashboard) call getLoyaltyData(lpmId)
22.   → JS Map hit (same page context) → return immediately without Apex call
```

**Cache refresh path (after point adjustment):**
```
1. Agent triggers refresh in loyaltyMemberDashboard
2. @AuraEnabled: LoyaltyLoginController.refreshLoyaltyData(contactId)
3. LoyaltySessionCacheService.refreshMemberData(contactId) — bypasses cache check
4.   → Steps 10-18 above
5. loyaltyDataService.clearLoyaltyCache(lpmId) → JS Map entry removed
6. Components re-read → JS Map miss → Apex called → new cache data
```

## Manual Setup Required
- Platform Cache Partition created: Setup → Platform Cache → New
  - Label/API Name: `LoyaltyMemberData`
  - Org Cache: ≥25 MB
- Named Credential `Loyalty_Cloud_API` OAuth configured
- `Loyalty_Agent` permission set assigned

## Error Handling
| Error | Handling |
|---|---|
| Platform Cache partition missing | `isCacheAvailable()` returns false; falls back to direct LC API every call |
| LC `GET /member-benefits` fails | `LoyaltyAPIException` caught with `WARN` debug; `MemberSessionData.tier/balance` remains null |
| LC `GET /member-vouchers` fails | Caught separately; `data.availableVouchers` stays null; balance still returned |
| Contact not found in SOQL | Returns empty `MemberSessionData{hasLoyalty=false}` |
| `getSessionLoyaltyData` top-level catch | Returns `new MemberSessionData()` (empty); no exception thrown to LWC |

## Security
- `LoyaltyLoginController` — `with sharing`; agent can only fetch data for Contacts visible to them
- `LoyaltySessionCacheService` — `with sharing`; Org Cache partition shared across users but keyed by contactId
- `LoyaltyMemberService`, `LoyaltyVoucherService` — `with sharing`
- Cache key includes full 18-char Contact Id — no accidental cross-contact read possible

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Cache miss — enrolled member | Fresh login, enrolled Contact | 2 LC API calls; cache populated; `MemberSessionData` returned with balance + vouchers |
| Cache hit — within TTL | Second call within 30 min | No LC API calls; cached data returned |
| Cache miss — not enrolled | Contact with `Has_Loyalty__c=false` | Empty `MemberSessionData{hasLoyalty=false}`; no LC calls |
| Platform Cache unavailable | Partition not configured | Direct LC calls every time; data still returned |
| LC benefits call fails | Mock 500 from benefits | `MemberSessionData` returned with null tier/balance; vouchers still attempted |
| Force refresh | `refreshLoyaltyData(contactId)` | Cache cleared; 2 LC calls; updated data returned |
| `syncMemberAttributes` from Flow | Contact `Has_Loyalty__c` changed | Cache refreshed; next page load shows updated data |

## Validation Queries
```sql
-- Verify enrolled contacts that would trigger cache load
SELECT Id, Has_Loyalty__c, Loyalty_Member_Id__c, Loyalty_Member_Type__c
FROM Contact WHERE Has_Loyalty__c = true LIMIT 20

-- Contacts with RCC change that triggered sync (flow fires on update)
SELECT Id, Has_Loyalty__c, Loyalty_Member_Type__c, LastModifiedDate
FROM Contact WHERE Loyalty_Member_Type__c != null AND LastModifiedDate = TODAY

-- Confirm no cache partition error (check via Apex)
-- Cache.Org.getPartition('local.LoyaltyMemberData') != null
```

## Dependencies
- Named Credential `Loyalty_Cloud_API` configured (INFRA)
- Platform Cache partition `local.LoyaltyMemberData` created
- `LoyaltyMemberService`, `LoyaltyVoucherService`, `LoyaltyAPIClient` deployed
- All downstream stories (1.8/1.9/1.17/1.19/1.20/1.25/1.26/1.27) consume this story's output

## Known Gaps
- **`cacheable=false`** on `getSessionLoyaltyData` — correct but means Lightning Data Service cannot cache this call; every component mount that calls this makes a new Apex call (mitigated by LWC-side `loyaltyDataService` in-memory Map)
- **`MemberSessionData.isStale(30)`** method — called in `getMemberData` but the implementation of `isStale()` is not shown in source; if not implemented, cache always returns data (never re-fetches within TTL)
- **No cache invalidation on enrollment** — when a user enrolls mid-session (story 1.1/1.2), the cache has `hasLoyalty=false`; only a `refreshView` from LWC or explicit refresh clears it; `Welcome_Email_Trigger_Flow` does not call `syncMemberAttributes`
- **RICEF also references "Certificate Lookup API"** at login time — this is the same as `getMemberVouchers`; vouchers are already fetched on login but the RICEF framing suggests a separate "Certificate Lookup" endpoint which is not a distinct call
