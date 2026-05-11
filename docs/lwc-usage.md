# LWC Usage — Per-Component Documentation

## c/loyaltyEnrollmentForm

**Purpose:** Standalone form to enroll a new or existing member. Does not require a pre-existing Contact — it matches or creates one internally.

**Targets:** `lightning__AppPage`, `lightning__Tab`, `lightning__RecordPage` (Contact)

**@api properties:** None (self-contained)

**Key behavior:**
- Calls `checkEmailExists(email)` on email field blur to prevent duplicate enrollment
- On submit: calls `enrollMember(contactId, memberType)` or `enrollExistingContact(contactId, memberType)`
- Shows inline error for duplicate email
- Shows success toast and resets form on enrollment success

**Test steps:**
1. Place on a Lightning App Page
2. Enter first name, last name, email, phone, select member type
3. Submit → verify Contact created/updated with `Has_Loyalty__c = true`

**Dependencies:** `LoyaltyEnrollmentController` (Apex)

---

## c/loyaltyJoinCta

**Purpose:** Single "Enroll" CTA button. Self-hides when the Contact is already a loyalty member.

**Targets:** `lightning__RecordPage` (Contact only)

**@api properties:**
| Property | Type | Default | Description |
|---|---|---|---|
| `recordId` | Id | auto | Contact record Id — auto-populated by record page |
| `memberType` | String | `'Retail'` | Default member type for enrollment |

**Key behavior:**
- Wire adapter reads `Contact.Has_Loyalty__c` — renders null when true
- On click: calls `LoyaltyEnrollmentController.enrollMember(recordId, memberType)`
- Fires `refreshView` standard event after success

**Test steps:**
1. Open Contact record with `Has_Loyalty__c = false`
2. Verify button visible; click it; verify Contact enrolled and button disappears

---

## c/loyaltyMemberDashboard

**Purpose:** Primary agent dashboard. Shows points, tier, active vouchers summary, and hosts the points adjustment tool.

**Targets:** `lightning__RecordPage` (Contact)

**@api properties:**
| Property | Type | Default | Description |
|---|---|---|---|
| `recordId` | Id | auto | Contact record Id |

**Key behavior:**
- On load: calls `LoyaltyTransactionController.getSessionLoyaltyData(recordId)` (uses Session Cache)
- Refresh button: calls `refreshLoyaltyData(recordId)` — clears cache and reloads
- Points adjustment: opens `loyaltyPointsAdjustment` modal (embedded, no extra placement needed)
- Shows spinner while loading; error state with retry button on failure

**Test steps:**
1. Open enrolled Contact record
2. Verify dashboard shows points balance, tier, voucher count
3. Click Refresh — verify data reloads without error
4. Click "Adjust Points" — verify modal opens

**Dependencies:** `LoyaltyTransactionController`, `LoyaltySessionCacheService`, `c/loyaltyPointsAdjustment`

---

## c/loyaltyPointsAdjustment

**Purpose:** Two-step points adjustment dialog (Credit or Debit). Not directly placeable — rendered inside `loyaltyMemberDashboard`.

**isExposed:** false

**@api properties:**
| Property | Type | Required | Description |
|---|---|---|---|
| `lpmId` | String | Yes | Loyalty Program Membership Id from LC |

**Key behavior:**
- Step 1: User selects Credit/Debit, enters amount and reason
- Step 2: Confirmation screen shows summary before committing
- Calls `LoyaltyTransactionController.adjustPoints(lpmId, amount, type, reason)`
- Routes to `creditPoints` or `debitPoints` API call based on type

**Validation:** Amount must be > 0; reason must be non-blank

---

## c/loyaltyPointsBalance

**Purpose:** Lightweight points balance tile with 5-minute client-side TTL cache.

**Targets:** `lightning__RecordPage` (Contact)

**@api properties:**
| Property | Type | Default | Description |
|---|---|---|---|
| `recordId` | Id | auto | Contact record Id |

**Key behavior:**
- Caches balance in component state for 5 minutes
- Shows formatted number with label "Points Balance"
- Auto-refreshes on mount if cache expired

**Test steps:**
1. Open enrolled Contact record
2. Verify numeric balance displayed
3. Adjust points via dashboard; navigate away and back — verify balance updates within 5 min

---

## c/loyaltyVoucherList

**Purpose:** Full list of member vouchers with client-side filtering by status.

**Targets:** `lightning__RecordPage` (Contact)

**@api properties:**
| Property | Type | Default | Description |
|---|---|---|---|
| `recordId` | Id | auto | Contact record Id |

**Key behavior:**
- Reads vouchers from `LoyaltySessionCacheService` data (same call as dashboard)
- Client-side filter tabs: Active / Redeemed / Expired
- No server call on tab change — all vouchers loaded at once, filtered in JS
- Each voucher shows: code, description, expiry date, discount value

**Test steps:**
1. Open enrolled Contact with at least one voucher in LC
2. Verify Active tab shows voucher
3. Switch tabs — verify correct filtering without spinner

---

## c/loyaltyTransactionHistory

**Purpose:** Paginated transaction journal with date range and journal type filters.

**Targets:** `lightning__RecordPage` (Contact)

**@api properties:**
| Property | Type | Required | Description |
|---|---|---|---|
| `lpmId` | String | Yes | Loyalty Program Membership Id — must be wired from parent |
| `recordId` | Id | No | Contact Id (for future use) |

**Key behavior:**
- Default: loads last 30 days of transactions, 10 per page
- Date filters: from/to date inputs
- Type filter: Purchase, Adjustment, Expiry, Reversal
- Pagination: Previous/Next buttons with page counter
- Each row: date, type, points, order reference

**⚠️ App Builder note:** `lpmId` must be wired from `Contact.Loyalty_Member_Id__c` — either via a parent wrapper or by modifying the component to self-fetch from recordId.

**Test steps:**
1. Place component on Contact page with lpmId wired
2. Verify recent transactions load
3. Apply date filter — verify response filtered
4. Click Next page — verify pagination works

---

## c/loyaltyPromoEnrollment

**Purpose:** Lists available promotions for the member; allows enrollment and opt-out per promotion.

**Targets:** `lightning__RecordPage` (Contact)

**@api properties:**
| Property | Type | Required | Description |
|---|---|---|---|
| `lpmId` | String | Yes | Loyalty Program Membership Id |

**Key behavior:**
- On load: calls `LoyaltyPromotionController.getMemberPromotions(lpmId)`
- Each promotion shows: name, description, start/end dates, enrollment status
- "Enroll" button → `enrollForPromotion(lpmId, promotionName)`
- "Opt Out" button (for enrolled) → `optOutFromPromotion(lpmId, promotionName)`
- Refreshes list after each action

**⚠️ App Builder note:** Same `lpmId` wiring issue as `loyaltyTransactionHistory`.

---

## c/loyaltyTierManagement

**Purpose:** Admin-only tool to manually override a member's tier in Loyalty Cloud.

**Targets:** `lightning__RecordPage` (Contact)

**@api properties:**
| Property | Type | Required | Description |
|---|---|---|---|
| `lpmId` | String | Yes | Loyalty Program Membership Id |
| `currentTier` | String | No | Current tier displayed in form |

**Key behavior:**
- Dropdown: Preferred / Elite
- Required reason text field (min 10 chars)
- Calls `LoyaltyTierController.updateMemberTier(lpmId, tier, reason)` on submit
- Shows success/error toast

**⚠️ Permission:** Requires `Loyalty_Admin` permission set. No server-side guard in the LWC controller — restrict via App Builder Audience targeting.

---

## c/loyaltyBarcodeDisplay

**Purpose:** Renders a scannable barcode of the member's LC membership ID.

**Targets:** `lightning__RecordPage` (Contact)

**@api properties:**
| Property | Type | Default | Description |
|---|---|---|---|
| `recordId` | Id | auto | Contact record Id (reads Loyalty_Member_Id__c via wire) |

**Key behavior:**
- Wire adapter reads `Contact.Loyalty_Member_Id__c`
- On data: calls `JsBarcode` (static resource) to render SVG barcode
- Shows membership ID as text below barcode
- Falls back to "No loyalty ID" message if not enrolled

**Dependencies:** `JsBarcode` static resource (must exist in org)

---

## c/loyaltyDataService

**Purpose:** Shared service module providing in-memory caching of LC data across sibling components on the same page.

**isExposed:** false — not placeable, imported by other components only

**Exports:**
| Function | Arguments | Returns | Description |
|---|---|---|---|
| `getLoyaltyData(lpmId)` | lpmId: String | Promise<MemberSessionData> | Returns cached data or fetches from Apex |
| `refreshLoyaltyDataForContact(lpmId)` | lpmId: String | Promise<MemberSessionData> | Clears cache entry and fetches fresh |
| `clearLoyaltyCache(lpmId)` | lpmId: String | void | Removes entry from in-memory cache |

**Cache:** JS `Map` keyed by lpmId; 30-minute TTL enforced by timestamp check

**Import example:**
```js
import { getLoyaltyData, refreshLoyaltyDataForContact } from 'c/loyaltyDataService';
```
