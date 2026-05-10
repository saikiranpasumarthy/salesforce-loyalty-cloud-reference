# Sequence Diagrams

## 1. Enrollment Flow

```
Agent (LWC)          loyaltyEnrollmentForm    LoyaltyEnrollmentController    ContactMatchService    DeduplicationService    LoyaltyEnrollmentService    LoyaltyAPIClient    LC API
     │                        │                           │                           │                       │                         │                      │              │
     │──── onEmailBlur ───────►│                          │                           │                       │                         │                      │              │
     │                        │──checkDuplicate()─────────►│                          │                       │                         │                      │              │
     │                        │                           │──findMatch(email)──────────►│                     │                         │                      │              │
     │                        │                           │                           │──SOQL (email/phone/   │                         │                      │              │
     │                        │                           │                           │  loyaltyId/epsilon)   │                         │                      │              │
     │                        │                           │                           │◄──Contact | null──────│                         │                      │              │
     │                        │◄──{isDuplicate, score}────│                           │                       │                         │                      │              │
     │◄── render warning ─────│                          │                           │                       │                         │                      │              │
     │                        │                           │                           │                       │                         │                      │              │
     │──── handleEnroll() ────►│                          │                           │                       │                         │                      │              │
     │                        │──enrollExistingContact()──►│                          │                       │                         │                      │              │
     │                        │                           │──EnrollmentRequest.       │                       │                         │                      │              │
     │                        │                           │  validate()               │                       │                         │                      │              │
     │                        │                           │──scoreMatch()─────────────────────────────────────►│                        │                      │              │
     │                        │                           │                           │                       │──return MatchResult──────►│                   │              │
     │                        │                           │──enroll()─────────────────────────────────────────────────────────────────────►│                 │              │
     │                        │                           │                           │                       │                         │──POST /members──────►│            │
     │                        │                           │                           │                       │                         │                      │─────────────►
     │                        │                           │                           │                       │                         │                      │◄────200─────│
     │                        │                           │                           │                       │                         │◄──memberId────────────│              │
     │                        │                           │                           │                       │──EventBus.publish()────►│                      │              │
     │                        │                           │                           │                       │  (Loyalty_Enrollment_    │                      │              │
     │                        │                           │                           │                       │   Event__e)             │                      │              │
     │                        │                           │                           │                       │                         │──upsert Contact──────►[SFDB]       │
     │                        │◄──EnrollmentResponse.ok───│                           │                       │                         │                      │              │
     │◄── dispatch 'enrolled'─│                          │                           │                       │                         │                      │              │
```

---

## 2. Order Fulfilment → Points Accrual

```
Order System         Platform Event Bus        OrderFulfilmentEventHandler     LoyaltyTransactionService    LoyaltyCartEvaluationService    LoyaltyAPIClient    LC API
     │                        │                           │                           │                               │                           │              │
     │──publish               │                           │                           │                               │                           │              │
     │  Order_Fulfilment_     │                           │                           │                               │                           │              │
     │  Event__e──────────────►│                          │                           │                               │                           │              │
     │                        │──trigger(events[])────────►│                          │                               │                           │              │
     │                        │                           │──for each event:          │                               │                           │              │
     │                        │                           │  accruePoints()───────────►│                             │                           │              │
     │                        │                           │                           │──getExclusionRules()──────────►│                          │              │
     │                        │                           │                           │                               │──CMDT query (lazy)        │              │
     │                        │                           │                           │◄──Map<type,Set<value>>────────│                           │              │
     │                        │                           │                           │──filter excluded lines        │                           │              │
     │                        │                           │                           │──buildTxnBody()               │                           │              │
     │                        │                           │                           │──post()───────────────────────────────────────────────────►│            │
     │                        │                           │                           │                               │                           │─────────────►
     │                        │                           │                           │                               │                           │◄────200─────│
     │                        │                           │──upsert Order_Points_     │                               │                           │              │
     │                        │                           │  Status__c (Status=Awarded│                               │                           │              │
```

---

## 3. Multi-Voucher Checkout

```
POS Terminal       CheckoutController        CheckoutService           LoyaltyVoucherService      LoyaltyAPIClient    LC API
     │                    │                        │                          │                          │              │
     │──POST checkout─────►│                       │                          │                          │              │
     │                    │──processCheckout()─────►│                         │                          │              │
     │                    │                        │──validateAll():           │                          │              │
     │                    │                        │  for each voucherId:      │                          │              │
     │                    │                        │──validateVoucher()────────►│                        │              │
     │                    │                        │                          │──GET /vouchers/{id}───────►│            │
     │                    │                        │                          │                          │──────────────►
     │                    │                        │                          │◄────VoucherDTO────────────│              │
     │                    │                        │◄──validated (or throw)────│                         │              │
     │                    │                        │                           │                          │              │
     │                    │                        │── ALL validated ──────────┤                          │              │
     │                    │                        │──redeemAll():             │                          │              │
     │                    │                        │  for each voucherId:      │                          │              │
     │                    │                        │──redeemVoucher()──────────►│                        │              │
     │                    │                        │                          │──POST /vouchers/{id}/redeem►│           │
     │                    │                        │                          │                          │──────────────►
     │                    │                        │                          │◄────200───────────────────│              │
     │                    │◄──{success, redeemed}──│                         │                          │              │
     │◄──checkout result──│                       │                          │                          │              │
```

---

## 4. Privacy Deletion (4-Gate Workflow)

```
OneTrust          PrivacyDeletionAPIController    PrivacyDeletionService       LoyaltyVoucherService    LoyaltyEnrollmentService    SFDB
     │                        │                           │                           │                         │                    │
     │──POST /privacy/delete──►│                          │                           │                         │                    │
     │                        │──processRequest()─────────►│                          │                         │                    │
     │                        │                           │── Gate 1: Open Orders     │                         │                    │
     │                        │                           │──SOQL (Order, open        │                         │                    │
     │                        │                           │  statuses)───────────────────────────────────────────────────────────────►│
     │                        │                           │◄──0 open orders──────────────────────────────────────────────────────────│
     │                        │                           │                           │                         │                    │
     │                        │                           │── Gate 2: Cancel Vouchers │                         │                    │
     │                        │                           │──cancelAllVouchers()───────►│                       │                    │
     │                        │                           │                           │──for each active        │                    │
     │                        │                           │                           │  voucher: cancel()     │                    │
     │                        │                           │                           │──(errors swallowed)     │                    │
     │                        │                           │                           │                         │                    │
     │                        │                           │── Gate 3: LC Unenroll    │                         │                    │
     │                        │                           │──unenrollFromLC()─────────────────────────────────────►│                │
     │                        │                           │                           │                         │──DELETE /members  │
     │                        │                           │                           │                         │◄────200───────────│
     │                        │                           │                           │                         │                    │
     │                        │                           │── Gate 4: Anonymise       │                         │                    │
     │                        │                           │──anonymiseContact()───────────────────────────────────────────────────────►│
     │                        │                           │  FirstName='Deleted'      │                         │                    │
     │                        │                           │  LastName='User {last4}'  │                         │                    │
     │                        │                           │  Email/Phone=null         │                         │                    │
     │                        │                           │◄──Contact updated─────────────────────────────────────────────────────────│
     │                        │◄──{status:completed}──────│                          │                         │                    │
     │◄──HTTP 200─────────────│                          │                           │                         │                    │
```

---

## 5. Session Cache Read Path

```
LWC (loyaltyMemberDashboard)    loyaltyDataService (JS module)    LoyaltyLoginController    LoyaltySessionCacheService    LoyaltyAPIClient    LC API
              │                           │                               │                           │                        │              │
              │──getLoyaltyData(contactId)►│                              │                           │                        │              │
              │                           │──check module Map (TTL 30min) │                           │                        │              │
              │                           │── MISS ──────────────────────►│                          │                        │              │
              │                           │                               │──getFromCache(key)─────────►│                     │              │
              │                           │                               │                           │──Cache.get()          │              │
              │                           │                               │                           │── HIT ────────────────►│             │
              │                           │◄──MemberSessionData (cached)──│                          │                        │              │
              │◄──data────────────────────│                              │                           │                        │              │
              │                           │──store in module Map          │                           │                        │              │
              │                           │                               │                           │                        │              │
              │                           │── (on cache MISS):            │                           │                        │              │
              │                           │                               │──call LC API──────────────────────────────────────►│            │
              │                           │                               │                           │                        │──GET /members►│
              │                           │                               │                           │                        │◄─────────────│
              │                           │                               │──put(key, data, ttl:1800)──►│                      │              │
              │                           │◄──MemberSessionData (live)────│                          │                        │              │
```

---

## 6. RCC Batch Processing

```
Scheduler              RCCCardBatchProcessor         RCCRecordParser    ContactMatchService    LoyaltyEnrollmentService    SFDB
     │                         │                           │                    │                        │                   │
     │──execute()──────────────►│                          │                    │                        │                   │
     │                         │── start():                │                    │                        │                   │
     │                         │──SOQL RCC_Import_Record   │                    │                        │                   │
     │                         │  WHERE Status='Pending'───────────────────────────────────────────────────────────────────────►│
     │                         │◄──scope records───────────────────────────────────────────────────────────────────────────────│
     │                         │                           │                    │                        │                   │
     │                         │── execute(scope):         │                    │                        │                   │
     │                         │──parse(csvRow)────────────►│                   │                        │                   │
     │                         │◄──Map<field,value>─────────│                  │                        │                   │
     │                         │──findMatch(email/phone)────────────────────────►│                      │                   │
     │                         │◄──Contact | null──────────────────────────────│                        │                   │
     │                         │  if matched: set Status='Matched'              │                        │                   │
     │                         │──enroll(contact, memberType)──────────────────────────────────────────►│                  │
     │                         │◄──EnrollmentResponse─────────────────────────────────────────────────│                   │
     │                         │  update RCC_Import_Record Status='Enrolled'    │                        │                   │
     │                         │──upsert records────────────────────────────────────────────────────────────────────────────►│
     │                         │                           │                    │                        │                   │
     │                         │── finish():               │                    │                        │                   │
     │                         │──insert Batch_Run_Log__c──────────────────────────────────────────────────────────────────►│
     │                         │──send email (success/failure summary)         │                        │                   │
```
