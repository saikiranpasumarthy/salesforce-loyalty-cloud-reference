# Execution Flow — Full Technical Chains

Numbered steps showing exact classes, methods, and objects involved for each operation.

---

## 1. New Member Enrollment

```
User clicks "Enroll" in loyaltyJoinCta
  1. LWC: loyaltyJoinCta.handleEnroll()
  2. @AuraEnabled: LoyaltyEnrollmentController.enrollMember(contactId, memberType)
  3. Query: Contact WHERE Id = :contactId (fetch email, phone, name, etc.)
  4. LoyaltyEnrollmentService.buildEnrollmentRequest(contact, memberType)
     → EnrollmentRequest DTO constructed
  5. LoyaltyEnrollmentService.enrollNewMember(req)
  6. LoyaltyAPIClient.post('/members', payload)
     → LoyaltyAPIClient.getConfig()
       → SOQL: Loyalty_Program_Config__mdt WHERE DeveloperName = 'Default'
     → Named Credential: callout:Loyalty_Cloud_API/connect/loyalty/programs/LevelUp/members
     → HttpRequest.send() → HTTP 201
  7. EnrollmentResponse.ok(responseBody)
     → Id.valueOf(lpmId) — validates 18-char SF ID from response
     → Returns EnrollmentResponse{lpmId, status}
  8. DML: update Contact SET Has_Loyalty__c=true, Loyalty_Member_Id__c=lpmId, Loyalty_Member_Type__c=type
  9. EventBus.publish(new Loyalty_Enrollment_Event__e(Contact_Id__c=contactId, LPM_Id__c=lpmId))
  10. Platform Event → Welcome_Email_Trigger_Flow activates
  11. LWC: toast "Enrollment successful"; fireEvent('refreshView')
```

---

## 2. Member Dashboard Load (Cache Miss)

```
Agent opens Contact record with Has_Loyalty__c=true
  1. LWC: loyaltyMemberDashboard.connectedCallback()
  2. Import: loyaltyDataService.getLoyaltyData(lpmId)
     → Check in-memory Map[lpmId] — key absent or TTL expired
  3. @AuraEnabled: LoyaltyTransactionController.getSessionLoyaltyData(contactId)
  4. Query: Contact WHERE Id = :contactId → get Loyalty_Member_Id__c
  5. LoyaltySessionCacheService.getMemberData(lpmId)
     → Check Cache.Org.get('local.LoyaltyMemberData.LMD_' + contactId)
     → Cache miss
  6. LoyaltyMemberService.getRewardsPoints(lpmId)
     → LoyaltyAPIClient.get('/member-benefits?memberId=' + lpmId)
     → Named Credential: GET /connect/loyalty/programs/LevelUp/member-benefits
     → Returns MemberBenefitsResponse{pointsBalance, tier, currency}
  7. LoyaltyVoucherService.getMemberVouchers(lpmId)
     → LoyaltyAPIClient.get('/member-vouchers?memberId=' + lpmId)
     → Returns List<VoucherDTO>
  8. MemberSessionData assembled: {pointsBalance, tier, vouchers, lastRefreshed}
  9. Cache.Org.put('local.LoyaltyMemberData.LMD_' + contactId, data, 1800) // TTL 30 min
  10. loyaltyDataService stores in in-memory Map[lpmId] with timestamp
  11. LWC renders: balance, tier badge, voucher count, recent transactions preview
```

---

## 3. Points Adjustment (Credit)

```
Agent enters amount=100, type=Credit, reason="Goodwill" in loyaltyPointsAdjustment
  1. LWC: loyaltyPointsAdjustment.handleConfirm()
  2. @AuraEnabled: LoyaltyTransactionController.adjustPoints(lpmId, 100, 'Credit', 'Goodwill')
  3. Routes to: LoyaltyTransactionService.creditPoints(lpmId, 100, 'USD', 'Goodwill')
     → LoyaltyAPIClient.post('/program-processes/Credit%20Points',
         {memberId: lpmId, points: 100, currency: 'USD', reason: 'Goodwill'})
     → Named Credential: POST /connect/loyalty/programs/LevelUp/program-processes/Credit%20Points
     → HTTP 200 response
  4. loyaltyDataService.clearLoyaltyCache(lpmId) — invalidate stale balance
  5. LWC: toast "100 points credited"; dashboard refreshes
```

---

## 4. Order Fulfilment Points Earning

```
OMS completes order → publishes Order_Fulfilment_Event__e
  1. Platform event trigger fires → OrderFulfilmentEventHandler.handleEvents(List<SObject>)
  2. For each event:
     a. Query: Contact WHERE Id = :event.Contact_Id__c → get Loyalty_Member_Id__c
     b. CheckoutService.buildFulfilmentPayload(event)
        → JSON.deserialize(event.Cart_Lines_JSON__c) → List<CartLineItem>
        → LoyaltyCartEvaluationService.getExclusionRules()
          → SOQL: Loyalty_Exclusion_Rule__mdt WHERE Is_Active__c = true
        → Filter excluded categories (Fuel, Gift Cards, Tobacco, Generic Brand)
     c. TransactionJournalDTO assembled:
        {lpmId, journalType='Purchase', activityDate, lineItems (filtered), tenderId}
     d. LoyaltyTransactionService.executeTransaction(dto)
        → LoyaltyAPIClient.post('/transaction-journals/bulk', dto)
        → Named Credential: POST /connect/loyalty/programs/LevelUp/transaction-journals/bulk
        → HTTP 200 → {transactionJournalId, totalPointsAwarded}
  3. DML: upsert Order_Points_Status__c {Contact__c, Order_Id__c, Status__c='Awarded', Points_Awarded__c}
```

---

## 5. Cart Points Simulation (Preview)

```
Customer views checkout summary
  1. Checkout page calls LoyaltyCartEvaluationService.evaluateCart(req)
  2. LoyaltyCartEvaluationService.applyExclusionRules(req.lineItems)
     → getExclusionRules() → SOQL: Loyalty_Exclusion_Rule__mdt
     → Filter excluded lines; set isExcluded=true on excluded items
  3. buildSimulationDTO(lpmId, eligibleLines, tenderId)
     → SOQL: Loyalty_Program_Config__mdt WHERE DeveloperName='Default' → get Currency_ISO_Code__c
     → TransactionJournalDTO{lpmId, journalType='Purchase', lineItems=eligible}
  4. LoyaltyTransactionService.simulateTransaction(dto)
     → LoyaltyAPIClient.post('/transaction-journals/bulk?simulate=true', dto)
     → HTTP 200 → {transactionJournals: [{totalPointsAwarded, bonusPoints}]}
  5. CartEvaluationResponse{estimatedPoints, bonusPoints} returned to checkout UI
```

---

## 6. Voucher Redemption at Checkout

```
Customer applies voucher codes at checkout
  1. CheckoutService.redeemCertificatesAtSubmission(['CODE1','CODE2'], lpmId)
  2. Phase 1 — validate all:
     For each code:
       a. LoyaltyVoucherService.validateVoucher(code, lpmId)
          → LoyaltyAPIClient.post('/program-processes/Validate%20Voucher', {voucherCode, memberId})
          → HTTP 200 or 4xx (throws LoyaltyVoucherException on failure)
  3. If any validation fails → throw LoyaltyVoucherException; abort; no redemptions occur
  4. Phase 2 — redeem all:
     For each code:
       a. LoyaltyVoucherService.redeemVoucher(code, lpmId)
          → LoyaltyAPIClient.post('/program-processes/Redeem%20Voucher', {voucherCode, memberId})
          → HTTP 200 → discount applied
```

---

## 7. Order Cancellation / Reversal

```
OMS cancels order → publishes Order_Cancellation_Event__e
  1. Platform event trigger fires → OrderCancellationEventHandler.handleEvents(List<SObject>)
  2. For each event:
     a. Parse Voucher_Codes__c → List<String> codes
     b. For each voucher code:
        LoyaltyVoucherService.cancelVoucher(code, 'ORDER_CANCELLATION')
        → POST /program-processes/Cancel%20Voucher
     c. Query Order_Points_Status__c WHERE Order_Id__c = event.Order_Id__c AND Status__c='Awarded'
     d. LoyaltyTransactionService.debitPoints(lpmId, pointsAwarded, currency, 'CANCELLATION:<orderId>')
        → POST /program-processes/Debit%20Points
  3. DML: update Order_Points_Status__c SET Status__c = 'Reversed'
```

---

## 8. Annual Points Expiry Batch

```
PointsExpiryScheduler.execute() [January 1, 00:00]
  1. Database.executeBatch(new PointsExpiryBatch(), 200)
  2. PointsExpiryBatch.start():
     → SOQL: Contact WHERE Country_Code__c='US' AND Has_Loyalty__c=true AND Loyalty_Member_Id__c != null
  3. PointsExpiryBatch.execute(scope):
     For each Contact:
       a. PointsExpiryService.evaluateExpiryEligibility(contactId)
          → isCAMember() → SOQL: Contact WHERE Id=:id → check Country_Code__c='CA'
          → getLastQualifyingPurchaseDate(lpmId)
            → SOQL: Order_Points_Status__c WHERE Contact__c IN (...) AND Status__c='Awarded' ORDER BY CreatedDate DESC LIMIT 1
          → If last purchase within 365 days → return false (skip)
          → LoyaltyMemberService.getRewardsPoints(lpmId) → GET /member-benefits → check balance > 0
       b. If eligible: PointsExpiryService.processExpiry(contactId)
          → getRewardsPoints(lpmId) → get current balance
          → SOQL: Loyalty_Program_Config__mdt → get Currency_ISO_Code__c
          → LoyaltyTransactionService.debitPoints(lpmId, balance, 'USD', 'ANNUAL_EXPIRY:2025')
             → POST /program-processes/Debit%20Points
  4. PointsExpiryBatch.finish():
     → DML: insert Batch_Run_Log__c{Batch_Type__c='PointsExpiryBatch', ...stats}
```

---

## 9. RCC Card Batch Import

```
RCCBatchScheduler.execute() [nightly 02:00]
  1. Database.executeBatch(new RCCCardBatchProcessor(), 50)
  2. RCCCardBatchProcessor.start():
     → SOQL: RCC_Import_Record__c WHERE Status__c='Pending' ORDER BY CreatedDate ASC
  3. RCCCardBatchProcessor.execute(scope):
     For each record:
       a. RCCRecordParser.validateRecord(rec) → checks card number + email present
       b. If invalid: markFailed(rec) → Status='Failed'; continue
       c. ExternalProfileDTO{email, rccCardNumber, sourceSystem='RCC_BATCH'}
       d. ContactMatchService.matchOrCreateContact(dto)
          → findBestMatch(dto) → SOQL: Contact WHERE Email=:email OR RCC_Card_Number__c=:card LIMIT 1
          → If found: updateContactFields(matched, dto) — update only if fields changed
          → If changed: DML update Contact
          → If not found: createContact(dto) → DML insert Contact
       e. SOQL: Contact WHERE Id=:contactId → check Has_Loyalty__c
       f. If not enrolled:
          LoyaltyEnrollmentService.enrollNewMember(req)
          → POST /connect/loyalty/programs/LevelUp/members
       g. DML (batched): Contact{RCC_Active__c=true, RCC_Card_Number__c}
       h. markProcessed(rec) → Status='Enrolled'
     After loop: DML update contacts; DML update records (single bulk DML each)
  4. RCCCardBatchProcessor.finish():
     → DML: insert Batch_Run_Log__c{Batch_Type__c='RCC_Card_Import', ...stats}
     → Messaging.sendEmail to loyalty-ops@company.com
```

---

## 10. Privacy Deletion (GDPR)

```
OneTrust sends POST /services/apexrest/privacy/delete/
  1. PrivacyDeletionAPIController.doDelete()
     → Parse body: {contactId, requestId, requestType}
     → Validate fields (400 if missing)
  2. PrivacyDeletionService.processPrivacyRequest(contactId, 'OneTrust', requestId)
  3. Gate 1:
     → SOQL: Order WHERE AccountId IN (SELECT AccountId FROM Contact WHERE Id=:contactId)
               AND Status NOT IN ('Delivered','Cancelled','Failed')
     → If any open orders → throw LoyaltyAPIException(409)
  4. SOQL: Contact WHERE Id=:contactId → get Has_Loyalty__c, Loyalty_Member_Id__c
  5. PHASE 1 — Callouts only (no DML):
     a. handleUnredeemedVouchers(lpmId)
        → LoyaltyVoucherService.getMemberVouchers(lpmId) → GET /member-vouchers
        → For each active voucher: cancelVoucher(code, 'PRIVACY_REQUEST') → POST /Cancel%20Voucher
     b. unenrollFromLoyalty(lpmId, 'PRIVACY_REQUEST')
        → LoyaltyMemberService.unenrollMember(lpmId) → POST /Unenroll%20Member
  6. PHASE 2 — DML only (all callouts done):
     a. deactivateContact(Id.valueOf(contactId))
        → DML update Contact{FirstName='Deleted', LastName='User <last4>', Email=null, Phone=null, ...all PII=null}
     b. ensurePrivacyRequest(contactId, requestId)
        → SOQL: Privacy_Request__c WHERE OneTrust_Request_Id__c=:requestId LIMIT 1
        → If not found: DML insert Privacy_Request__c{Contact__c, requestId, Status='In_Progress', Type='Erasure'}
        → Returns Privacy_Request__c.Id
     c. PrivacyAuditLogger.log(contactId, 'Vouchers_Cancelled', ..., privacyRequestSfId) → DML insert Privacy_Audit_Log__c
     d. PrivacyAuditLogger.log(contactId, 'LC_Unenrolled', ..., privacyRequestSfId) → DML insert
     e. PrivacyAuditLogger.log(contactId, 'Contact_Anonymised', ..., privacyRequestSfId) → DML insert
     f. DML insert Privacy_Audit_Log__c{Action='Request_Completed', Detail='...Systems: SFSC;LoyaltyCloud'}
  7. HTTP 200 → {status:'SUCCESS', systemsUpdated:['LoyaltyCloud','SFSC'], timestamp}
```

---

## 11. POS Loyalty Lookup

```
POS terminal sends POST /services/apexrest/loyalty/lookup
  1. LoyaltyLookupController.doLookup()
     → Parse body: {email?, phone?, loyaltyId?, cardNumber?}
  2. DeduplicationService.findBestMatch(email, phone, loyaltyId)
     → SOQL: Contact WHERE Email=:email OR Phone=:phone OR Loyalty_Member_Id__c=:loyaltyId LIMIT 10
     → scoreCandidate() for each → email=50pts, loyaltyId=40pts, phone=30pts
     → Return best match with score ≥ 30
  3. LoyaltyCompositeAPIController.getMemberData(contactId)
     → LoyaltyMemberService.getMemberProfile(lpmId) → GET /members/{lpmId}
     → LoyaltyMemberService.getRewardsPoints(lpmId) → GET /member-benefits
     → LoyaltyVoucherService.getMemberVouchers(lpmId) → GET /member-vouchers
  4. MemberCompositeResponse assembled and returned
```
