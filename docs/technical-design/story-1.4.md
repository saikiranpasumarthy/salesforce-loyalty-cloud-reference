# STORY-1.4 / 1.5 / 1.6 — RCC Card Batch Import (Retail, Pro, Cancellation)

**RICEF IDs:** 1.4 (Retail RCC), 1.5 (Pro RCC / BSG), 1.6 (RCC Cancellation) | **Type:** Services | **Module:** SFSC, LC

## Business Purpose
Nightly batch processes inbound Bread Financial RCC card file: matches/creates SFSC Contacts, creates/links LPMs, activates RCC bonus earn attributes, and handles cancellations/inactive cards.

## Assumptions
- RCC staging records (`RCC_Import_Record__c`) are pre-loaded into SFSC before batch runs (by upstream ETL/integration)
- Batch processes all records with `Status__c = 'Pending'`
- `Member_Type__c = 'Pro'` on the staging record triggers Pro enrollment (story 1.5)
- `Card_Number__c` status values `'Inactive'` or `'Cancelled'` in the raw file map to `Status__c = 'Failed'` after processing — RCC deactivation sets `Contact.RCC_Active__c = false` (story 1.6)
- Batch size = 50 (configurable); each chunk makes ≤50 LC API calls
- Email is the primary match key; batch records without email are marked Failed
- Completion email sent to `loyalty-ops@company.com` (hardcoded)

## User Flow
1. Bread Financial file delivered to SFSC (nightly ETL) → `RCC_Import_Record__c` rows inserted with `Status__c = 'Pending'`
2. `RCCBatchScheduler` fires at 02:00 → `Database.executeBatch(new RCCCardBatchProcessor(), 50)`
3. For each pending record:
   - Validate: card number + email present; status is valid enum
   - Match or create Contact by email via `ContactMatchService`
   - If Contact not yet in LC → enroll via LC API
   - Update Contact: `RCC_Card_Number__c`, `RCC_Active__c`
   - Mark staging record `Enrolled` or `Failed`
4. `finish()` inserts `Batch_Run_Log__c`, sends summary email to ops team
5. `RCC_LPM_Attribute_Update_Flow` fires on Contact save (if `Has_Loyalty__c` or `Loyalty_Member_Type__c` changed) → calls `syncMemberAttributes` → refreshes Platform Cache for that Contact

## Components

**LWC:** None (batch process — no UI)

**Apex:**
| Class | Method | Description |
|---|---|---|
| `RCCCardBatchProcessor` | `start()` | `Database.QueryLocator` for all Pending `RCC_Import_Record__c` |
| `RCCCardBatchProcessor` | `execute()` | Per-chunk: validate, match/create Contact, enroll if needed, update Contact + staging record |
| `RCCCardBatchProcessor` | `finish()` | Insert `Batch_Run_Log__c`; send email |
| `RCCCardBatchProcessor` | `markProcessed()` | Sets `Status__c = 'Enrolled'` |
| `RCCCardBatchProcessor` | `markFailed()` | Sets `Status__c = 'Failed'`; populates `Error_Message__c` |
| `RCCRecordParser` | `validateRecord(rec)` | Checks card number, email format, status enum |
| `RCCRecordParser` | `parseRecord(csvRow)` | Parses raw CSV row into staging object |
| `RCCBatchScheduler` | `execute()` | Implements `Schedulable`; calls `Database.executeBatch` |
| `ContactMatchService` | `matchOrCreateContact(dto)` | Match by email; create if no match |
| `LoyaltyEnrollmentService` | `enrollNewMember(req)` | LC API enrollment (called if `Has_Loyalty__c = false`) |
| `LoyaltyLoginController` | `syncMemberAttributes(requests)` | `@InvocableMethod`; refreshes Platform Cache after attribute change |

**Flows:**
- `RCC_LPM_Attribute_Update_Flow` — Trigger: Contact after-save when `Has_Loyalty__c` or `Loyalty_Member_Type__c` IsChanged; Guard: `Loyalty_Member_Id__c` is not null + `Has_Loyalty__c = true`; Action: invokes `LoyaltyLoginController.syncMemberAttributes` (Apex action)

**Platform Events:** None (enrollment event published by `LoyaltyEnrollmentService` — same as story 1.1)

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `RCC_Import_Record__c` | `Card_Number__c`, `Email__c`, `Member_Type__c`, `Status__c` | `Status__c`, `Error_Message__c`, `Batch_Job_Id__c` |
| `Contact` | `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `Email`, `Phone` | `RCC_Card_Number__c`, `RCC_Active__c`, `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `Loyalty_Member_Type__c` |
| `Batch_Run_Log__c` | — | `Batch_Type__c`, `Completed_At__c`, `Total_Processed__c`, `Total_Succeeded__c`, `Total_Failed__c`, `Error_Summary__c`, `Apex_Job_Id__c` |

**Custom Metadata:**
- `Loyalty_Program_Config__mdt` — record `Default`; `Program_API_Name__c` for enrollment requests

**Permission Sets:**
- `Loyalty_Admin` — required for `RCCCardBatchProcessor` class access (see permission set XML)

## API Integration
| Field | Value |
|---|---|
| **Endpoint** | `POST /connect/loyalty/programs/{name}/individual-member-enrollments` |
| **When called** | Per record where Contact `Has_Loyalty__c = false` |
| **Request fields** | `memberType` (Retail or Pro), `loyaltyProgramName`, `enrollmentDate`, `contactDetails.{email}` |
| **Response fields** | `loyaltyProgramMember.id`, `loyaltyProgramMember.membershipNumber` |

## Execution Sequence
```
1. RCCBatchScheduler.execute() at 02:00
2. Database.executeBatch(new RCCCardBatchProcessor(), 50)
3. start() → SOQL: RCC_Import_Record__c WHERE Status__c = 'Pending'
4. execute(scope) — for each record:
   a. RCCRecordParser.validateRecord(rec)
      → if invalid: markFailed(rec); stats.recordFailure(); continue
   b. ExternalProfileDTO{email, rccCardNumber, sourceSystem='RCC_BATCH'}
   c. ContactMatchService.matchOrCreateContact(dto)
      → SOQL: Contact WHERE Email OR Phone OR loyaltyId OR epsilon
      → if found: updateContactFields if changed; DML update
      → if not found: DML insert Contact
   d. SOQL: Contact WHERE Id = :contactId (re-read Has_Loyalty__c)
   e. if !Has_Loyalty__c:
      → LoyaltyEnrollmentService.buildEnrollmentRequest(c, memberType)
        → SOQL: Loyalty_Program_Config__mdt WHERE DeveloperName='Default'
      → LoyaltyEnrollmentService.enrollNewMember(req) → LC API POST
      → Contact DML update (Has_Loyalty__c, Loyalty_Member_Id__c)
      → EventBus.publish(Loyalty_Enrollment_Event__e)
   f. Build Contact{RCC_Active__c, RCC_Card_Number__c} → contacts list
   g. markProcessed(rec) → toUpdate list
   h. stats.recordSuccess()
5. DML: update contacts (bulk)
6. DML: update toUpdate records (bulk)
7. Contact after-save → RCC_LPM_Attribute_Update_Flow fires if Has_Loyalty__c changed
   → LoyaltyLoginController.syncMemberAttributes(contactId)
     → LoyaltySessionCacheService.refreshMemberData(contactId) → 2 LC API calls
8. finish() → DML insert Batch_Run_Log__c
9. Messaging.sendEmail to loyalty-ops@company.com
```

## Manual Setup Required
- Batch scheduled via Execute Anonymous: `System.schedule('Nightly RCC Import', '0 0 2 * * ?', new RCCBatchScheduler())`
- `RCC_LPM_Attribute_Update_Flow` activated in Setup → Flows
- `Loyalty_Admin` permission set assigned to the running user or system/batch context
- Platform Cache partition `local.LoyaltyMemberData` created (used by `syncMemberAttributes`)
- `Loyalty_Program_Config__mdt` Default record has correct `Program_API_Name__c`
- Email address `loyalty-ops@company.com` must be deliverable (or update hardcoded value in source)

## Error Handling
| Error | Handling |
|---|---|
| Invalid staging record (missing email, bad status) | `markFailed(rec)` with reason; batch continues |
| `ContactMatchService` throws | `markFailed(rec)`; stats.recordFailure(); try-catch in execute loop |
| LC API fails during enrollment | Caught in execute try-catch; `markFailed(rec)` |
| `syncMemberAttributes` cache refresh fails | `System.debug(WARN)`; caught silently; no re-throw |
| Batch email fails | `Messaging.sendEmail` not in try-catch — could surface in `finish()` |

## Security
- `RCCCardBatchProcessor` — `with sharing`
- `ContactMatchService` — `with sharing`; creates Contacts in context user's sharing model
- `LoyaltyEnrollmentService` — `with sharing`
- Batch context user must have Create on Contact, Edit on `RCC_Import_Record__c`, Create on `Batch_Run_Log__c`

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Valid Retail record | Staging: Pending, email present, Member_Type=Retail | Status=Enrolled; Contact.RCC_Active__c=true; Batch_Run_Log Total_Succeeded++ |
| Valid Pro record (1.5) | Staging: Pending, email present, Member_Type=Pro | Enrolled with Pro type; Contact.Loyalty_Member_Type__c=Pro |
| Invalid — no email (1.6 analog) | Staging: Pending, no email | Status=Failed; Error_Message='Email is required'; batch continues |
| Invalid — bad status | Staging: Status='Unknown' | Status=Failed; error logged |
| Contact already enrolled | Email matches enrolled Contact | No LC call; Contact.RCC_Card_Number__c updated; Status=Enrolled |
| LC API fails | Mock returns 500 | Status=Failed; Batch_Run_Log.Total_Failed++ |
| Batch summary email | 3 records: 2 OK, 1 fail | Batch_Run_Log: Succeeded=2, Failed=1; email sent |

## Validation Queries
```sql
-- Recent batch run result
SELECT Batch_Type__c, Total_Processed__c, Total_Succeeded__c, Total_Failed__c, Completed_At__c
FROM Batch_Run_Log__c WHERE Batch_Type__c = 'RCC_Card_Import' ORDER BY Completed_At__c DESC LIMIT 1

-- Failed records needing review
SELECT Card_Number__c, Email__c, Status__c, Error_Message__c
FROM RCC_Import_Record__c WHERE Status__c = 'Failed' ORDER BY CreatedDate DESC

-- Contacts updated with RCC data
SELECT Email, RCC_Card_Number__c, RCC_Active__c, Loyalty_Member_Type__c
FROM Contact WHERE RCC_Card_Number__c != null ORDER BY LastModifiedDate DESC LIMIT 20

-- Pending records remaining (should be 0 after batch)
SELECT COUNT(Id) FROM RCC_Import_Record__c WHERE Status__c = 'Pending'
```

## Dependencies
- Story 1.1 — `LoyaltyEnrollmentService`, `ContactMatchService` must be deployed
- Story 1.7 — `LoyaltySessionCacheService` must be deployed (used by `syncMemberAttributes`)
- `Loyalty_Enrollment_Event__e` object deployed
- `Welcome_Email_Trigger_Flow` activated (if welcome email on batch enrollment is desired)

## Known Gaps
- **Completion email address hardcoded** in `RCCCardBatchProcessor.finish()` as `loyalty-ops@company.com`; should be in CMDT or Custom Setting
- **`RCC_Active__c = false` for cancellations (story 1.6)** only works if staging `Status__c` maps to a boolean; current code sets `rec.Status__c == 'Active'` check: `Contact.RCC_Active__c = rec.Status__c == 'Active'` — actually sets to `false` for Inactive/Cancelled, which is correct; but the Flow for suppressing LC bonus earn rule on cancellation is referenced in RICEF but not implemented in `RCC_LPM_Attribute_Update_Flow` (only syncs cache, doesn't call a "suppress earn rule" API)
- **`RCC_LPM_Attribute_Update_Flow`** calls `syncMemberAttributes` (cache refresh) but RICEF comment says it should "trigger RCC bonus earn rule in Loyalty Cloud" — no LC "update member attribute" API call exists in the current implementation for this flow
- **Batch size governor risk**: each record in execute() makes up to 3 SOQL queries + 1 LC callout; at 50/chunk this is within limits but should be monitored
- **Pro RCC (story 1.5)**: differentiated only by `Member_Type__c = 'Pro'` on staging record; no BSG brand-specific flag on Contact is set beyond `Loyalty_Member_Type__c`
