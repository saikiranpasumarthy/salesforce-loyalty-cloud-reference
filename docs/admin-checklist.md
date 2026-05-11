# Admin Setup Checklist

Check each item after deployment. Items are grouped by phase; complete each phase before starting the next.

---

## Phase 1: Deploy & Core Config

- [ ] `sf project deploy start --source-dir force-app` completed with 0 failures
- [ ] All 67 Apex tests pass (`sf apex run test --test-level RunLocalTests`)
- [ ] **Named Credential — switch to OAuth 2.0**
  - [ ] Setup → Security → Named Credentials → Loyalty Cloud API → Edit
  - [ ] Auth Protocol changed to OAuth 2.0
  - [ ] Auth Provider selected (create one first if needed — see manual-setup.md Section A2)
  - [ ] Authentication successful (no red banner after Save)
- [ ] **Platform Cache Partition created**
  - [ ] Setup → Platform Cache → New Partition
  - [ ] Label: `LoyaltyMemberData`, API Name: `LoyaltyMemberData`
  - [ ] Session Cache: 25 MB; Org Cache: 25 MB

---

## Phase 2: Custom Metadata Verification

- [ ] Setup → Custom Metadata Types → **Loyalty Program Config** → Manage Records
  - [ ] Record `Default` exists with Program API Name = `LevelUp`
  - [ ] `Is_Active__c = true`, `Currency_ISO_Code__c = USD`
  - [ ] (Optional) Record `CA_Program` exists for Canadian members
- [ ] Setup → Custom Metadata Types → **Tier Mapping** → Manage Records
  - [ ] 8 records present: Upper, Base, Conversion, Pro_Elite, Student_Elite, Pro_Preferred, Student_Preferred, Not_Converted
- [ ] Setup → Custom Metadata Types → **Loyalty Exclusion Rule** → Manage Records
  - [ ] 4 records present: Exclude_Fuel, Exclude_Gift_Cards, Exclude_Tobacco, Exclude_Generic_Brand
  - [ ] All 4 have `Is_Active__c = true`

---

## Phase 3: Permission Sets

- [ ] Setup → Permission Sets → **Loyalty Admin** → Manage Assignments
  - [ ] At least one System Administrator assigned
  - [ ] Loyalty operations managers assigned
- [ ] Setup → Permission Sets → **Loyalty Agent** → Manage Assignments
  - [ ] All Service Cloud agents who handle loyalty assigned
- [ ] Setup → Permission Sets → **Loyalty Integration User** → Manage Assignments
  - [ ] Service account user (used by OneTrust / POS) assigned
- [ ] Verify a test agent can see Contact loyalty fields (Has_Loyalty__c, Loyalty_Member_Id__c) — field permissions included in Agent permission set

---

## Phase 4: Flows

- [ ] Setup → Flows → **Privacy Request Handler Flow** → Activate
- [ ] Setup → Flows → **RCC LPM Attribute Update Flow** → Activate
- [ ] Setup → Flows → **Welcome Email Trigger Flow** → Activate
  - [ ] Verify welcome email template/org-wide address is configured (flow needs an email template to send; check flow canvas for Email Action element)

---

## Phase 5: Platform Event Triggers

- [ ] Setup → Apex Triggers → verify trigger on `Order_Fulfilment_Event__e` exists
- [ ] Setup → Apex Triggers → verify trigger on `Order_Cancellation_Event__e` exists
- [ ] (If triggers missing — create per `missing-items.md` item 12)

---

## Phase 6: Lightning App Builder

- [ ] Open a Contact record → Gear icon → Edit Page (or Setup → Lightning App Builder → Contact Record Page)
- [ ] **loyaltyJoinCta** placed on page
  - [ ] Component visibility: `Has_Loyalty__c equals false`
- [ ] **loyaltyMemberDashboard** placed on page
  - [ ] Component visibility: `Has_Loyalty__c equals true`
- [ ] **loyaltyPointsBalance** placed in right sidebar
  - [ ] Component visibility: `Has_Loyalty__c equals true`
- [ ] **loyaltyVoucherList** placed in main column or tab
- [ ] **loyaltyTransactionHistory** placed (lpmId wired if using wrapper)
- [ ] **loyaltyPromoEnrollment** placed (lpmId wired)
- [ ] **loyaltyBarcodeDisplay** placed in right sidebar
- [ ] **loyaltyTierManagement** placed
  - [ ] App Builder Audience: restricted to users with Loyalty_Admin permission set
- [ ] Page **Activated** (Org Default or assigned to specific apps)
- [ ] Create Lightning App Page "Loyalty Enrollment"
  - [ ] **loyaltyEnrollmentForm** placed
  - [ ] Page activated and added to Service Console navigation

---

## Phase 7: Scheduled Batch Jobs

- [ ] Open Developer Console → Execute Anonymous
- [ ] Run: `System.schedule('Annual Points Expiry', '0 0 0 1 1 ? *', new PointsExpiryScheduler());`
- [ ] Run: `System.schedule('Nightly RCC Import', '0 0 2 * * ?', new RCCBatchScheduler());`
- [ ] Verify: Setup → Scheduled Jobs → both jobs appear with correct Next Run times

---

## Phase 8: External Integrations

- [ ] **OneTrust webhook configured**
  - [ ] Salesforce REST endpoint: `/services/apexrest/privacy/delete/`
  - [ ] Auth: OAuth 2.0 connected app credentials (see manual-setup.md Section H)
  - [ ] OneTrust team has Consumer Key + Consumer Secret for service account
  - [ ] Test deletion from OneTrust reaches SFSC (check Privacy_Request__c records)
- [ ] **POS / Xstore integration configured**
  - [ ] REST endpoint: `/services/apexrest/loyalty/lookup`
  - [ ] Auth: same connected app or separate service account
  - [ ] Test lookup by email returns member profile
- [ ] **SFMC (for welcome email)**
  - [ ] Welcome_Email_Trigger_Flow connected to SFMC journey or email alert
  - [ ] Test enrollment → welcome email received

---

## Phase 9: Static Resources

- [ ] Setup → Static Resources → **JsBarcode** exists and is `Public`
- [ ] If missing: upload `JsBarcode.min.js` from https://github.com/lindell/JsBarcode/releases

---

## Phase 10: Smoke Test

- [ ] Create test Contact; enroll via LWC or Execute Anonymous → `Has_Loyalty__c = true`
- [ ] Dashboard loads without error for enrolled Contact
- [ ] Points balance displayed correctly
- [ ] Barcode renders
- [ ] RCC batch processes a test Pending record → Enrolled status
- [ ] Privacy deletion anonymizes Contact fields correctly
- [ ] Batch_Run_Log__c records created after batch runs
- [ ] Scheduled jobs listed in Setup → Scheduled Jobs

---

## Post-Go-Live Monitoring

- [ ] Create list view on `Batch_Run_Log__c` — "Recent Runs" sorted by Completed_At__c DESC
- [ ] Create list view on `RCC_Import_Record__c` — filter: `Status = Failed`
- [ ] Create list view on `Privacy_Request__c` — filter: `Status = In_Progress`
- [ ] Set up Salesforce report on `Order_Points_Status__c` failures (Status = Failed)
- [ ] Verify Named Credential OAuth token does not expire — set up token refresh monitoring
