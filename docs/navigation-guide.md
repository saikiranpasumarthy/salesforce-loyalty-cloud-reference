# Navigation Guide — LWC Placement in Lightning App Builder

## Prerequisites
All components require the **Loyalty_Agent** or **Loyalty_Admin** permission set assigned to the user.

---

## Contact Record Page Components

Open: **Setup → App Builder → Contact Record Page** (or open a Contact record → click the gear icon → Edit Page)

### 1. loyaltyJoinCta
**Purpose:** "Enroll" call-to-action button. Self-hides when Contact is already enrolled.
- **Page type:** Record Page — Contact
- **Placement:** Right sidebar, top section (above loyalty dashboard)
- **Visibility filter:** `Has_Loyalty__c = false` (add component visibility rule in App Builder)
- **@api props to set in App Builder:** `memberType` (default: `Retail`) — set to preferred default for your member base

### 2. loyaltyMemberDashboard
**Purpose:** Main dashboard showing points, tier, vouchers, and quick-action buttons.
- **Page type:** Record Page — Contact
- **Placement:** Main column, below standard details
- **Visibility filter:** `Has_Loyalty__c = true`
- **No @api props to configure** — reads `recordId` automatically
- **Contains embedded sub-component:** `loyaltyPointsAdjustment` — no separate placement needed

### 3. loyaltyPointsBalance
**Purpose:** Lightweight points balance tile (use when dashboard is too heavy).
- **Page type:** Record Page — Contact
- **Placement:** Right sidebar or compact layout area
- **Visibility filter:** `Has_Loyalty__c = true`
- **Notes:** 5-minute client-side cache; independent of Session Cache

### 4. loyaltyVoucherList
**Purpose:** List all vouchers with Active/Redeemed/Expired filter tabs.
- **Page type:** Record Page — Contact
- **Placement:** Main column, below dashboard
- **Visibility filter:** `Has_Loyalty__c = true`

### 5. loyaltyTransactionHistory
**Purpose:** Paginated transaction journal with date range and type filters.
- **Page type:** Record Page — Contact
- **Placement:** Main column, tab within a Tabs component
- **Visibility filter:** `Has_Loyalty__c = true`
- **@api props:** `lpmId` — wire this from the Contact's `Loyalty_Member_Id__c` field

### 6. loyaltyBarcodeDisplay
**Purpose:** Shows scannable barcode of loyalty ID for in-store use.
- **Page type:** Record Page — Contact
- **Placement:** Right sidebar
- **Visibility filter:** `Has_Loyalty__c = true`
- **Dependency:** Requires `JsBarcode` static resource deployed (included in source)

### 7. loyaltyPromoEnrollment
**Purpose:** Lists available promotions; allows enroll/opt-out per promotion.
- **Page type:** Record Page — Contact
- **Placement:** Main column, Promotions tab
- **Visibility filter:** `Has_Loyalty__c = true`
- **@api props:** `lpmId` — wire from `Loyalty_Member_Id__c`

### 8. loyaltyTierManagement
**Purpose:** Admin-only tier override tool.
- **Page type:** Record Page — Contact
- **Placement:** Admin section at bottom or separate "Admin" tab
- **Visibility filter:** User has Loyalty_Admin permission set (use App Builder Audience targeting)
- **@api props:** `lpmId`, `currentTier` — both required

---

## App Page / Tab Components

### 9. loyaltyEnrollmentForm
**Purpose:** Standalone enrollment form for new member sign-up (not tied to a specific Contact record).
- **Page type:** Lightning App Page OR Tab within Service Console
- **Placement:** Full-width main content area
- **Creation steps:**
  1. Setup → App Builder → New → App Page
  2. Name: "Loyalty Enrollment" → Choose layout: One Region
  3. Drag `loyaltyEnrollmentForm` into the region
  4. Activate → assign to Loyalty Service app or Service Console
- **No @api props** — form is self-contained; creates/matches Contact internally

---

## loyaltyDataService (service module)
- **isExposed: false** — this is NOT placed in App Builder
- It is imported by sibling components via: `import { getLoyaltyData } from 'c/loyaltyDataService'`
- No placement action required; it is bundled automatically with components that import it

---

## Recommended Contact Record Page Layout

```
┌─────────────────────────────────────────────────────────┐
│ MAIN COLUMN                    │ RIGHT SIDEBAR           │
│                                │                         │
│ [Standard Contact Details]     │ loyaltyJoinCta          │
│                                │ (hidden when enrolled)  │
│ [loyaltyMemberDashboard]       │                         │
│   (includes points adjustment) │ loyaltyPointsBalance    │
│                                │                         │
│ ┌─ Tabs ──────────────────┐   │ loyaltyBarcodeDisplay   │
│ │ Vouchers │ History │ Promos│  │                         │
│ │                           │  │                         │
│ │ loyaltyVoucherList        │  │                         │
│ │ loyaltyTransactionHistory │  │                         │
│ │ loyaltyPromoEnrollment    │  │                         │
│ └───────────────────────────┘  │                         │
│                                │                         │
│ [loyaltyTierManagement]        │                         │
│ (Admin audience only)          │                         │
└─────────────────────────────────────────────────────────┘
```

---

## Activating and Assigning Pages

1. After placing components, click **Activate** in App Builder
2. Choose activation type:
   - **Assign as org default** — applies to all Contact records
   - **Assign to apps** — apply only within Service Console or specific Lightning App
3. Under **Assign to Users** or **Audiences** — restrict `loyaltyTierManagement` visibility to users with Loyalty_Admin permission set using the Audience feature

---

## Service Console Setup

To add Loyalty Enrollment as a console workspace tab:
1. Setup → App Manager → Service Console → Edit
2. Navigation Items → Add `Loyalty Enrollment` page (Lightning App Page created above)
3. Save and deploy
