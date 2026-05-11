# User Journeys

## 1. Enrollment — New Member (Online / LWC Form)

1. Agent opens Contact record → sees `loyaltyJoinCta` (visible only when `Has_Loyalty__c = false`)
2. Agent clicks "Enroll" → `loyaltyEnrollmentForm` opens (standalone or on Contact page)
3. Agent selects Member Type: Retail / Pro / Student
4. LWC calls `LoyaltyEnrollmentController.checkEmailExists(email)` → checks for duplicate
5. LWC calls `LoyaltyEnrollmentController.enrollMember(contactId, memberType)`
6. Controller → `LoyaltyEnrollmentService.enrollNewMember(req)` → POST `/connect/loyalty/programs/LevelUp/members`
7. LC returns `{id: <lpmId>, status: ACTIVE}` → `EnrollmentResponse.ok()` stores lpmId
8. Contact updated: `Has_Loyalty__c = true`, `Loyalty_Member_Id__c = <lpmId>`, `Loyalty_Member_Type__c = <type>`
9. Platform event `Loyalty_Enrollment_Event__e` published
10. `Welcome_Email_Trigger_Flow` fires → sends welcome email via SFMC
11. `loyaltyJoinCta` hides; `loyaltyMemberDashboard` becomes visible

**Error paths:**
- Duplicate email → `checkEmailExists` returns true → LWC shows "Member already exists" inline
- LC API 4xx → `LoyaltyEnrollmentException` → AuraHandledException shown in toast

---

## 2. Enrollment — Existing Contact (enrollExistingContact)

1. Contact already exists in SFSC but not in LC
2. Agent calls `LoyaltyEnrollmentController.enrollExistingContact(contactId, memberType)`
3. `ContactMatchService.matchOrCreateContact(dto)` → finds existing Contact (no new Contact created)
4. If Contact fields changed (phone/email/country), Contact updated; otherwise no DML
5. `LoyaltyEnrollmentService.enrollNewMember(req)` → LC API call → LPM created
6. Contact fields updated as in Journey 1

---

## 3. Enrollment — RCC Card Batch Import

1. External RCC card provider drops records into `RCC_Import_Record__c` with `Status__c = 'Pending'`
2. `RCCBatchScheduler` fires nightly at 02:00 → triggers `RCCCardBatchProcessor`
3. Batch queries all Pending records; for each:
   - `RCCRecordParser.validateRecord(rec)` → checks card number + email present
   - `ContactMatchService.matchOrCreateContact(dto)` → find/create Contact by email
   - If Contact not yet in LC: `enrollSvc.enrollNewMember(req)` with Retail or Pro type
   - Contact updated: `RCC_Active__c = true`, `RCC_Card_Number__c = <card>`
   - Record status → `Enrolled`
4. Invalid records (no email) → status `Failed` with error message
5. `finish()` inserts `Batch_Run_Log__c` record; sends summary email to `loyalty-ops@company.com`

---

## 4. Points Earning — Order Fulfilment

1. OMS completes order → publishes `Order_Fulfilment_Event__e`:
   - Fields: `Contact_Id__c`, `Order_Id__c`, `Order_Total__c`, `Cart_Lines_JSON__c`, `Tender_Type__c`
2. `OrderFulfilmentEventHandler` trigger fires
3. Contact's `Loyalty_Member_Id__c` retrieved
4. `CheckoutService.buildFulfilmentPayload()` parses `Cart_Lines_JSON__c`; applies `Loyalty_Exclusion_Rule__mdt` — items in Fuel/Gift Cards/Tobacco/Generic Brand categories are excluded
5. `LoyaltyTransactionService.executeTransaction(dto)` → POST `/connect/loyalty/programs/LevelUp/transaction-journals/bulk`
6. LC returns TJ Id + points awarded
7. `Order_Points_Status__c` record created/updated → `Status__c = 'Awarded'`

**Exclusion rules (loaded from CMDT):** Fuel, Gift Cards, Tobacco, Generic Brand

---

## 5. Points Earning — Cart Preview (Simulation)

1. Member views checkout summary page
2. LWC/checkout page calls `LoyaltyCartEvaluationService.evaluateCart(req)`
3. Service applies exclusion rules → calls `LoyaltyTransactionService.simulateTransaction(dto)` → POST `/transaction-journals/bulk` (read-only, no LC record created)
4. Returns `CartEvaluationResponse.estimatedPoints` + `bonusPoints`
5. UI shows "You'll earn X points" preview

---

## 6. Points Expiry — Annual Batch

1. `PointsExpiryScheduler` fires January 1 annually → triggers `PointsExpiryBatch`
2. Batch queries all US Contacts (`Country_Code__c = 'US'`) with active LPMs
3. For each member, `PointsExpiryService.evaluateExpiryEligibility(contactId)`:
   - CA members → skipped (never expire)
   - Last qualifying purchase within 365 days → skipped
   - Balance = 0 → skipped
4. Eligible members: `processExpiry(contactId)` → `LoyaltyTransactionService.debitPoints(lpmId, balance, 'USD', 'ANNUAL_EXPIRY:2025')`
5. `finish()` → `Batch_Run_Log__c` inserted with `Batch_Type__c = 'PointsExpiryBatch'`

---

## 7. Voucher Redemption — Checkout

1. Member applies voucher code at checkout
2. `CheckoutService.redeemCertificatesAtSubmission(codes, lpmId)`:
   - Phase 1 (validate all): `LoyaltyVoucherService.validateVoucher(code, lpmId)` for each code
   - If any validation fails → throw, abort redemption
   - Phase 2 (redeem all): `LoyaltyVoucherService.redeemVoucher(code, lpmId)` for each code
3. POST `/connect/loyalty/programs/LevelUp/program-processes/Redeem%20Voucher`
4. Discount applied to order total

**Partial failure handling:** If validate-all passes but redeem fails mid-way, the caller must handle reversal. No automatic rollback in this implementation.

---

## 8. Order Cancellation / Points Reversal

1. OMS cancels order → publishes `Order_Cancellation_Event__e`:
   - Fields: `Contact_Id__c`, `Order_Id__c`, `Voucher_Codes__c`
2. `OrderCancellationEventHandler` trigger fires
3. Voucher codes parsed from `Voucher_Codes__c`; each cancelled via `LoyaltyVoucherService.cancelVoucher(code, 'ORDER_CANCELLATION')`
4. Points debited via `LoyaltyTransactionService.debitPoints(lpmId, pointsAwarded, currency, 'CANCELLATION:<orderId>')`
5. `Order_Points_Status__c` record status → `Reversed`

---

## 9. Tier Upgrade

1. Admin/agent opens Contact record → `loyaltyTierManagement` LWC (admin-only)
2. Agent selects new tier (Preferred / Elite) + enters reason
3. LWC calls `LoyaltyTierController.updateMemberTier(lpmId, tier, reason)`
4. → `LoyaltyMemberService.updateMemberTier(lpmId, tier, reason)` → POST `/program-processes/Update%20Member%20Tier`
5. LC updates member tier; no SFSC Contact field update in this flow (tier is owned by LC)

**Tier mapping:** Legacy codes (Upper, Base, Conversion, Pro_Elite, etc.) → Canonical tier (Preferred/Elite) + MemberType (Retail/Pro/Student) via `Tier_Mapping__mdt`

---

## 10. Promotion Enrollment / Opt-Out

1. Agent opens Contact record → `loyaltyPromoEnrollment` LWC
2. LWC calls `LoyaltyPromotionController.getMemberPromotions(lpmId)` → GET `/member-promotions`
3. Available promotions listed; agent clicks "Enroll"
4. → `LoyaltyPromotionController.enrollForPromotion(lpmId, promotionName)` → POST `/program-processes/Enroll%20Promotions`
5. For opt-out: → `LoyaltyPromotionController.optOutFromPromotion(lpmId, promotionName)` → POST `/program-processes/Opt%20Out%20Promotion`

---

## 11. Privacy Deletion (GDPR/CCPA)

**Trigger:** OneTrust webhook or agent action

1. POST `/services/apexrest/privacy/delete/` with `{contactId, requestId, requestType: 'DELETION'}`
2. `PrivacyDeletionAPIController.doDelete()` → `PrivacyDeletionService.processPrivacyRequest()`
3. **Gate 1:** Check for in-progress orders on Contact's Account → 409 if any exist
4. **Phase 1 — Callouts only:**
   - Gate 2: `handleUnredeemedVouchers(lpmId)` → cancel all active vouchers via LC API
   - Gate 3: `unenrollFromLoyalty(lpmId, 'PRIVACY_REQUEST')` → POST `/program-processes/Unenroll%20Member`
5. **Phase 2 — DML only:**
   - Gate 4: `deactivateContact(contactId)` → clears all PII fields; sets `FirstName = 'Deleted'`, `LastName = 'User <last4>'`
   - `ensurePrivacyRequest(contactId, requestId)` → creates `Privacy_Request__c` master record
   - Audit logs inserted into `Privacy_Audit_Log__c` for each step
   - Final summary log with `Action__c = 'Request_Completed'`
6. Response: `{status: SUCCESS, systemsUpdated: ['LoyaltyCloud', 'SFSC']}`

**Fields retained:** `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `Country_Code__c`, `Privacy_Deletion_Date__c`
**Fields cleared:** Email, Phone, MailingStreet, MailingCity, MailingPostalCode, DOB_Month, DOB_Day, Pro_License_Number, School_Name, RCC_Card_Number, Epsilon_Profile_Id

---

## 12. POS / Xstore Lookup

1. POS terminal calls POST `/services/apexrest/loyalty/lookup`
2. Request body: `{email?, phone?, loyaltyId?, cardNumber?}`
3. `LoyaltyLookupController` finds Contact by any identifier → returns composite member data
4. LC API called for live balance + vouchers via `LoyaltyCompositeAPIController`

---

## 13. Member Dashboard View (Service Cloud Agent)

1. Agent opens Contact record
2. `loyaltyMemberDashboard` LWC loads → calls `LoyaltySessionCacheService.getMemberData(lpmId)`
3. Cache miss: LC API called for benefits + vouchers; result stored in Org Cache partition `local.LoyaltyMemberData` with 30-min TTL
4. Dashboard displays: points balance, tier, active vouchers, recent transactions
5. Agent can trigger manual points adjustment via embedded `loyaltyPointsAdjustment` sub-component
6. Agent can refresh data → `LoyaltyTransactionController.refreshLoyaltyData()` → clears cache
