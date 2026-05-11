# STORY-1.25 — Order Submission: Points Award & Reversal

**RICEF ID:** 1.25 | **Type:** Services | **Complexity:** Complex | **Module:** SFSC, LC

## Business Purpose
Award loyalty points to a member when an order is fulfilled (via OMS platform event), and reverse those points if the order is cancelled, including reverting any redeemed certificates.

## Assumptions
- OMS (or MuleSoft) publishes `Order_Fulfilment_Event__e` on successful order fulfilment
- OMS publishes `Order_Cancellation_Event__e` on order cancellation; includes `Points_To_Reverse__c` and `Voucher_Ids_JSON__c`
- `Cart_Lines_JSON__c` on fulfilment event contains JSON array of line items already filtered/prepped by OMS
- `Loyalty_Member_Id__c` on the event is the LC LPM ID (not SFSC Contact Id)
- If `Loyalty_Member_Id__c` is blank → non-loyalty order → skip processing
- `orderId` is used as TJ `referenceId` in LC — LC rejects duplicate TJ for the same `orderId` (idempotency)
- `Order_Points_Status__c` custom object tracks state machine: Pending → Awarded → Reversed / Failed
- `PointsPendingStatusService` is called at order submission (before fulfilment) by the checkout layer to create the Pending record

## User Flow
1. Member submits order → checkout calls `PointsPendingStatusService.markPointsPending(orderId, lpmId)` → `Order_Points_Status__c` created with `Status = Pending`
2. OMS fulfils order → publishes `Order_Fulfilment_Event__e`
3. Apex trigger on `Order_Fulfilment_Event__e` → `OrderFulfilmentEventHandler.handleFulfilmentEvent(events)`
4. For each event: parse line items → build TJ DTO → call `executeTransaction` → LC creates TJ + awards points
5. `Order_Points_Status__c` updated to `Awarded` with TJ Id
6. If order cancelled → OMS publishes `Order_Cancellation_Event__e`
7. `OrderCancellationEventHandler.handleCancellationEvent(events)` fires
8. Vouchers cancelled (if any) → points debited → status set to `Reversed`

## Components

**LWC:** None (batch/event-driven)

**Apex:**
| Class | Method | Description |
|---|---|---|
| `OrderFulfilmentEventHandler` | `handleFulfilmentEvent(events)` | Main trigger entry point; per-event error isolation |
| `OrderFulfilmentEventHandler` | `processEvent(evt)` | Parses lines, builds DTO, calls `executeTransaction`, updates status |
| `OrderFulfilmentEventHandler` | `parseLineItems(jsonStr)` | Deserializes `Cart_Lines_JSON__c` JSON to `List<CartLineItem>` |
| `OrderCancellationEventHandler` | `handleCancellationEvent(events)` | Main trigger entry point for cancellations |
| `OrderCancellationEventHandler` | `processEvent(evt)` | Cancels vouchers, debits points, marks Reversed |
| `PointsPendingStatusService` | `markPointsPending(orderId, lpmId)` | Creates `Order_Points_Status__c` with Status=Pending (idempotent upsert) |
| `PointsPendingStatusService` | `markPointsAwarded(orderId, txnJournalId)` | Updates status to Awarded |
| `PointsPendingStatusService` | `markReversed(orderId)` | Updates status to Reversed |
| `PointsPendingStatusService` | `markFailed(orderId, errorMsg)` | Updates status to Failed |
| `LoyaltyTransactionService` | `executeTransaction(dto)` | `POST /transaction-journals/bulk` — creates TJ; awards points |
| `LoyaltyTransactionService` | `debitPoints(lpmId, amount, currency, reason)` | `POST /program-processes/Debit%20Points` (cancellation reversal) |
| `LoyaltyVoucherService` | `cancelVoucher(code, reason)` | `POST /program-processes/Cancel%20Voucher` (cancellation reversal) |

**Flows:** None

**Platform Events:**
| Event | Publisher | Handler |
|---|---|---|
| `Order_Fulfilment_Event__e` | OMS / MuleSoft | `OrderFulfilmentEventHandler` (Apex trigger required) |
| `Order_Cancellation_Event__e` | OMS / MuleSoft | `OrderCancellationEventHandler` (Apex trigger required) |

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Order_Fulfilment_Event__e` | `Loyalty_Member_Id__c`, `Order_Id__c`, `Order_Date__c`, `Cart_Lines_JSON__c` | — |
| `Order_Cancellation_Event__e` | `Loyalty_Member_Id__c`, `Order_Id__c`, `Points_To_Reverse__c`, `Voucher_Ids_JSON__c` | — |
| `Order_Points_Status__c` | `Order_Id__c`, `Status__c` | `Status__c` (Pending/Awarded/Reversed/Failed) |
| `Loyalty_Program_Config__mdt` | `Currency_ISO_Code__c` | — |

**Custom Metadata:**
- `Loyalty_Program_Config__mdt` — Default; `Currency_ISO_Code__c` for TJ and debit calls

**Permission Sets:**
- `Loyalty_Admin` — required for `Order_Points_Status__c` (CRUD in permission set)

## API Integration
| Operation | Endpoint | Method | Key Request Fields | Key Response Fields |
|---|---|---|---|---|
| Execute TJ (award) | `/transaction-journals/bulk` | POST | `lpmId`, `journalTypeName='Purchase'`, `activityDate`, `currencyName`, `lineItems[]` | `transactionJournals[0].id` (TJ Id) |
| Debit points (reversal) | `/program-processes/Debit%20Points` | POST | `memberId=lpmId`, `points`, `currency`, `reason` | 200 OK |
| Cancel voucher | `/program-processes/Cancel%20Voucher` | POST | `voucherCode`, `reason` | 200 OK |

## Execution Sequence

### Fulfilment (points award):
```
1. OMS fulfils order → publishes Order_Fulfilment_Event__e
2. Apex trigger fires → OrderFulfilmentEventHandler.handleFulfilmentEvent(events)
3. For each event:
   a. if Loyalty_Member_Id__c blank → return (non-loyalty)
   b. parseLineItems(Cart_Lines_JSON__c) → List<CartLineItem>
   c. Build TransactionJournalDTO:
      {lpmId, orderId, journalType='Purchase', activityDate, currencyCode, lineItems}
      → SOQL: Loyalty_Program_Config__mdt WHERE DeveloperName='Default'
   d. LoyaltyTransactionService.executeTransaction(dto)
      → LoyaltyAPIClient.post('/transaction-journals/bulk', payload)
      → Named Credential HTTP POST → LC creates TJ + awards points
      → Response: {transactionJournals[{id, ...}]}
   e. extractTJId(resp) → TJ Id string
   f. PointsPendingStatusService.markPointsAwarded(orderId, tjId) → DML update
4. On exception: statusService.markFailed(orderId, msg) → DML update
```

### Cancellation (reversal):
```
1. OMS cancels order → publishes Order_Cancellation_Event__e
2. Apex trigger fires → OrderCancellationEventHandler.handleCancellationEvent(events)
3. For each event:
   a. if Loyalty_Member_Id__c blank → return
   b. if Voucher_Ids_JSON__c not blank:
      parseVoucherCodes(Voucher_Ids_JSON__c) → List<String>
      for each code:
        LoyaltyVoucherService.cancelVoucher(code, 'ORDER_CANCELLED')
        → POST /Cancel%20Voucher
        → if LoyaltyVoucherException → add to errors list; continue
   c. if Points_To_Reverse__c > 0:
      → SOQL: Loyalty_Program_Config__mdt WHERE DeveloperName='Default'
      LoyaltyTransactionService.debitPoints(lpmId, points, currency, 'ORDER_CANCELLED:<orderId>')
      → POST /Debit%20Points
   d. PointsPendingStatusService.markReversed(orderId) → DML update
   e. if errors: System.debug(WARN) with voucher error list
```

## Manual Setup Required
- Apex triggers on `Order_Fulfilment_Event__e` and `Order_Cancellation_Event__e` must exist (trigger files not in this repo — handler classes are deployed but triggers are referenced in comments only)
- OMS/MuleSoft must be configured to publish the platform events with correct field mapping
- `Loyalty_Admin` permission set assigned to the trigger context user
- Named Credential `Loyalty_Cloud_API` OAuth configured
- `Order_Points_Status__c` DML permissions on the running user

## Error Handling
| Error | Handling |
|---|---|
| `Loyalty_Member_Id__c` blank on event | `return` early; no LC calls; no status update |
| `Cart_Lines_JSON__c` malformed JSON | `parseLineItems` catches and returns empty list; TJ sent with empty lines |
| LC `executeTransaction` fails | Caught in outer try-catch; `markFailed(orderId, msg)` |
| `debitPoints` fails | Exception propagates; `handleCancellationEvent` outer catch logs error |
| `cancelVoucher` fails for one code | `LoyaltyVoucherException` caught per-voucher; error added to list; reversal continues |
| Duplicate TJ (re-run event) | LC rejects duplicate `orderId` reference → LC 400 → `LoyaltyAPIException` → `markFailed` |

## Security
- `OrderFulfilmentEventHandler` — `with sharing`
- `OrderCancellationEventHandler` — `with sharing`
- `PointsPendingStatusService` — `with sharing`
- Platform event triggers run in the context of the Automated Process user or the integration user

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Full fulfilment | `Loyalty_Member_Id__c` set, valid Cart_Lines_JSON | TJ created; `Order_Points_Status__c.Status=Awarded` |
| Non-loyalty order | `Loyalty_Member_Id__c` blank | Skipped; no LC call; no status update |
| Cancellation with voucher | Event with voucher codes + 100 points | Voucher cancelled; 100 pts debited; Status=Reversed |
| Voucher cancel fails (one of two) | First code fails in LC | Error logged; second code attempted; points reversed; Status=Reversed |
| Points already awarded, cancelled | `Order_Points_Status__c` was Awarded | markReversed → status changes to Reversed |
| LC executeTransaction 500 | Mock returns 500 | `markFailed`; Status=Failed |
| Duplicate fulfilment event | Same orderId published twice | Second event → LC 400 → markFailed on second event |

## Validation Queries
```sql
-- Points status for a specific order
SELECT Status__c, Order_Id__c, CreatedDate FROM Order_Points_Status__c WHERE Order_Id__c = '<orderId>'

-- All awarded points today
SELECT Contact__c, Order_Id__c, Status__c, Points_Awarded__c
FROM Order_Points_Status__c WHERE Status__c = 'Awarded' AND CreatedDate = TODAY

-- Failed points awards (need investigation)
SELECT Order_Id__c, Status__c FROM Order_Points_Status__c WHERE Status__c = 'Failed'

-- Reversed orders (cancellations processed)
SELECT Order_Id__c, Status__c FROM Order_Points_Status__c
WHERE Status__c = 'Reversed' AND LastModifiedDate = TODAY
```

## Dependencies
- Story 1.7 — `LoyaltySessionCacheService` should be refreshed after points award (not currently called in `OrderFulfilmentEventHandler` — gap)
- Story 1.20 — Voucher cancellation in reversal flow shares `LoyaltyVoucherService`
- Apex trigger files for platform events must be deployed (not included in this repo)
- OMS integration must publish correctly-structured events

## Known Gaps
- **Apex triggers missing from source**: `OrderFulfilmentEventHandler` and `OrderCancellationEventHandler` class files exist, but no `trigger` files for `Order_Fulfilment_Event__e` or `Order_Cancellation_Event__e` are in the repo; these must be created separately
- **No session cache refresh after award**: `OrderFulfilmentEventHandler.processEvent()` does not call `LoyaltySessionCacheService.refreshMemberData()`; the member's displayed balance in SFSC will be stale until the next 30-min cache expiry or explicit agent refresh
- **`Contact__c` on `Order_Points_Status__c`**: The `PointsPendingStatusService` does not set a `Contact__c` field when creating the Pending record (only `Order_Id__c` and `Status__c`); SOQL in `PointsExpiryService` queries this field — potential mismatch if the field is populated by a different path
- **`markPointsPending` not called from `OrderFulfilmentEventHandler`**: the Pending state is expected to be set at checkout (by `CheckoutService`), not by the event handler; if checkout skips this call, `markPointsAwarded` silently no-ops (empty SOQL result)
- **Partial voucher cancel failure** (cancellation): errors are logged with `System.debug(WARN)` but not persisted to any object for ops review
