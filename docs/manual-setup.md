# Manual Setup — Post-Deploy Configuration

Run these steps after `sf project deploy start` succeeds. Order matters where noted.

---

## A. Named Credential — OAuth Setup (REQUIRED — nothing works without this)

The deployed Named Credential `Loyalty Cloud API` uses `NoAuthentication` protocol so the deploy does not fail. Switch to OAuth before testing:

1. **Setup → Security → Named Credentials → Loyalty Cloud API → Edit**
2. Change **URL** to your actual Loyalty Cloud org URL (same org or sandbox)
3. Change **Auth Protocol** to `OAuth 2.0`
4. Set **Auth Provider** (must exist first — see step A2 below)
5. Set **Identity Type** to `Named Principal` or `Per User` based on your architecture
6. Check **Generate Authorization Header**
7. Click **Save** → authenticate when prompted

### A2. Create Auth Provider (before A above)
1. **Setup → Auth. Providers → New**
2. Provider Type: `Salesforce` (or `Open ID Connect` if using external IdP)
3. Consumer Key / Consumer Secret: from your Loyalty Cloud Connected App
4. Default Scopes: `api refresh_token`
5. Save — copy the **Callback URL** shown
6. Go to Loyalty Cloud org → Connected App → update redirect URI with this callback URL

---

## B. Platform Cache Partition (REQUIRED for session caching)

The `LoyaltySessionCacheService` uses partition `local.LoyaltyMemberData`. If missing, caching is silently skipped (no error), but performance degrades.

1. **Setup → Platform Cache → New Platform Cache Partition**
2. Label: `LoyaltyMemberData`
3. API Name: `LoyaltyMemberData`
4. Session Cache: **25 MB** (minimum; increase based on expected concurrent agents)
5. Org Cache: **25 MB**
6. Save

---

## C. Custom Metadata — Verify Records

Records are deployed from source but verify they loaded correctly:

1. **Setup → Custom Metadata Types → Loyalty Program Config → Manage Records**
   - Verify record `Default` exists with:
     - Program API Name: `LevelUp`
     - Currency ISO Code: `USD`
     - Max Enrollments Per Day: `5000`
     - Points Expiry Days: `365`
     - Is Active: checked
   - If you have a Canadian program: verify record `CA_Program` exists

2. **Setup → Custom Metadata Types → Tier Mapping → Manage Records**
   - Verify 8 records exist: Upper, Base, Conversion, Pro_Elite, Student_Elite, Pro_Preferred, Student_Preferred, Not_Converted

3. **Setup → Custom Metadata Types → Loyalty Exclusion Rule → Manage Records**
   - Verify 4 records: Exclude_Fuel, Exclude_Gift_Cards, Exclude_Tobacco, Exclude_Generic_Brand
   - All should have `Is_Active__c = true`

---

## D. Permission Sets — Assign to Users

1. **Setup → Permission Sets → Loyalty Admin → Manage Assignments → Add Assignments**
   - Assign to: Loyalty Operations admins, system administrators managing the program

2. **Setup → Permission Sets → Loyalty Agent → Manage Assignments → Add Assignments**
   - Assign to: All Service Cloud agents who handle loyalty inquiries

3. **Setup → Permission Sets → Loyalty Integration User → Manage Assignments**
   - Assign to: the Service Account used by OneTrust and any external system making REST API calls

---

## E. Lightning App Builder — Page Activation

Components are deployed but not yet visible until pages are activated:

1. **Setup → Lightning App Builder → Contact Record Page → Edit** (or create new)
2. Add components per the navigation guide (see `navigation-guide.md`)
3. Click **Activate** → select **Assign as Org Default** or assign to specific apps
4. For `loyaltyEnrollmentForm`:
   - Create a new **App Page** named "Loyalty Enrollment"
   - Add the component to the page
   - Activate and assign to Service Console

---

## F. Flows — Activate

Three flows are deployed in inactive state:

1. **Setup → Flows → Privacy Request Handler Flow → Activate**
   - Handles `Privacy_Request__c` status transitions after deletion

2. **Setup → Flows → RCC LPM Attribute Update Flow → Activate**
   - Updates LPM attributes when RCC card batch runs

3. **Setup → Flows → Welcome Email Trigger Flow → Activate**
   - Sends welcome email on `Loyalty_Enrollment_Event__e` platform event
   - **Dependency:** Requires SFMC integration or Email Alert configured in org

---

## G. Platform Event — Subscribe Flows/Triggers

The three platform events need subscribers:

| Event | Expected Subscriber | What to do |
|---|---|---|
| `Loyalty_Enrollment_Event__e` | `Welcome_Email_Trigger_Flow` | Flow handles this — just activate the flow (step F) |
| `Order_Fulfilment_Event__e` | `OrderFulfilmentEventHandler` (Apex trigger) | Trigger deployed — verify it exists under Setup → Apex Triggers |
| `Order_Cancellation_Event__e` | `OrderCancellationEventHandler` (Apex trigger) | Same — verify trigger exists |

---

## H. Connected App — For REST API Callers

External systems (OneTrust, POS) call the REST endpoints. They need OAuth tokens:

1. **Setup → App Manager → New Connected App**
2. Name: `Loyalty Integration`
3. Enable OAuth: check
4. Callback URL: `https://login.salesforce.com/services/oauth2/success`
5. Scopes: `api`, `refresh_token`
6. Save → copy Consumer Key + Consumer Secret
7. Share credentials with OneTrust admin and POS integration team
8. Assign `Loyalty_Integration_User` permission set to the service account user

---

## I. Scheduled Jobs — Batch Processors

Batch jobs are not auto-scheduled. Schedule manually via Developer Console or Setup:

**PointsExpiryScheduler** (annual — January 1):
```apex
// Run in Developer Console → Execute Anonymous
System.schedule('Annual Points Expiry', '0 0 0 1 1 ? *', new PointsExpiryScheduler());
```

**RCCBatchScheduler** (nightly — 02:00):
```apex
// Run in Developer Console → Execute Anonymous
System.schedule('Nightly RCC Import', '0 0 2 * * ?', new RCCBatchScheduler());
```

Verify: **Setup → Scheduled Jobs** — both should appear.

---

## J. Email Alert for Batch Completion

`RCCCardBatchProcessor.finish()` sends email to `loyalty-ops@company.com`. Before go-live:
1. Verify `loyalty-ops@company.com` is a valid deliverable address
2. OR update the address in `RCCCardBatchProcessor.cls` line ~120 before deploying

---

## K. Verify Static Resources

`loyaltyBarcodeDisplay` uses `JsBarcode` static resource:
1. **Setup → Static Resources** → confirm `JsBarcode` exists and is Public
2. If missing: upload `JsBarcode.min.js` from https://github.com/lindell/JsBarcode/releases

---

## L. Remote Site Settings (if Named Credential is not used)

If you bypass Named Credentials and call the LC API directly:
1. **Setup → Remote Site Settings → New**
2. Name: `LoyaltyCloud`
3. URL: your LC org URL
4. Active: checked

This is a fallback only — prefer Named Credentials.

---

## Deployment Order Summary

```
1. Deploy metadata (sf project deploy start)
2. Create Auth Provider (Setup)
3. Configure Named Credential OAuth (Setup)
4. Create Platform Cache partition
5. Verify Custom Metadata records
6. Assign Permission Sets to users
7. Activate Flows
8. Schedule batch jobs (Execute Anonymous)
9. Activate Lightning App Builder pages
10. Create Connected App for external callers
```
