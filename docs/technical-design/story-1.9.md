# STORY-1.9 / 1.8 / 1.10 / 1.11 — Rewards Page: Loyalty Dashboard

**RICEF IDs:** 1.8 (Welcome Pop-Up), 1.9 (Rewards Dashboard), 1.10 (Student Experience), 1.11 (Pro Experience) | **Type:** UI | **Module:** SFSC, LC

## Business Purpose
Display member's tier, points balance, points-to-next-reward progress, available vouchers with expiry, and transaction history on the Rewards/My Account page; with display variants for Student and Pro members.

## Assumptions
- Session data loaded at login (story 1.7); dashboard reads from `loyaltyDataService` cache — no direct LC call on render
- Welcome pop-up (1.8) is a subset of dashboard data; shown once per session
- Student (1.10) and Pro (1.11) display variants are controlled by `memberType` from `MemberSessionData` — `'Student'` prefix suppressed in tier label; same for `'Pro'`
- CA members: `isCAMember=true` → no points expiry date shown
- `pointsBalance` and `tier` rendered from cached `MemberSessionData`; transaction history fetched separately via LC `GET /transaction-journals`
- `loyaltyPointsAdjustment` (admin-only manual adjustment) is embedded inside `loyaltyMemberDashboard`

## User Flow
1. Authenticated member opens Rewards/Account page → `loyaltyMemberDashboard` loads
2. `loyaltyDataService.getLoyaltyData(lpmId)` → cache hit (from login) → renders immediately:
   - Points balance, tier name (Student/Pro prefix stripped per 1.10/1.11), progress bar to next tier
   - Active vouchers list with expiry dates (from `availableVouchers`)
   - CA members: no expiry date shown
3. `loyaltyTransactionHistory` loads separately → `LoyaltyTransactionController.getTransactionHistory(lpmId)` → LC API paginated
4. Agent refresh button → `refreshLoyaltyData(contactId)` clears cache; re-fetches from LC
5. Admin users see "Adjust Points" button → opens `loyaltyPointsAdjustment` modal
6. `loyaltyPointsBalance` (sidebar) — 5-min client cache; lightweight balance tile
7. `loyaltyVoucherList` — client-side filter tabs (Active/Redeemed/Expired)

## Components

**LWC:**
| Component | Purpose |
|---|---|
| `loyaltyMemberDashboard` | Main dashboard: balance, tier, progress bar, vouchers summary; embeds `loyaltyPointsAdjustment`; refresh button |
| `loyaltyPointsBalance` | Sidebar balance tile; 5-min client-side TTL cache; reads from session data |
| `loyaltyVoucherList` | Full voucher list; Active/Redeemed/Expired tabs; client-side filter |
| `loyaltyTransactionHistory` | Paginated TJ list; date range + type filter; 10 records/page |
| `loyaltyPointsAdjustment` | isExposed=false; embedded in dashboard; two-step Credit/Debit modal |

**Apex:**
| Class | Method | Description |
|---|---|---|
| `LoyaltyTransactionController` | `getSessionLoyaltyData(contactId)` | Returns cached `MemberSessionData`; called on dashboard load |
| `LoyaltyTransactionController` | `getTransactionHistory(lpmId, startDate, endDate, type, page)` | Calls LC `GET /transaction-journals`; paginated |
| `LoyaltyTransactionController` | `adjustPoints(lpmId, amount, type, reason)` | Routes to `creditPoints` or `debitPoints` |
| `LoyaltyTransactionController` | `refreshLoyaltyData(contactId)` | Delegates to `LoyaltyLoginController.refreshLoyaltyData` |
| `LoyaltyTransactionService` | `getTransactionHistory(lpmId, params)` | `GET /transaction-journals` with date/type query params |
| `LoyaltyTransactionService` | `creditPoints(lpmId, amount, currency, reason)` | `POST /program-processes/Credit%20Points` |
| `LoyaltyTransactionService` | `debitPoints(lpmId, amount, currency, reason)` | `POST /program-processes/Debit%20Points` |

**Flows:** None directly for this story (uses session cache flow from 1.7)

**Platform Events:** None

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Contact` | `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `Loyalty_Member_Type__c`, `Country_Code__c` | None |

**Custom Metadata:** None (CMDT used by underlying `LoyaltyAPIClient`)

**Permission Sets:**
- `Loyalty_Agent` — view dashboard, transaction history, vouchers
- `Loyalty_Admin` — additionally required to see and use `loyaltyPointsAdjustment`

## API Integration
| Call | Endpoint | When |
|---|---|---|
| Transaction history | `GET /transaction-journals?memberId={lpmId}&startDate=&endDate=&type=&page=` | On `loyaltyTransactionHistory` mount and filter change |
| Credit points | `POST /program-processes/Credit%20Points` | On `adjustPoints` with type=Credit |
| Debit points | `POST /program-processes/Debit%20Points` | On `adjustPoints` with type=Debit |

## Execution Sequence
```
1. loyaltyMemberDashboard.connectedCallback()
2.   → loyaltyDataService.getLoyaltyData(lpmId) → JS Map hit → render balance, tier, vouchers
3.   → If JS Map miss → LoyaltyTransactionController.getSessionLoyaltyData(contactId)
4.     → LoyaltySessionCacheService.getMemberData(contactId) → Org Cache hit or LC fetch
5. Render: tier label = memberType=Student → strip 'Student ' prefix; same for Pro (1.10/1.11)
6. Render: isCAMember=true → hide expiry date on points section (CA variant)
7. loyaltyTransactionHistory.connectedCallback()
8.   → LoyaltyTransactionController.getTransactionHistory(lpmId, null, null, null, 1)
9.     → LoyaltyTransactionService.getTransactionHistory(lpmId, {})
10.    → LoyaltyAPIClient.get('/transaction-journals?memberId=...')
11.    → Returns paginated list → 10 records rendered
12. Agent adjusts points (admin only):
13.   → loyaltyPointsAdjustment.handleConfirm()
14.   → LoyaltyTransactionController.adjustPoints(lpmId, 100, 'Credit', 'Goodwill')
15.   → LoyaltyTransactionService.creditPoints(lpmId, 100, 'USD', 'Goodwill')
16.   → Named Credential POST → LC returns 200
17.   → loyaltyDataService.clearLoyaltyCache(lpmId) → JS Map cleared
18.   → loyaltyMemberDashboard triggers refresh → loop back to step 3
```

## Manual Setup Required
- `loyaltyMemberDashboard` placed on Contact record page in App Builder; visibility: `Has_Loyalty__c = true`
- `loyaltyPointsBalance` placed in right sidebar; same visibility rule
- `loyaltyVoucherList` placed on Contact page (or in a Tab)
- `loyaltyTransactionHistory` placed — requires `@api lpmId` wired from a parent or wrapper
- `loyaltyTierManagement` (admin tier override) — separate placement; Audience restricted to Loyalty_Admin
- App Builder page activated

## Error Handling
| Error | Handling |
|---|---|
| Session data unavailable | `loyaltyDataService` catches; dashboard shows empty state / spinner |
| Transaction history LC failure | `LoyaltyTransactionService` throws `LoyaltyAPIException`; AuraHandledException → error toast in component |
| Points adjustment fails | `LoyaltyTransactionException`; toast in `loyaltyPointsAdjustment` |
| `@api lpmId` not set on `loyaltyTransactionHistory` | Component renders empty table; no error — silent data gap |

## Security
- All Apex classes — `with sharing`
- `LoyaltyTransactionController.adjustPoints` — no permission check in Apex; rely on App Builder Audience for `loyaltyPointsAdjustment` visibility (see gap below)
- `Loyalty_Agent` can view dashboard and history but cannot see points adjustment modal if App Builder Audience is correctly set

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Enrolled Retail member | `memberType=Retail`, balance=500 | Dashboard shows "Preferred" (or "Elite"); balance 500; no prefix in tier |
| Student member (1.10) | `memberType=Student` | Tier shows "Preferred" not "Student Preferred" |
| Pro member (1.11) | `memberType=Pro` | Tier shows "Elite" not "Pro Elite" |
| CA member | `isCAMember=true` | No expiry date shown |
| No vouchers | Empty `availableVouchers` | Empty state shown in voucher list |
| Transaction history pagination | Call page=2 | Second page of TJs returned |
| Admin adjust +100 | Credit 100 | Balance increases; cache cleared; dashboard refreshes |
| Admin debit 50 | Debit 50 | Balance decreases |

## Validation Queries
```sql
-- Enrolled members visible to dashboard
SELECT Id, Loyalty_Member_Id__c, Loyalty_Member_Type__c, Country_Code__c
FROM Contact WHERE Has_Loyalty__c = true LIMIT 20

-- CA members (no expiry display)
SELECT Id, Country_Code__c FROM Contact WHERE Country_Code__c = 'CA' AND Has_Loyalty__c = true

-- Student and Pro members (tier prefix suppression)
SELECT Id, Loyalty_Member_Type__c FROM Contact
WHERE Loyalty_Member_Type__c IN ('Student', 'Pro') AND Has_Loyalty__c = true
```

## Dependencies
- Story 1.7 — `LoyaltySessionCacheService` must be deployed and cache partition configured
- Story 1.26 — `loyaltyBarcodeDisplay` is a sibling component on the same page
- Named Credential `Loyalty_Cloud_API` configured
- `loyaltyDataService` module deployed (shared across components)

## Known Gaps
- **Welcome Pop-Up (RICEF 1.8)**: referenced as a separate component in RICEF but no dedicated `loyaltyWelcomePopup` LWC exists; the welcome pop-up behavior (show once per session, first name + tier + balance) is expected to be handled by `loyaltyMemberDashboard` JS logic but the "once per session" suppression logic is not implemented
- **`loyaltyTransactionHistory` `@api lpmId` not auto-derived** from recordId; must be wired by a parent wrapper or App Builder dynamic binding — see ui-gaps.md
- **No admin permission guard in `adjustPoints` Apex controller** — `LoyaltyTierController.updateMemberTier` same gap; relies on App Builder Audience only
- **Points-to-next-reward "dial" / progress bar** (RICEF 1.9): `MemberSessionData.nextTierThreshold` and `pointsToNextTier` are returned; whether the LWC renders an actual circular dial vs. a bar is not verifiable without LWC HTML/CSS inspection
