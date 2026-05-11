# Missing Items — Gaps for a Fully Working UI

## Critical (blocks all functionality)

### 1. Named Credential not configured for OAuth
**File:** `force-app/main/default/namedCredentials/Loyalty_Cloud_API.namedCredential-meta.xml`
**Status:** Deployed with `protocol: NoAuthentication`
**Impact:** Every LC API call will fail with 401 or connection error in production
**Fix:** See `manual-setup.md` Section A — switch to OAuth 2.0 in Setup UI after deploy

### 2. Platform Cache Partition not created
**Status:** `LoyaltySessionCacheService` references `local.LoyaltyMemberData` but the partition only exists if an admin creates it
**Impact:** Session caching silently disabled; every dashboard load hits LC API directly (performance + rate limit risk)
**Fix:** Create partition in Setup → Platform Cache (Section B in `manual-setup.md`)

### 3. Flows not activated
**Status:** Three flows deployed in inactive state (Salesforce default for deployed flows)
**Impact:**
- `Welcome_Email_Trigger_Flow` → no welcome email on enrollment
- `Privacy_Request_Handler_Flow` → no status updates on privacy requests
- `RCC_LPM_Attribute_Update_Flow` → RCC batch doesn't trigger attribute sync
**Fix:** Activate all three in Setup → Flows

---

## High (component visible but broken)

### 4. loyaltyTierManagement has no visibility guard
**File:** `force-app/main/default/lwc/loyaltyTierManagement/`
**Status:** Component is `isExposed: true` and targets Contact record page. No permission check in JS.
**Impact:** Any agent can see and use the tier override — should be admin-only
**Fix:** Add App Builder Audience targeting, OR add JS-side permission check:
```js
// In connectedCallback:
hasAdminAccess = await checkPermission(); // no @AuraEnabled method exists for this
```
No Apex method currently checks Loyalty_Admin permission inside LWC. This is a code gap.

### 5. loyaltyBarcodeDisplay requires JsBarcode static resource
**Status:** Static resource referenced but not guaranteed to exist in all orgs
**Impact:** Component renders blank or throws JS error
**Fix:** Verify JsBarcode exists in Setup → Static Resources; upload if missing

### 6. loyaltyPromoEnrollment uses hardcoded @api lpmId
**Status:** `@api lpmId` must be set manually in App Builder or wired from a parent component
**Impact:** If placed directly on Contact record page without a parent feeding lpmId, it shows no data
**Fix:** Component needs either a wire adapter to read `Contact.Loyalty_Member_Id__c`, or a parent wrapper component

### 7. loyaltyTransactionHistory @api lpmId same issue
**Status:** Same as #6 — `@api lpmId` not auto-derived from recordId
**Fix:** Component should wire `Loyalty_Member_Id__c` from `recordId` internally

---

## Medium (functionality works but incomplete)

### 8. No Apex method to validate admin permission for LWC
**Status:** `LoyaltyTierController` has no `@AuraEnabled` method to check if the running user has Loyalty_Admin permission set
**Impact:** Cannot do server-side permission enforcement from LWC
**Missing code:**
```apex
@AuraEnabled(cacheable=true)
public static Boolean hasAdminPermission() {
    return [SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name = 'Loyalty_Admin'] > 0;
}
```

### 9. No SFSC Contact field update after tier change
**Status:** `LoyaltyTierController.updateMemberTier` calls LC API but does NOT update any Contact field
**Impact:** Contact record in SFSC does not reflect the new tier; dashboard may show stale tier
**Fix:** After LC API call, update `Contact.Loyalty_Tier__c` (field would need to be added to Contact object)

### 10. CheckoutService partial redemption rollback not implemented
**File:** `force-app/main/default/classes/orders/CheckoutService.cls`
**Status:** `redeemCertificatesAtSubmission` validates all then redeems all, but if redeem fails mid-loop, no rollback
**Impact:** Partially redeemed vouchers in an order that then fails
**Fix:** Catch exceptions during redeem loop, call `cancelVoucher` on already-redeemed codes

### 11. DeduplicationService.flagDuplicate is a stub
**File:** `force-app/main/default/classes/composite/DeduplicationService.cls`
**Status:** Method body is `System.debug(...)` only — no actual flagging logic
**Impact:** Duplicate flagging does nothing
**Fix:** Implement Case creation or custom flag field update

### 12. OrderFulfilmentEventHandler and OrderCancellationEventHandler need Apex trigger wrappers
**Status:** Handler classes exist but the actual `trigger` files for the platform events need to exist
**Check:** `sf org list metadata --metadata-type ApexTrigger` — verify triggers exist on `Order_Fulfilment_Event__e` and `Order_Cancellation_Event__e`
**If missing:** Create trigger files (not in current source):
```apex
trigger OrderFulfilmentTrigger on Order_Fulfilment_Event__e (after insert) {
    new OrderFulfilmentEventHandler().handleEvents(Trigger.new);
}
```

### 13. No error boundary in LWC components
**Status:** All components catch errors and display generic messages, but no structured error telemetry
**Impact:** Failures silently swallowed; no way to monitor API error rates from LWC
**Fix:** Implement LWC `errorCallback` lifecycle hook in major components

---

## Low (cosmetic / UX)

### 14. loyaltyEnrollmentForm has no field-level validation for Pro/Student types
**Status:** Pro members should require `Pro_License_Number__c`; Student members should require `School_Name__c`
**Impact:** Agents can enroll Pro members without license number
**Fix:** Add conditional required fields in form JS based on selected member type

### 15. loyaltyTransactionHistory shows no empty state when new member
**Status:** Component likely renders empty table with no explanation
**Fix:** Add conditional "No transactions yet" message

### 16. Batch completion email hardcoded to loyalty-ops@company.com
**File:** `RCCCardBatchProcessor.cls` line ~120
**Status:** Not configurable; must be changed at code level
**Fix:** Move email address to `Loyalty_Program_Config__mdt` or a custom setting

### 17. PointsExpiryBatch has no email notification on completion
**Status:** `RCCCardBatchProcessor` sends email; `PointsExpiryBatch` only does `System.debug`
**Fix:** Add equivalent email notification to `PointsExpiryBatch.finish()`

### 18. Privacy deletion does not set Privacy_Deletion_Date__c
**File:** `PrivacyDeletionService.deactivateContact()`
**Status:** Header comment says this field is retained for audit, but `deactivateContact()` never sets it
**Fix:** Add `Privacy_Deletion_Date__c = Date.today()` to the Contact update in `deactivateContact()`
