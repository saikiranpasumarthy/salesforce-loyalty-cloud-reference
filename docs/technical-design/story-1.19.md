# STORY-1.19 — Award Bonus Points: RCC Tender

**RICEF ID:** 1.19 | **Type:** API | **Complexity:** Medium | **Module:** SFSC, LC

## Business Purpose
When an authenticated member pays with their RCC (Retailer Credit Card) at checkout, include the RCC tender type in the transaction journal so Loyalty Cloud applies the RCC bonus earn rate on top of the base tier earn rate — resulting in a higher total points award at order fulfilment.

## Assumptions
- The RCC tender bonus is implemented entirely as an LC earn rule configured in the Loyalty Cloud program — no custom Apex logic for the bonus calculation
- The Apex layer only needs to pass `tenderType` in the TJ payload; LC handles the multiplier
- `RCC_Active__c` on the Contact indicates the member has an active RCC card; checked at session load (story 1.7)
- `Cart_Lines_JSON__c` on `Order_Fulfilment_Event__e` is populated by OMS; the `tenderType` field is also expected to be on the event but is not explicitly on the event object in the RICEF — assumed to be in the JSON or a separate field
- At simulation (story 1.17), `tenderId` passed from checkout drives RCC bonus preview; at fulfilment (story 1.25), `tenderType` is included in the TJ DTO
- `TransactionJournalDTO.tenderType` is an optional field; if null, LC applies base earn rate only

## User Flow
1. Member with `RCC_Active__c = true` proceeds to checkout
2. Checkout page detects RCC payment → assembles `CartEvaluationRequest` with `tenderId = 'RCC'`
3. `LoyaltyCartEvaluationService.evaluateCart(req)` → `simulateTransaction(dto)` → LC returns `{totalPointsAwarded, bonusPoints}` including RCC bonus
4. Checkout UI shows combined estimate: "You'll earn X base + Y bonus = Z total points"
5. Member submits order → OMS fulfils → `Order_Fulfilment_Event__e` published
6. `OrderFulfilmentEventHandler.processEvent(evt)` builds TJ DTO with `tenderType = 'RCC'`
7. `LoyaltyTransactionService.executeTransaction(dto)` → LC creates TJ with RCC earn rule applied
8. Member's points balance updated with RCC bonus included

## Components

**LWC:** None (no dedicated LWC; checkout integration layer assembles the tender type)

**Apex:**
| Class | Method | Description |
|---|---|---|
| `LoyaltyTransactionService` | `executeTransaction(dto)` | Includes `tenderType` from DTO in TJ payload when non-null |
| `LoyaltyTransactionService` | `simulateTransaction(dto)` | Same payload builder; `simulate=true` |
| `LoyaltyTransactionService` | `buildTxnBody(dto, simulate)` | Adds `tenderType` to TJ map if `dto.tenderType != null` |
| `LoyaltyCartEvaluationService` | `buildSimulationDTO(lpmId, lines, tenderId)` | Sets `dto.tenderType = tenderId` when RCC tender selected |
| `OrderFulfilmentEventHandler` | `processEvent(evt)` | Expected to set `tenderType` on TJ DTO from event data |

**Flows:** None

**Platform Events:**
- `Order_Fulfilment_Event__e` — expected to carry tender type information (field not confirmed in current source)

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Contact` | `RCC_Active__c` | None |
| `TransactionJournalDTO` | `tenderType` | — |

**Custom Metadata:**
- `Loyalty_Program_Config__mdt` — `Currency_ISO_Code__c` used in TJ payload

**Permission Sets:**
- Same as story 1.17 (cart evaluation) and 1.25 (fulfilment event handler)

## API Integration
| Operation | Endpoint | Method | Key Request Fields | Key Response Fields |
|---|---|---|---|---|
| Simulate with RCC tender | `/transaction-journals/bulk` | POST | `simulate=true`, `tenderType='RCC'`, `lineItems[]` | `transactionJournals[0].totalPointsAwarded`, `bonusPoints` |
| Execute with RCC tender | `/transaction-journals/bulk` | POST | `simulate=false`, `tenderType='RCC'`, `referenceId=orderId` | `transactionJournals[0].id` |

## Execution Sequence

### Cart simulation with RCC:
```
1. Checkout page: req.tenderId = 'RCC'  (RCC payment detected)
2. LoyaltyCartEvaluationService.evaluateCart(req)
3.   → applyExclusionRules(req.lineItems) → filtered lines
4.   → buildSimulationDTO(lpmId, filteredLines, 'RCC')
        → dto.tenderType = 'RCC'
5.   → LoyaltyTransactionService.simulateTransaction(dto)
6.   → buildTxnBody(dto, simulate=true)
        → txn.put('tenderType', 'RCC')
        → txn.put('simulate', true)
7.   → Named Credential POST → LC evaluates earn rules:
        base earn rate (tier-based) + RCC bonus rule → combined estimate
8.   → Response: {transactionJournals: [{totalPointsAwarded: 150, bonusPoints: 50}]}
9.   → CartEvaluationResponse{estimatedPoints: 150, bonusPoints: 50}
10. Checkout renders: "You'll earn 150 points (50 RCC bonus)"
```

### Fulfilment with RCC:
```
1. OMS fulfils order → publishes Order_Fulfilment_Event__e (tenderType expected in event)
2. OrderFulfilmentEventHandler.processEvent(evt)
3.   → dto.tenderType = evt.Tender_Type__c  (if field exists on event) or from Cart_Lines_JSON__c
4.   → LoyaltyTransactionService.executeTransaction(dto)
5.   → buildTxnBody(dto, simulate=false)
        → txn.put('tenderType', 'RCC')
        → txn.put('simulate', false)
6.   → Named Credential POST → LC creates TJ with RCC earn rule
7.   → Response: {transactionJournals: [{id: 'TJ-001', totalPointsAwarded: 150}]}
8.   → PointsPendingStatusService.markPointsAwarded(orderId, 'TJ-001')
```

## Manual Setup Required
- LC Earn Rule configured for RCC tender: Program → Earn Rules → "RCC Bonus" — applies when `tenderType = 'RCC'`
- `RCC_Active__c` field on Contact populated by the RCC batch (story 1.4)
- Checkout layer must pass `tenderId = 'RCC'` when RCC payment is selected
- OMS must include tender type in the `Order_Fulfilment_Event__e` (via `Tender_Type__c` field or inside `Cart_Lines_JSON__c`)

## Error Handling
| Error | Handling |
|---|---|
| `tenderType` is null | `buildTxnBody` omits the field; LC applies base earn rate only (no bonus) |
| RCC earn rule not configured in LC | LC processes TJ at base rate; no error; `bonusPoints = 0` in response |
| `RCC_Active__c = false` but `tenderId = 'RCC'` sent | LC validates the member's tender eligibility; may return 400 if ineligible |
| Simulation fails | `LoyaltyAPIException` thrown; checkout suppresses points estimate (story 1.17 error handling) |

## Security
- No dedicated Apex class for story 1.19 — security follows `LoyaltyTransactionService` (`with sharing`) and `LoyaltyCartEvaluationService` (`with sharing`)
- `tenderType` is a business attribute; no PII risk

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| RCC payment simulation | `tenderId='RCC'`, valid cart | Simulation includes RCC bonus; `bonusPoints > 0` |
| Non-RCC payment simulation | `tenderId='CreditCard'` | Simulation at base rate; `bonusPoints = 0` |
| RCC fulfilment | `tenderType='RCC'` in TJ DTO | LC awards base + RCC bonus points; TJ created |
| No tender type | `dto.tenderType = null` | `tenderType` omitted from payload; base earn rate applied |
| `RCC_Active__c = false` | Member not RCC-enrolled | Checkout should suppress RCC tender option (not enforced in Apex) |

## Validation Queries
```sql
-- Members with active RCC card (eligible for RCC bonus)
SELECT Id, RCC_Active__c, Loyalty_Member_Id__c, Loyalty_Member_Type__c
FROM Contact WHERE RCC_Active__c = true AND Has_Loyalty__c = true LIMIT 20

-- Orders awarded with RCC bonus (verify via LC TJ — no SFSC field for bonus)
SELECT Order_Id__c, Status__c, Points_Awarded__c
FROM Order_Points_Status__c WHERE Status__c = 'Awarded'

-- RCC card holders enrolled this week (from batch)
SELECT Id, RCC_Card_Number__c, RCC_Active__c, Loyalty_Member_Id__c
FROM Contact WHERE RCC_Active__c = true AND LastModifiedDate = THIS_WEEK
```

## Dependencies
- Story 1.4 — `RCC_Active__c` set by `RCCCardBatchProcessor`; required before RCC tender bonus can apply
- Story 1.17 — `LoyaltyCartEvaluationService.buildSimulationDTO` passes `tenderId` to `dto.tenderType`
- Story 1.25 — `OrderFulfilmentEventHandler.processEvent` must set `tenderType` on the TJ DTO from the event
- LC Earn Rule for RCC bonus must be configured in the Loyalty Cloud program console

## Known Gaps
- **`tenderType` not on `Order_Fulfilment_Event__e`**: the event object fields in the source (`Loyalty_Member_Id__c`, `Order_Id__c`, `Order_Date__c`, `Cart_Lines_JSON__c`) do not include `Tender_Type__c`; if OMS does not add this field, the TJ at fulfilment will always have `tenderType = null` → RCC bonus is never applied at fulfilment, even if it was simulated at checkout
- **No validation that member is RCC-eligible**: `buildTxnBody` blindly passes whatever `tenderType` is in the DTO; if a non-RCC member's tender is set to `'RCC'` by a bug, LC may apply the bonus incorrectly or return an error — no guard in Apex
- **`bonusPoints` display not verified in LWC**: `CartEvaluationResponse.bonusPoints` is returned but the RICEF mentions "combined earn estimate (base tier + RCC bonus)" on Order Review page — no LWC HTML/CSS confirms this breakdown is displayed; likely requires checkout integration layer to consume the `bonusPoints` field explicitly
