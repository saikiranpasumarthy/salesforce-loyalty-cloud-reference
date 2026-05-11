# STORY-1.17 — Points Earn Preview: Cart / Checkout

**RICEF ID:** 1.17 | **Type:** API | **Complexity:** Medium | **Module:** SFSC, LC

## Business Purpose
Display total estimated loyalty points the member will earn on their current cart or checkout page, using a read-only Loyalty Cloud cart evaluation API (simulate only — no TJ created).

## Assumptions
- Member must be authenticated and enrolled (has active LPM)
- Guest/non-loyalty users see no estimate (LWC suppresses)
- Points estimate updates dynamically on cart changes (re-call on cart update)
- `simulateTransaction` is used (not `executeTransaction`) — no LC record created
- Exclusion rules apply: items in excluded categories (Fuel, Gift Cards, Tobacco, Generic Brand) are stripped from the payload before simulation
- Tender type is available at checkout (from payment selection); RCC tender adds bonus earn (story 1.19)
- `Loyalty_Exclusion_Rule__mdt` records loaded once per transaction (lazy cached)

## User Flow
1. Authenticated member views cart page → LWC calls `evaluateCart(req)`
2. Cart line items + LPM ID + tender type assembled into `CartEvaluationRequest`
3. Exclusion rules applied: excluded category lines flagged as `isExcluded = true`
4. `simulateTransaction(dto)` called → LC returns `{totalPointsAwarded, bonusPoints}`
5. LWC renders "You'll earn X points" in cart summary; suppressed for guest users
6. On cart change → re-call with updated line items → estimate updates

## Components

**LWC:** (LWC renders the estimate — no dedicated named component in this repo; called from checkout integration layer)

**Apex:**
| Class | Method | Description |
|---|---|---|
| `LoyaltyCartEvaluationService` | `evaluateCart(req)` | Entry point; applies exclusions; calls simulate |
| `LoyaltyCartEvaluationService` | `buildCartRequest(lines, lpmId, tenderId)` | Convenience builder for `CartEvaluationRequest` |
| `LoyaltyCartEvaluationService` | `applyExclusionRules(lines)` | Clones line items; sets `isExcluded=true` for excluded categories |
| `LoyaltyCartEvaluationService` | `getExclusionRules()` | SOQL `Loyalty_Exclusion_Rule__mdt`; static cache per transaction |
| `LoyaltyCartEvaluationService` | `buildSimulationDTO(lpmId, lines, tenderId)` | Assembles `TransactionJournalDTO` for simulation |
| `LoyaltyTransactionService` | `simulateTransaction(dto)` | `POST /transaction-journals/bulk?simulate=true` (no LC record created) |
| `LoyaltyAPIClient` | `post(path, body)` | Named Credential HTTP POST |

**Flows:** None

**Platform Events:** None

**DTOs:**
- `CartEvaluationRequest` — `lpmId`, `tenderId`, `List<CartLineItem>`
- `CartLineItem` — `productId`, `sku`, `categoryName`, `quantity`, `unitPrice`, `lineTotal`, `isExcluded`
- `CartEvaluationResponse` — `estimatedPoints`, `bonusPoints`
- `TransactionJournalDTO` — `lpmId`, `journalTypeName`, `activityDate`, `currencyName`, `tenderType`, `List<CartLineItem>`

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Loyalty_Exclusion_Rule__mdt` | `Rule_Value__c`, `Is_Active__c` | None |
| `Loyalty_Program_Config__mdt` | `Currency_ISO_Code__c` | None |

**Custom Metadata:**
- `Loyalty_Exclusion_Rule__mdt` — 4 active records: Exclude_Fuel, Exclude_Gift_Cards, Exclude_Tobacco, Exclude_Generic_Brand; `Rule_Value__c` matched against `CartLineItem.categoryName`
- `Loyalty_Program_Config__mdt` — Default; `Currency_ISO_Code__c` = `'USD'` used in DTO

**Permission Sets:**
- `Loyalty_Agent` — minimum for Apex access

## API Integration
| Field | Value |
|---|---|
| **Endpoint** | `POST /connect/loyalty/programs/{name}/transaction-journals/bulk` |
| **Simulate mode** | `?simulate=true` query param (or request body flag per LC version) |
| **Request fields** | `lpmId`, `journalTypeName='Purchase'`, `activityDate`, `currencyName`, `tenderType`, `lineItems[{productId, sku, categoryName, quantity, unitPrice, lineTotal, isExcluded}]` |
| **Response fields** | `transactionJournals[0].totalPointsAwarded`, `transactionJournals[0].bonusPoints` |

## Execution Sequence
```
1. Checkout page assembles CartEvaluationRequest:
   req.lpmId = member's lpmId (from session data)
   req.tenderId = selected payment type
   req.lineItems = cart lines with productId, categoryName, unitPrice, lineTotal

2. LoyaltyCartEvaluationService.evaluateCart(req)
3.   → applyExclusionRules(req.lineItems)
4.     → getExclusionRules()
5.       → static exclusionCache: if null
6.       → SOQL: Loyalty_Exclusion_Rule__mdt WHERE Is_Active__c=true
7.       → Map{'Fuel'→true, 'Gift Cards'→true, 'Tobacco'→true, 'Generic Brand'→true}
8.     → For each line: if categoryName in exclusionCache → copy.isExcluded=true
9.   → buildSimulationDTO(lpmId, eligibleLines, tenderId)
10.    → SOQL: Loyalty_Program_Config__mdt WHERE DeveloperName='Default' → currencyCode
11.    → TransactionJournalDTO{lpmId, type='Purchase', date=today, currency, lines}
12.  → LoyaltyTransactionService.simulateTransaction(dto)
13.    → JSON.serialize(dto)
14.    → LoyaltyAPIClient.post('/transaction-journals/bulk?simulate=true', payload)
15.    → Named Credential HTTP POST → LC simulates earn calculation → no record created
16.    → Response: {transactionJournals: [{totalPointsAwarded, bonusPoints}]}
17.  → parseEvaluationResponse(raw) → CartEvaluationResponse{estimatedPoints, bonusPoints}
18. Return to checkout page → render "You'll earn X points"
```

## Manual Setup Required
- Named Credential `Loyalty_Cloud_API` OAuth configured
- `Loyalty_Exclusion_Rule__mdt` records deployed (4 records included in source)
- `Loyalty_Program_Config__mdt` Default record with correct `Currency_ISO_Code__c`
- Checkout page integration must assemble `CartEvaluationRequest` and call this service

## Error Handling
| Error | Handling |
|---|---|
| LC API 4xx/5xx during simulation | `LoyaltyAPIException` thrown; caller catches; estimate not shown (suppress gracefully) |
| Empty cart / no line items | `evaluateCart` returns `CartEvaluationResponse{estimatedPoints=0}` |
| Non-loyalty user | Caller should check `hasLoyalty` from session data before calling; if called anyway, lpmId is blank → LC returns 400 |
| CMDT query returns no results | `CurrencyCode` defaults may cause LC to return 400; should default to `'USD'` |

## Security
- `LoyaltyCartEvaluationService` — `with sharing`
- `LoyaltyTransactionService` — `with sharing`
- `getExclusionRules()` is `public static` — accessible from other classes (used by `CheckoutService.buildFulfilmentPayload`)
- No PII transmitted; lpmId is an opaque identifier

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| All eligible items | 3 cart lines, no excluded categories | `estimatedPoints > 0`; simulation returns LC estimate |
| Some excluded items | 1 Fuel line + 2 regular lines | Fuel line excluded; points calculated on 2 lines only |
| All excluded items | All lines in excluded categories | `estimatedPoints = 0` |
| RCC tender | `tenderId = 'RCC'` | Simulation includes RCC bonus; `bonusPoints > 0` |
| Non-loyalty user | `lpmId = null` | Caller should suppress; if called, LC returns 400 → `LoyaltyAPIException` |
| LC simulation fails | Mock 500 | Exception caught; estimate not rendered |
| Empty cart | 0 line items | `estimatedPoints = 0` returned without LC call |

## Validation Queries
```sql
-- Active exclusion rules
SELECT DeveloperName, Rule_Value__c, Is_Active__c
FROM Loyalty_Exclusion_Rule__mdt WHERE Is_Active__c = true

-- Currency config
SELECT Currency_ISO_Code__c FROM Loyalty_Program_Config__mdt WHERE DeveloperName = 'Default'

-- Enrolled members who should see cart estimate
SELECT Id, Loyalty_Member_Id__c FROM Contact WHERE Has_Loyalty__c = true LIMIT 10
```

## Dependencies
- Story 1.7 — session data provides `lpmId` to checkout page
- Named Credential `Loyalty_Cloud_API` configured
- `Loyalty_Exclusion_Rule__mdt` records deployed

## Known Gaps
- **`simulateTransaction` endpoint ambiguity**: LC API uses `POST /transaction-journals/bulk` for both execute and simulate; the `?simulate=true` flag is assumed — verify against actual LC API documentation for program `LevelUp`
- **No dedicated LWC** for this story in the repo — the `LoyaltyCartEvaluationService` is a backend service; the LWC rendering the estimate must be implemented as part of the checkout/PDP integration layer (referenced in RICEF as a separate LWC component)
- **`exclusionCache` is static per-transaction** (Apex transaction scope) — safe for a single request; but if the checkout page makes multiple calls in the same request context (e.g., cart update), the rules are loaded only once — this is intentional and correct
- **Bonus point display (story 1.19)**: `bonusPoints` is returned in `CartEvaluationResponse` but the combined display (base + RCC bonus) depends on the caller correctly using `bonusPoints` field; the RICEF mentions "combined earn estimate (base tier + RCC bonus)" on Order Review page — not verified in LWC layer
