# Tester Walkthrough

Step-by-step instructions for a tester verifying the deployment end-to-end. Prerequisites: org deployed, Named Credential configured, permission sets assigned.

---

## Setup: Create Test Data

Run in **Developer Console → Execute Anonymous**:

```apex
// Create a test Contact (not yet enrolled)
Contact c = new Contact(
    FirstName = 'Test',
    LastName = 'LoyaltyUser',
    Email = 'loyalty.tester@example.com',
    Phone = '+15551234567',
    Country_Code__c = 'US'
);
insert c;
System.debug('Test Contact Id: ' + c.Id);
// Copy the Id from debug log for steps below
```

---

## Test 1: View Enrollment CTA

1. Open the Contact record for `Test LoyaltyUser`
2. On the right sidebar, you should see the **loyaltyJoinCta** component with an "Enroll" button
3. Verify the button is visible (component shows when `Has_Loyalty__c = false`)
4. **PASS criteria:** Button visible; no JS errors in browser console

---

## Test 2: Enroll the Member

**Option A — via LWC (if pages are activated):**
1. Click the "Enroll" button in `loyaltyJoinCta`
2. Select Member Type: `Retail`
3. Click Submit
4. Verify: success toast appears; `loyaltyJoinCta` disappears; `loyaltyMemberDashboard` appears

**Option B — via Developer Console (if LWC not yet placed):**
```apex
String contactId = '<paste Contact Id here>';
LoyaltyEnrollmentController.enrollMember(contactId, 'Retail');
```
Then refresh the Contact record page.

**Verify in SOQL:**
```sql
SELECT Has_Loyalty__c, Loyalty_Member_Id__c, Loyalty_Member_Type__c
FROM Contact WHERE Email = 'loyalty.tester@example.com'
```
**PASS criteria:** `Has_Loyalty__c = true`, `Loyalty_Member_Id__c` is a non-blank string

---

## Test 3: View Member Dashboard

1. Open the enrolled Contact record
2. The `loyaltyMemberDashboard` should appear
3. Verify it shows:
   - Points balance (any number, even 0)
   - Tier (Preferred or Elite)
   - Vouchers section (empty is OK for new member)
4. **PASS criteria:** No spinner stuck; no "Error loading data" message

If dashboard shows error: check Named Credential OAuth setup and run `LoyaltySessionCacheService` test from Execute Anonymous.

---

## Test 4: View Points Balance

1. On the same Contact record, locate `loyaltyPointsBalance` in right sidebar
2. Should display a numeric balance
3. **PASS criteria:** Balance displayed; refreshes independently of dashboard

---

## Test 5: Manual Points Adjustment

1. In `loyaltyMemberDashboard`, click the "Adjust Points" button (opens `loyaltyPointsAdjustment`)
2. Select Type: `Credit`, Amount: `100`, Reason: `Test adjustment`
3. Click the confirm button (two-step flow)
4. Verify: success message; dashboard refreshes; balance increases by 100

**Verify via Execute Anonymous:**
```apex
String lpmId = [SELECT Loyalty_Member_Id__c FROM Contact WHERE Email='loyalty.tester@example.com'].Loyalty_Member_Id__c;
LoyaltyTransactionController.adjustPoints(lpmId, 100, 'Credit', 'Test');
```
**PASS criteria:** No exception thrown; LC API returns 200

---

## Test 6: View Transaction History

1. On the Contact record, locate `loyaltyTransactionHistory`
2. If paginated: verify first page loads
3. Set a date filter (from 1 year ago to today) — verify filtered results
4. **PASS criteria:** Table renders; pagination controls work; date filter applies without error

---

## Test 7: View Vouchers

1. Locate `loyaltyVoucherList` on Contact record
2. Click tabs: Active / Redeemed / Expired
3. New members will see empty Active tab — this is correct
4. **PASS criteria:** Tab switching works without error; empty state shows (not spinner stuck)

---

## Test 8: Barcode Display

1. Locate `loyaltyBarcodeDisplay` on Contact record
2. Should show a barcode image with the member's loyalty ID encoded
3. If blank: verify `JsBarcode` static resource exists (Setup → Static Resources)
4. **PASS criteria:** Scannable barcode rendered; loyalty ID visible as text below barcode

---

## Test 9: RCC Batch Import

**Setup:**
```apex
RCC_Import_Record__c r1 = new RCC_Import_Record__c(
    Card_Number__c = 'TEST-CARD-001',
    Email__c = 'rcc.batch.tester@example.com',
    Member_Type__c = 'Retail',
    Status__c = 'Pending'
);
RCC_Import_Record__c r2 = new RCC_Import_Record__c(
    Card_Number__c = 'BAD-CARD-002',
    // No Email — should fail
    Member_Type__c = 'Retail',
    Status__c = 'Pending'
);
insert new List<RCC_Import_Record__c>{r1, r2};
```

**Run batch:**
```apex
Database.executeBatch(new RCCCardBatchProcessor(), 50);
```

**Verify:**
```sql
SELECT Card_Number__c, Status__c, Error_Message__c
FROM RCC_Import_Record__c
WHERE Card_Number__c IN ('TEST-CARD-001', 'BAD-CARD-002')

SELECT Batch_Type__c, Total_Processed__c, Total_Succeeded__c, Total_Failed__c
FROM Batch_Run_Log__c ORDER BY Completed_At__c DESC LIMIT 1
```
**PASS criteria:** `TEST-CARD-001` → `Enrolled`; `BAD-CARD-002` → `Failed`; Batch_Run_Log created

---

## Test 10: Privacy Deletion

**Pre-condition:** Use the enrolled test Contact from Test 2.

**Run via Execute Anonymous (simulates OneTrust webhook):**
```apex
PrivacyDeletionService svc = new PrivacyDeletionService();
svc.processPrivacyRequest('<contactId>', 'Agent', 'TEST-REQ-001');
```

**Verify:**
```sql
SELECT FirstName, LastName, Email, Phone, Has_Loyalty__c, Loyalty_Member_Id__c
FROM Contact WHERE Id = '<contactId>'

SELECT Action__c, Performed_At__c
FROM Privacy_Audit_Log__c
WHERE Privacy_Request__c IN (
    SELECT Id FROM Privacy_Request__c WHERE OneTrust_Request_Id__c = 'TEST-REQ-001'
)
ORDER BY Performed_At__c
```
**PASS criteria:**
- `FirstName = 'Deleted'`; `Email = null`; `Phone = null`
- `Has_Loyalty__c = true` (retained); `Loyalty_Member_Id__c` non-null (retained)
- 3–4 audit log entries: `Vouchers_Cancelled`, `LC_Unenrolled`, `Contact_Anonymised`, `Request_Completed`

---

## Test 11: Points Expiry (US Member, No Recent Purchase)

```apex
// Create a US Contact with loyalty but no recent purchases
Contact usContact = new Contact(
    FirstName = 'Expiry', LastName = 'TestUser',
    Email = 'expiry.test@example.com',
    Country_Code__c = 'US',
    Has_Loyalty__c = true,
    Loyalty_Member_Id__c = '<valid-lpmId>'
);
insert usContact;

PointsExpiryService svc = new PointsExpiryService();
Boolean eligible = svc.evaluateExpiryEligibility(usContact.Id);
System.debug('Eligible for expiry: ' + eligible); // Should be true if balance > 0
```

**PASS criteria:** `eligible = true` for a US member with positive balance and no recent purchases

---

## Test 12: Verify All Scheduled Jobs

After running the schedule commands from `manual-setup.md`:
1. **Setup → Scheduled Jobs**
2. Verify `Annual Points Expiry` appears with Next Run = January 1
3. Verify `Nightly RCC Import` appears with Next Run = tonight 02:00

---

## Known Issues to Watch For

| Symptom | Likely Cause | Check |
|---|---|---|
| Dashboard shows "Error loading data" | Named Credential not OAuth configured | Setup → Named Credentials |
| Points balance shows null | Org Cache partition missing | Setup → Platform Cache |
| Flows don't trigger on enrollment | Flows still inactive | Setup → Flows → Activate |
| Barcode blank | JsBarcode static resource missing | Setup → Static Resources |
| Batch runs but no Contact updated | Named Credential → LC API call failing | Check Batch_Run_Log__c.Error_Summary__c |
