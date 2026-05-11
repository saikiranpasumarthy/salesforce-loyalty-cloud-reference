# UI Gaps — Missing Metadata Preventing LWC Visibility

## What "UI Gap" means here
A component is deployed and functional in Apex/JS but cannot be seen by end users because some Salesforce UI configuration layer is missing or incomplete.

---

## Gap 1: No Lightning App Builder page activations

**Components affected:** All 9 exposed LWC components
**Status:** Components are deployed to the org but not placed on any Lightning page. An LWC component cannot appear on a record page until:
1. An admin places it in Lightning App Builder
2. The page is activated

**What the user sees:** Nothing. The Contact record looks like a standard layout.

**Fix:** Follow `navigation-guide.md` to place and activate all components.

---

## Gap 2: No App Builder Audience targeting for loyaltyTierManagement

**Status:** `loyaltyTierManagement` is `isExposed: true` and listed for Contact record pages, but there is no built-in audience restriction in the component's `*.js-meta.xml`. Once placed on a page, it is visible to all users who can view that Contact record.

**Missing:** An App Builder Audience rule limiting this component to users with the `Loyalty_Admin` permission set.

**Fix in App Builder:**
1. Select `loyaltyTierManagement` on the page
2. In the properties panel, click "Set Component Visibility"
3. Add rule: Permission = `Loyalty Admin`
4. Save and activate

**Or:** Add a `@wire(getPermissionSetAssignment)` check inside the JS — but no `@AuraEnabled` method to query this exists in the codebase (see `missing-items.md` item 8).

---

## Gap 3: loyaltyJoinCta has no App Builder visibility rule for Has_Loyalty__c

**Status:** The component's JS code hides itself reactively when `Has_Loyalty__c` becomes true (via wire), but the component is still rendered in the DOM and makes an Apex call even for enrolled members. The JS-level hide is correct but wastes an Apex call.

**Better approach:** Add an App Builder component visibility condition:
- Filter field: `Contact.Has_Loyalty__c`
- Condition: `equals false`

This prevents the component from rendering at all for enrolled members.

---

## Gap 4: loyaltyMemberDashboard has no visibility rule for unenrolled members

**Status:** If placed without a visibility rule, the dashboard renders for unenrolled contacts and shows an error state (or spinner) because `Loyalty_Member_Id__c` is blank.

**Fix:** App Builder visibility rule:
- Filter field: `Contact.Has_Loyalty__c`
- Condition: `equals true`

---

## Gap 5: loyaltyEnrollmentForm not placed in any App Page or Console Tab

**Status:** Component exists and is `isExposed: true` with targets `lightning__AppPage` and `lightning__Tab`, but no App Page has been created for it.

**What the user sees:** There is no tab or page where agents can enroll a new (non-Contact-linked) member.

**Fix:** Create a Lightning App Page named "Loyalty Enrollment", add the component, activate, and add to Service Console navigation items. Steps in `navigation-guide.md` Section 9.

---

## Gap 6: loyaltyPromoEnrollment and loyaltyTransactionHistory require lpmId wiring

**Status:** Both components declare `@api lpmId`. When placed directly on a Contact record page in App Builder, App Builder cannot automatically wire `Contact.Loyalty_Member_Id__c` into the `lpmId` property because App Builder only auto-provides `recordId`.

**What the user sees:** Component renders but shows no data (lpmId is null/undefined).

**Fix options:**
1. **Wrapper component approach:** Create a thin parent LWC that reads `Loyalty_Member_Id__c` via wire and passes it to the child as `lpmId`
2. **Update the component:** Change components to accept `recordId` and internally fetch `Loyalty_Member_Id__c` via wire
3. **App Builder dynamic binding (Summer '23+):** Some orgs support dynamic property binding from record fields — check if your org version supports it

The simplest fix is option 2: add a wire for `getRecord` inside each component.

---

## Gap 7: No Tab in Service Console for Loyalty Operations

**Status:** There is no Lightning App configuration pointing agents to the Loyalty Enrollment form or a loyalty-specific work area.

**Fix:** In Setup → App Manager → Service Console (Lightning):
1. Add "Loyalty Enrollment" App Page as a nav item
2. Optionally add a "Loyalty Operations" tab grouping enrollment form + batch log view

---

## Gap 8: No List View for RCC_Import_Record__c or Batch_Run_Log__c

**Status:** Objects are deployed with full schema but no list views defined in source. Admins cannot easily monitor batch run status without writing SOQL.

**Fix (Setup UI):**
1. Setup → Object Manager → RCC Import Record → List Views → New
2. Create "All Pending" view (filter: Status = Pending)
3. Create "Recent Failures" view (filter: Status = Failed, sorted by CreatedDate DESC)
4. Repeat for Batch Run Log — create "Recent Runs" view

---

## Gap 9: No Quick Action for Privacy Deletion on Contact

**Status:** `PrivacyDeletionController` has `@AuraEnabled` methods but there is no Quick Action or Flow Screen defined to expose this to agents from the Contact page.

**Missing:** A Lightning component or Flow Screen that lets a Service Cloud agent initiate a GDPR deletion from the Contact record (rather than requiring a REST API call from OneTrust).

---

## Gap 10: Custom Labels not localised

**Status:** A `CustomLabels.labels-meta.xml` exists in source. LWC components that reference labels will work, but no translated variants are defined. For multi-language orgs, all labels will show English text only.

**Fix:** Add translations via Setup → Translation Workbench if needed.
