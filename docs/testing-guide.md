# Testing Guide

## Apex Test Suite

Run all tests: `sf apex run test --test-level RunLocalTests --wait 10`

All 67 tests should pass. Coverage target: ≥75% on all classes.

---

## Feature Test Areas

### 1. Enrollment

**Test: New member enrollment via LWC form**
- Pre-condition: Contact exists with `Has_Loyalty__c = false`
- Action: Call `LoyaltyEnrollmentController.enrollMember(contactId, 'Retail')`
- Expected: Contact `Has_Loyalty__c = true`, `Loyalty_Member_Id__c` populated
- SOQL validation:
```sql
SELECT Has_Loyalty__c, Loyalty_Member_Id__c, Loyalty_Member_Type__c
FROM Contact WHERE Email = 'test@example.com'
```

**Test: Duplicate email check**
- Action: Call `LoyaltyEnrollmentController.checkEmailExists('existing@example.com')`
- Expected: `true` returned (no exception)

**Test: Enroll existing Contact**
- Pre-condition: Contact exists without loyalty
- Action: `LoyaltyEnrollmentController.enrollExistingContact(contactId, 'Pro')`
- Expected: Contact enrolled; `Loyalty_Member_Type__c = 'Pro'`

---

### 2. Points Balance & Session Cache

**Test: Dashboard loads member data**
- Pre-condition: Contact enrolled, `Loyalty_Member_Id__c` set
- Action: Call `LoyaltyTransactionController.getSessionLoyaltyData(contactId)`
- Expected: Returns `MemberSessionData` with `pointsBalance >= 0` and `vouchers` list

**Test: Cache invalidation**
- Action: Call `refreshLoyaltyData(contactId)` after adjusting points
- Expected: Next `getSessionLoyaltyData` call fetches fresh data from LC

SOQL (verify cache is backed by Org Cache partition):
```sql
-- No direct SOQL for Org Cache; verify via Apex in Execute Anonymous:
-- Cache.Org.contains('local.LoyaltyMemberData.LMD_<contactId>')
```

---

### 3. Points Adjustment

**Test: Credit points**
- Action: `LoyaltyTransactionController.adjustPoints(lpmId, 100, 'Credit', 'Goodwill')`
- Expected: No exception; LC returns 200
- Verify: `getSessionLoyaltyData` shows increased balance

**Test: Debit points**
- Action: `LoyaltyTransactionController.adjustPoints(lpmId, 50, 'Debit', 'Correction')`
- Expected: No exception
- Verify: Balance decreases by 50

---

### 4. Vouchers

**Test: List vouchers**
- Action: `getSessionLoyaltyData(contactId)` — check `.vouchers` field
- Expected: Returns list (may be empty for new member)

**Test: Validate voucher**
- Action: `LoyaltyVoucherService.validateVoucher(code, lpmId)`
- Expected: Returns `VoucherDTO` with `status = 'Active'`

**Test: Redeem voucher**
- Action: `CheckoutService.redeemCertificatesAtSubmission([code], lpmId)`
- Expected: No exception; voucher status changes to Redeemed
- SOQL (to verify):
```sql
-- No SFSC object for individual voucher status; validate via LC API response or mock
```

---

### 5. Transaction History

**Test: Retrieve transactions**
- Action: `LoyaltyTransactionController.getTransactionHistory(lpmId, null, null, null, 1)`
- Expected: Returns paginated list of `TransactionJournalDTO` objects

**Test: Filter by date**
- Action: Pass `startDate = '2024-01-01'`, `endDate = '2024-12-31'`
- Expected: Only transactions in date range returned

---

### 6. Promotions

**Test: Get available promotions**
- Action: `LoyaltyPromotionController.getMemberPromotions(lpmId)`
- Expected: Returns list of promotions (may be empty)

**Test: Enroll in promotion**
- Action: `LoyaltyPromotionController.enrollForPromotion(lpmId, 'DoublePointsWeekend')`
- Expected: No exception; member added to promotion in LC

---

### 7. Tier Management

**Test: Upgrade tier**
- Pre-condition: User has `Loyalty_Admin` permission set
- Action: `LoyaltyTierController.updateMemberTier(lpmId, 'Elite', 'Manual upgrade per request')`
- Expected: No exception; LC reflects new tier

**Test: TierMappingService**
- Action: `new TierMappingService().mapLegacyTier('Pro_Elite')`
- Expected: `tier = 'Elite'`, `memberType = 'Pro'`

---

### 8. Order Fulfilment Points

**Test: Points awarded on order**
- Action: Publish `Order_Fulfilment_Event__e` with valid Contact_Id, Order_Id, Cart_Lines_JSON
- Expected: `Order_Points_Status__c` record created with `Status__c = 'Awarded'`
- SOQL:
```sql
SELECT Id, Status__c, Contact__c, Order_Id__c
FROM Order_Points_Status__c
WHERE Order_Id__c = '<orderId>'
```

**Test: Exclusion rules applied**
- Action: Include a `categoryName = 'Fuel'` line in Cart_Lines_JSON
- Expected: Fuel line excluded from TJ; points calculated without that line

---

### 9. Order Cancellation

**Test: Points reversed on cancellation**
- Pre-condition: `Order_Points_Status__c` with `Status__c = 'Awarded'` exists
- Action: Publish `Order_Cancellation_Event__e` for the same order
- Expected: `Order_Points_Status__c.Status__c = 'Reversed'`
- SOQL:
```sql
SELECT Status__c FROM Order_Points_Status__c WHERE Order_Id__c = '<orderId>'
```

---

### 10. RCC Batch

**Test: Batch processes pending records**
- Pre-condition: Insert `RCC_Import_Record__c` with `Status__c = 'Pending'`, valid `Email__c` and `Card_Number__c`
- Action: `Database.executeBatch(new RCCCardBatchProcessor(), 50)`
- Expected: Record `Status__c = 'Enrolled'`; Contact `RCC_Card_Number__c` set; `Batch_Run_Log__c` created
- SOQL:
```sql
SELECT Status__c, Error_Message__c FROM RCC_Import_Record__c WHERE Card_Number__c = '<card>'
SELECT Batch_Type__c, Total_Succeeded__c FROM Batch_Run_Log__c WHERE Batch_Type__c = 'RCC_Card_Import'
```

**Test: Invalid records fail gracefully**
- Pre-condition: Insert record with no `Email__c`
- Expected: `Status__c = 'Failed'`; `Error_Message__c` populated; batch continues

---

### 11. Points Expiry

**Test: US member without recent purchase is eligible**
- Pre-condition: Contact `Country_Code__c = 'US'`, no `Order_Points_Status__c` with Status=Awarded in last year
- Action: `new PointsExpiryService().evaluateExpiryEligibility(contactId)`
- Expected: `true`

**Test: CA member is never eligible**
- Pre-condition: Contact `Country_Code__c = 'CA'`
- Action: Same as above
- Expected: `false`

**Test: Member with recent purchase is not eligible**
- Pre-condition: `Order_Points_Status__c` with `Status__c = 'Awarded'` and `CreatedDate` within last 365 days
- Expected: `false`

---

### 12. Privacy Deletion

**Test: Full deletion flow**
- Pre-condition: Contact with loyalty, no open orders on Account
- Action: POST `/services/apexrest/privacy/delete/` with valid payload
- Expected: Contact `Email = null`, `FirstName = 'Deleted'`, `Has_Loyalty__c` still true
- SOQL:
```sql
SELECT FirstName, LastName, Email, Phone, Has_Loyalty__c
FROM Contact WHERE Id = '<contactId>'

SELECT Action__c, Performed_At__c FROM Privacy_Audit_Log__c
WHERE Privacy_Request__c IN (
    SELECT Id FROM Privacy_Request__c WHERE OneTrust_Request_Id__c = '<requestId>'
)
ORDER BY Performed_At__c
```

**Test: Blocked by open order**
- Pre-condition: Contact's Account has Order with `Status = 'Processing'`
- Action: POST deletion request
- Expected: HTTP 409 response; Contact unchanged

---

### 13. Deduplication

**Test: Email match returns high-confidence result**
- Action: `new DeduplicationService().findBestMatch('known@example.com', null, null)`
- Expected: `MatchResult.score = 50`, `isHighConfidence = true`

**Test: Phone-only match returns medium confidence**
- Action: `findBestMatch(null, '+15551234567', null)`
- Expected: `score = 30`, `isHighConfidence = false`

---

## Batch Run Log Validation

After any batch completes:
```sql
SELECT Batch_Type__c, Total_Processed__c, Total_Succeeded__c, Total_Failed__c,
       Completed_At__c, Error_Summary__c
FROM Batch_Run_Log__c
ORDER BY Completed_At__c DESC
LIMIT 10
```
