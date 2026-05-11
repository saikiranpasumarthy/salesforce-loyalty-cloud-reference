# STORY-T3 — Annual Points Expiry Batch

**RICEF ID:** T3 (code-inferred; not in RICEF spreadsheet) | **Type:** Batch | **Complexity:** Medium | **Module:** SFSC, LC

## Business Purpose
On January 1 each year, expire all loyalty points for US members who have not made a qualifying purchase in the prior 12 months by debiting their full balance via the LC Debit Points API — while permanently exempting Canadian (CA) members from expiry.

## Assumptions
- US members: `Contact.Country_Code__c = 'US'` — subject to annual expiry
- CA members: `Contact.Country_Code__c = 'CA'` — permanently exempt; never processed
- "Qualifying purchase" = `Order_Points_Status__c` record with `Status__c = 'Awarded'` within last 365 days
- Members with 0 points balance are skipped (no debit call needed)
- Each contact requires 1 LC `getRewardsPoints` call + 1 LC `debitPoints` call (2 callouts per eligible member)
- Apex batch governor limit: 100 callouts per `execute` chunk — keep batch size ≤ 50 to stay within limits (2 callouts × 50 = 100)
- `PointsExpiryScheduler` runs `PointsExpiryBatch` annually on January 1
- Batch is `Database.Stateful` — running totals survive between chunks; logged to `Batch_Run_Log__c` in `finish()`

## User Flow
1. January 1 → `PointsExpiryScheduler.execute()` fires → `Database.executeBatch(new PointsExpiryBatch(), 50)`
2. `start()`: SOQL returns all US Contacts with `Has_Loyalty__c=true` and `Loyalty_Member_Id__c != null`
3. `execute()` per chunk:
   - For each Contact: `PointsExpiryService.evaluateExpiryEligibility(contactId)` — checks CA exemption, 12-month purchase window, balance > 0
   - If eligible: `PointsExpiryService.processExpiry(contactId)` — LC `debitPoints` for full balance
   - Per-record try-catch: failed records added to `failedIds`; batch continues
4. `finish()`: `Batch_Run_Log__c` inserted with totals (expired/skipped/failed)

## Components

**LWC:** None

**Apex:**
| Class | Method | Description |
|---|---|---|
| `PointsExpiryBatch` | `start(bc)` | QueryLocator for US enrolled Contacts; excludes CA via `Country_Code__c = 'US'` |
| `PointsExpiryBatch` | `execute(bc, scope)` | Per-contact eligibility check + expiry; stateful running totals |
| `PointsExpiryBatch` | `finish(bc)` | Inserts `Batch_Run_Log__c` with summary stats |
| `PointsExpiryService` | `evaluateExpiryEligibility(contactId)` | Returns true if US, no qualifying purchase in 12 months, balance > 0 |
| `PointsExpiryService` | `processExpiry(contactId)` | Reads balance via LC; calls `debitPoints` for full balance |
| `PointsExpiryService` | `isCAMember(contactId)` | Returns true if `Country_Code__c = 'CA'` |
| `PointsExpiryService` | `getLastQualifyingPurchaseDate(lpmId)` | SOQL `Order_Points_Status__c` where `Status='Awarded'` ordered desc |
| `PointsExpiryScheduler` | `execute(sc)` | `Schedulable`; fires `Database.executeBatch` annually |
| `LoyaltyTransactionService` | `debitPoints(lpmId, amount, currency, reason)` | `POST /program-processes/Debit%20Points` — reason: `'ANNUAL_EXPIRY:{year}'` |

**Batch State (`Database.Stateful`):**
- `totalExpired` — count of members whose points were debited
- `totalSkipped` — count of members who were ineligible
- `totalFailed` — count of members where processing threw an exception
- `failedIds` — `List<String>` of `{contactId}: {errorMessage}` entries

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Contact` | `Id`, `FirstName`, `LastName`, `Email`, `Loyalty_Member_Id__c`, `Country_Code__c`, `Has_Loyalty__c` | None |
| `Order_Points_Status__c` | `Contact__c`, `Status__c`, `CreatedDate` | None |
| `Loyalty_Program_Config__mdt` | `Currency_ISO_Code__c` | None |
| `Batch_Run_Log__c` | None | `Batch_Type__c`, `Completed_At__c`, `Total_Processed__c`, `Total_Succeeded__c`, `Total_Failed__c`, `Error_Summary__c`, `Apex_Job_Id__c` |

**Permission Sets:**
- `Loyalty_Admin` — required to manually trigger or re-schedule the batch

## API Integration
| Operation | Endpoint | Method | Key Request Fields | Key Response Fields |
|---|---|---|---|---|
| Read balance (eligibility) | `/member-benefits?memberId={lpmId}` | GET | — | `pointsBalance` |
| Debit points (expiry) | `/program-processes/Debit%20Points` | POST | `memberId`, `points`, `currency`, `reason='ANNUAL_EXPIRY:{year}'` | 200 OK |

## Execution Sequence
```
January 1 → PointsExpiryScheduler.execute()
→ Database.executeBatch(new PointsExpiryBatch(), 50)

start():
→ Database.getQueryLocator([
    SELECT Id, FirstName, LastName, Email, Loyalty_Member_Id__c, Country_Code__c
    FROM Contact
    WHERE Country_Code__c = 'US'
    AND Has_Loyalty__c = true
    AND Loyalty_Member_Id__c != null
  ])

execute() per chunk of 50:
→ for each Contact c:
    try:
      expirySvc.evaluateExpiryEligibility(c.Id)
        → isCAMember(c.Id): SOQL Contact → false (US member, passes)
        → SOQL Contact WHERE Id=c.Id → Loyalty_Member_Id__c
        → getLastQualifyingPurchaseDate(lpmId)
            → SOQL Order_Points_Status__c WHERE Contact__c IN (SELECT Id FROM Contact WHERE Loyalty_Member_Id__c=:lpmId)
              AND Status__c='Awarded' ORDER BY CreatedDate DESC LIMIT 1
            → if lastPurchase >= today-365 → return false (has qualifying purchase)
        → LoyaltyMemberService.getRewardsPoints(lpmId) → pointsBalance
        → if pointsBalance > 0 → return true
      
      if eligible:
        expirySvc.processExpiry(c.Id)
          → SOQL Contact → Loyalty_Member_Id__c
          → LoyaltyMemberService.getRewardsPoints(lpmId) → pointsBalance
          → SOQL Loyalty_Program_Config__mdt → currencyCode
          → LoyaltyTransactionService.debitPoints(lpmId, pointsBalance, currencyCode, 'ANNUAL_EXPIRY:2025')
          → POST /program-processes/Debit%20Points
        totalExpired++
      else:
        totalSkipped++
    catch(Exception e):
      totalFailed++; failedIds.add(c.Id + ': ' + e.getMessage())

finish():
→ insert Batch_Run_Log__c{
    Batch_Type__c='PointsExpiryBatch',
    Completed_At__c=DateTime.now(),
    Total_Processed__c=expired+skipped+failed,
    Total_Succeeded__c=expired,
    Total_Failed__c=failed,
    Error_Summary__c=failedIds.join('\n').left(131072),
    Apex_Job_Id__c=jobId
  }
```

## Manual Setup Required
- Schedule `PointsExpiryScheduler` to run annually on January 1:
  ```apex
  System.schedule('Annual Points Expiry', '0 0 2 1 1 ? *', new PointsExpiryScheduler());
  ```
  (CRON: 2 AM UTC on January 1 — adjust for timezone as needed)
- `Batch_Run_Log__c` custom object deployed with fields: `Batch_Type__c`, `Completed_At__c`, `Total_Processed__c`, `Total_Succeeded__c`, `Total_Failed__c`, `Error_Summary__c`, `Apex_Job_Id__c`
- `Loyalty_Program_Config__mdt` Default record with correct `Currency_ISO_Code__c`
- Named Credential `Loyalty_Cloud_API` OAuth configured
- Verify batch size ≤ 50 if 2 callouts per record (benefits + debit)

## Error Handling
| Error | Handling |
|---|---|
| CA member in query scope | `isCAMember` returns true in `evaluateExpiryEligibility` → `return false` → skip |
| Member has qualifying purchase | `lastPurchase >= today-365` → `return false` → skip |
| Member has 0 balance | `pointsBalance <= 0` → `return false` → skip |
| `getRewardsPoints` fails during eligibility check | `WARN` debug; `return false` → skip (conservative — do not expire if balance unknown) |
| `debitPoints` LC call fails | Exception caught; `totalFailed++`; `failedIds.add(...)`; batch continues |
| Entire chunk fails | Per-record catch prevents full chunk failure; each record isolated |
| `Batch_Run_Log__c` insert fails in `finish()` | Uncaught — would surface as unhandled exception in the Apex job; job summary lost |

## Security
- `PointsExpiryBatch` — `with sharing`
- `PointsExpiryService` — `with sharing`
- Batch runs as the scheduled user (must have `Loyalty_Admin` or explicit permissions on `Order_Points_Status__c` and `Batch_Run_Log__c`)
- No PII in `Batch_Run_Log__c` except Contact IDs in `Error_Summary__c`

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| US member, no purchases | US, enrolled, 500 pts, no `Order_Points_Status__c` in 12 months | Eligible=true; `debitPoints(500)` called; `totalExpired++` |
| US member, recent purchase | US, enrolled, 500 pts, `Awarded` record 30 days ago | Eligible=false; `totalSkipped++`; no LC call |
| CA member | CA, enrolled, 500 pts | `isCAMember=true`; `evaluateExpiryEligibility=false`; `totalSkipped++` |
| Zero balance member | US, enrolled, balance=0 | `evaluateExpiryEligibility=false`; `totalSkipped++` |
| LC `debitPoints` fails | LC mock returns 500 | `totalFailed++`; `failedIds` entry; batch continues |
| `getRewardsPoints` fails (eligibility) | LC mock returns 500 during benefits check | `WARN` debug; `return false`; `totalSkipped++` |
| Batch summary logged | Any run | `Batch_Run_Log__c` record with expired/skipped/failed counts |

## Validation Queries
```sql
-- US members with active loyalty (batch scope)
SELECT Id, Loyalty_Member_Id__c, Country_Code__c FROM Contact
WHERE Country_Code__c = 'US' AND Has_Loyalty__c = true AND Loyalty_Member_Id__c != null

-- CA members (should never be processed)
SELECT Id, Loyalty_Member_Id__c FROM Contact WHERE Country_Code__c = 'CA' AND Has_Loyalty__c = true

-- Members with a qualifying purchase in the last 12 months
SELECT Contact__c, MAX(CreatedDate) lastPurchase
FROM Order_Points_Status__c
WHERE Status__c = 'Awarded'
GROUP BY Contact__c
HAVING MAX(CreatedDate) >= LAST_N_DAYS:365

-- Batch run history
SELECT Batch_Type__c, Completed_At__c, Total_Processed__c, Total_Succeeded__c, Total_Failed__c
FROM Batch_Run_Log__c WHERE Batch_Type__c = 'PointsExpiryBatch' ORDER BY Completed_At__c DESC LIMIT 5

-- Failed members from last run
SELECT Error_Summary__c FROM Batch_Run_Log__c
WHERE Batch_Type__c = 'PointsExpiryBatch' ORDER BY Completed_At__c DESC LIMIT 1
```

## Dependencies
- Story 1.25 — `Order_Points_Status__c` records with `Status='Awarded'` are the source of qualifying purchase dates; must be populated correctly by `PointsPendingStatusService.markPointsAwarded`
- `LoyaltyTransactionService.debitPoints` — shared with story 1.25 (cancellation reversal)
- `Loyalty_Program_Config__mdt` Default record deployed with `Currency_ISO_Code__c`
- `Batch_Run_Log__c` custom object deployed

## Known Gaps
- **`evaluateExpiryEligibility` makes 2 SOQLs + 1 LC callout per record**: with a batch size of 50 and ~2 callouts per eligible member, the callout limit (100/transaction) is tight; if all 50 members are eligible, the chunk hits exactly 100 callouts — no headroom for retry or additional logic
- **`processExpiry` makes another SOQL + callout**: `processExpiry` re-queries the Contact and re-reads the balance (because `evaluateExpiryEligibility` doesn't pass the balance forward) — this causes a duplicate `getRewardsPoints` call per eligible member; refactor to pass balance from evaluate to process
- **`Contact__c` field on `Order_Points_Status__c`**: `getLastQualifyingPurchaseDate` queries by `Contact__c` field using a subquery — this field must be populated by `PointsPendingStatusService.markPointsPending` (confirmed gap in story 1.25 Known Gaps)
- **No email notification on expiry**: `PointsExpiryBatch.finish()` only inserts a `Batch_Run_Log__c` record; no SFMC/email notification is sent to members whose points expired — the RICEF mentions "publish SFMC expiry notification event" but no `EventBus.publish` call exists in the code
- **Scheduler not pre-deployed**: `PointsExpiryScheduler` must be manually scheduled via Execute Anonymous; there is no declarative scheduled job in the source
