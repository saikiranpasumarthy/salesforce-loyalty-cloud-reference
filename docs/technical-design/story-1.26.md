# STORY-1.26 — App Barcode: Loyalty ID Display

**RICEF ID:** 1.26 | **Type:** UI | **Complexity:** Low | **Module:** SFSC

## Business Purpose
Display the member's Loyalty ID as a scannable CODE128 barcode on the Contact record page so store associates and POS systems can scan the member's digital card at checkout.

## Assumptions
- `loyaltyBarcodeDisplay` reads `Loyalty_Member_Id__c` from the Contact record via `getRecord` wire
- JsBarcode library (CODE128 format) renders the barcode as an SVG element
- No Apex callout is made — all data comes from SFSC field via Lightning UI API
- Guest/non-loyalty members see an empty state ("No loyalty ID") — no barcode rendered
- `JsBarcode` static resource must be uploaded before deploying this component

## User Flow
1. Agent opens a Contact record page → `loyaltyBarcodeDisplay` mounts
2. `connectedCallback` initiates `loadScript(JsBarcode)` to load the barcode library
3. `@wire(getRecord)` fetches `Loyalty_Member_Id__c`, `FirstName`, `LastName` from the Contact
4. When both script and field data are ready → `renderBarcode()` called
5. SVG element populated with CODE128 barcode for `Loyalty_Member_Id__c`
6. Member name displayed below barcode
7. Agent taps "Refresh" → `handleRefresh()` re-renders the SVG

## Components

**LWC:**
| Component | Purpose |
|---|---|
| `loyaltyBarcodeDisplay` | Renders scannable CODE128 barcode from `Loyalty_Member_Id__c`; `@api recordId` wired from record page |

**Apex:** None — reads Contact fields via Lightning UI API only

**Flows:** None

**Platform Events:** None

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Contact` | `Loyalty_Member_Id__c`, `FirstName`, `LastName` | None |

**Static Resources:**
- `JsBarcode` — `JsBarcode.all.min.js` uploaded as static resource; referenced via `@salesforce/resourceUrl/JsBarcode`

**Permission Sets:**
- `Loyalty_Agent` — minimum; required to view the Contact record page

## API Integration
None — no Apex callout; reads Contact field via Lightning Data Service `getRecord` wire adapter.

## Execution Sequence
```
1. loyaltyBarcodeDisplay.connectedCallback()
   → loadScript(this, JsBarcode) [async]
   → .then: isScriptLoaded = true; renderBarcode()

2. @wire(getRecord, {recordId, fields: [LOYALTY_ID_FIELD, FIRST_NAME_FIELD, LAST_NAME_FIELD]})
   → wiredRecord({data})
   → loyaltyId  = getFieldValue(data, LOYALTY_ID_FIELD)
   → memberName = `${FirstName} ${LastName}`.trim()
   → renderBarcode()

3. renderBarcode()
   → if (!isScriptLoaded || !loyaltyId) return  [guard: wait for both]
   → svgEl = this.refs?.barcodeEl
   → JsBarcode(svgEl, loyaltyId, {
       format: 'CODE128',
       width: 2,
       height: 60,
       displayValue: false,
       margin: 10
     })
   → SVG rendered in DOM

4. handleRefresh() (manual refresh button)
   → renderBarcode()  [re-renders SVG in-place]
```

## Manual Setup Required
- Upload `JsBarcode.all.min.js` as a static resource named `JsBarcode`
  - Download from https://github.com/lindell/JsBarcode/releases
  - Static Resource API Name must be exactly `JsBarcode`
- Place `loyaltyBarcodeDisplay` on the Contact record page in App Builder
  - Set visibility: `Has_Loyalty__c = true` to hide for non-loyalty contacts
- `Loyalty_Agent` permission set assigned to users who need to view the component

## Error Handling
| Error | Handling |
|---|---|
| `JsBarcode` static resource not found | `loadScript` rejects; `console.error('JsBarcode load failed:', e)`; barcode never renders |
| `Loyalty_Member_Id__c` is blank | `hasLoyaltyId` getter returns false; HTML template shows "No loyalty ID" empty state |
| `@wire(getRecord)` error | `wiredRecord({error})` path; field values remain null; renderBarcode no-ops |
| `this.refs?.barcodeEl` not in DOM | `renderBarcode` returns early on null ref; no crash |
| SVG render fails (JsBarcode exception) | Uncaught; console error; SVG element may be blank — no graceful recovery in current code |

## Security
- `loyaltyBarcodeDisplay` — Lightning component; runs in LWS (Lightning Web Security) sandbox
- No Apex callout; no PII transmitted; loyalty ID is a non-reversible opaque identifier
- Access controlled at the App Builder visibility rule level
- Static resource is public (no access restriction on the resource itself)

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Enrolled member | `Loyalty_Member_Id__c = 'MBR-10001'` | CODE128 barcode rendered in SVG |
| Non-loyalty member | `Has_Loyalty__c = false` | Component hidden by App Builder visibility rule |
| Loyalty ID present but blank | `Loyalty_Member_Id__c = null` | Empty state ("No loyalty ID") shown |
| JsBarcode not uploaded | Static resource missing | `loadScript` fails; barcode section empty; console error |
| Refresh button clicked | Any state | `renderBarcode()` re-called; SVG re-drawn |

## Validation Queries
```sql
-- Contacts with Loyalty IDs (should show barcode)
SELECT Id, FirstName, LastName, Loyalty_Member_Id__c
FROM Contact WHERE Loyalty_Member_Id__c != null AND Has_Loyalty__c = true LIMIT 20

-- Contacts where barcode would render empty
SELECT Id, Loyalty_Member_Id__c
FROM Contact WHERE Has_Loyalty__c = true AND Loyalty_Member_Id__c = null
```

## Dependencies
- Story 1.7 — session data is not required here; component reads directly from the Contact record
- `JsBarcode` static resource deployed before package install
- No dependency on LC API or Platform Cache

## Known Gaps
- **No refresh-on-enroll**: if a Contact is enrolled mid-session and `Loyalty_Member_Id__c` is written, the component does not automatically re-render (the `@wire` adapter will re-fire on field change, but only if the record page is still open and the wire cache updates)
- **Single static barcode**: there is no "hide barcode after scan" or one-time-use token pattern; the same static `Loyalty_Member_Id__c` renders every time — POS must handle repeat scans idempotently
- **No print/download**: no button to download the SVG as PNG or open a print-friendly view
- **`this.refs?.barcodeEl` requires LWS refs API**: if deployed to orgs without LWS (legacy orgs), `this.refs` may be undefined; fallback to `this.template.querySelector('[data-ref="barcodeEl"]')` should be considered
