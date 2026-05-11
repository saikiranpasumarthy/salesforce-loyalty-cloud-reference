# STORY-1.20 / 1.21 — Certificate Redemption & Promo Code Validation

**RICEF IDs:** 1.20 (Certificate Redemption), 1.21 (Promo Code Validation) | **Type:** API | **Complexity:** Complex (1.20) / Medium (1.21) | **Module:** SFSC, LC

## Business Purpose
At checkout, allow members to apply and redeem reward certificates (vouchers) and promo codes against an order; with full multi-cert support and reversal on order cancellation.

## Assumptions
- **1.20**: Certificates are LC vouchers with a code (`voucherCode`); multiple can be applied to one order
- **1.20**: Validate-all-then-redeem-all pattern: if any validation fails, no redemptions occur
- **1.20**: `redeemVoucher(code, lpmId, orderId)` call binds the voucher to the order in LC
- **1.21**: Promo codes are validated by mapping the code to an LC promotion via `Loyalty_Exclusion_Rule__mdt`; a match triggers `LoyaltyPromotionService.enrollForPromotion`
- **1.21**: Promo code → promotion mapping currently uses `Loyalty_Exclusion_Rule__mdt` as a placeholder table (not a real promo code table)
- Cancellation reversal handled by `OrderCancellationEventHandler` (story 1.25)

## User Flow

### Certificate Redemption (1.20):
1. Member views checkout → certificate list loaded from session cache (story 1.7)
2. Member selects one or more certificates → LWC sends list to `redeemCertificatesAtSubmission`
3. Phase 1 — Validate all: for each code, `validateVoucher(code, lpmId)` called → any fail throws immediately
4. Phase 2 — Redeem all: for each code, `redeemVoucher(code, lpmId, orderId)` called
5. Order submitted with certificate discount applied
6. On order cancellation: `OrderCancellationEventHandler` calls `cancelVoucher` for each code → reinstates certificates

### Promo Code Validation (1.21):
1. Member enters promo code in checkout input field
2. `validateAndRedeemPromoCode(promoCode, lpmId, orderId)` called
3. If code maps to an active LC promotion → member enrolled in promotion
4. Promotion-based earn rate applies to the order

## Components

**LWC:**
- `loyaltyVoucherList` — Displays available certs/vouchers; Active tab shows redeemable certs; selection drives `redeemCertificatesAtSubmission` call

**Apex:**
| Class | Method | Description |
|---|---|---|
| `CheckoutService` | `redeemCertificatesAtSubmission(orderId, lpmId, voucherCodes)` | Validate all → redeem all; idempotency via validate gate |
| `CheckoutService` | `validateAndRedeemPromoCode(promoCode, lpmId, orderId)` | Looks up promo code → enrolls member in promotion |
| `LoyaltyVoucherService` | `validateVoucher(code, lpmId)` | `POST /program-processes/Validate%20Voucher` |
| `LoyaltyVoucherService` | `redeemVoucher(code, lpmId, orderId)` | `POST /program-processes/Redeem%20Voucher` |
| `LoyaltyVoucherService` | `cancelVoucher(code, reason)` | `POST /program-processes/Cancel%20Voucher` (called on cancellation) |
| `LoyaltyVoucherService` | `getMemberVouchers(lpmId)` | `GET /member-vouchers` (called at login, not at checkout) |
| `LoyaltyVoucherService` | `issueVoucher(lpmId, voucherDefId)` | `POST /program-processes/Issue%20Voucher` (for programmatic issuance) |
| `LoyaltyPromotionService` | `enrollForPromotion(lpmId, promotionName)` | `POST /program-processes/Enroll%20Promotions` (promo code apply) |

**Flows:** None

**Platform Events:**
- `Order_Cancellation_Event__e` — consumed by `OrderCancellationEventHandler`; drives cancellation reversal (story 1.25)

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Loyalty_Exclusion_Rule__mdt` | `DeveloperName`, `Is_Active__c` | None (used as promo code lookup placeholder) |
| `Order_Points_Status__c` | `Status__c`, `Order_Id__c` | None at redemption time; updated to Reversed on cancellation |

**Custom Metadata:**
- `Loyalty_Exclusion_Rule__mdt` — used as placeholder for promo code → promotion mapping in `validateAndRedeemPromoCode`

**Permission Sets:**
- `Loyalty_Agent` — needed if triggered from Service Cloud; checkout flow may run as system user

## API Integration
| Operation | Endpoint | Method | Request | Response |
|---|---|---|---|---|
| Validate voucher | `/program-processes/Validate%20Voucher` | POST | `{voucherCode, memberId: lpmId}` | 200 OK or 4xx with reason |
| Redeem voucher | `/program-processes/Redeem%20Voucher` | POST | `{voucherCode, memberId: lpmId, orderId}` | 200 OK → voucher status=Redeemed |
| Cancel voucher | `/program-processes/Cancel%20Voucher` | POST | `{voucherCode, reason}` | 200 OK → voucher status=Cancelled |
| Enroll promotion | `/program-processes/Enroll%20Promotions` | POST | `{memberId: lpmId, promotionName}` | 200 OK |

## Execution Sequence

### Certificate Redemption:
```
1. Checkout page: CheckoutService.redeemCertificatesAtSubmission(orderId, lpmId, ['CODE1','CODE2'])
2. if voucherCodes == null || isEmpty → return (no-op)
3. Phase 1 — validate all:
   for each code:
     LoyaltyVoucherService.validateVoucher(code, lpmId)
     → LoyaltyAPIClient.post('/program-processes/Validate%20Voucher', {voucherCode, memberId})
     → HTTP 200 OK → continue
     → HTTP 4xx → throw LoyaltyVoucherException → abort entire flow
4. All validations pass
5. Phase 2 — redeem all:
   for each code:
     LoyaltyVoucherService.redeemVoucher(code, lpmId, orderId)
     → LoyaltyAPIClient.post('/program-processes/Redeem%20Voucher', {voucherCode, memberId, orderId})
     → HTTP 200 → voucher now status=Redeemed in LC
6. Order submitted with discount applied
```

### Cancellation reversal (called from story 1.25):
```
1. OrderCancellationEventHandler receives Order_Cancellation_Event__e
2. parseVoucherCodes(evt.Voucher_Ids_JSON__c) → List<String> codes
3. for each code:
   LoyaltyVoucherService.cancelVoucher(code, 'ORDER_CANCELLED')
   → if LoyaltyVoucherException → log error; continue (partial failure allowed)
4. Points reversal (story 1.25) continues regardless of voucher cancel errors
```

### Promo Code Validation:
```
1. CheckoutService.validateAndRedeemPromoCode(promoCode, lpmId, orderId)
2. SOQL: Loyalty_Exclusion_Rule__mdt WHERE DeveloperName = :promoCode LIMIT 1
3. if empty → return false (code not recognized)
4. promotionId = promos[0].DeveloperName
5. LoyaltyPromotionService.enrollForPromotion(lpmId, promotionId)
   → LoyaltyAPIClient.post('/program-processes/Enroll%20Promotions', {memberId, promotionName})
6. return true → LWC shows success message
```

## Manual Setup Required
- Named Credential `Loyalty_Cloud_API` OAuth configured
- Checkout integration must call `CheckoutService.redeemCertificatesAtSubmission` at order submission
- Promo code → LC promotion mapping must be built via CMDT or a dedicated custom object (current implementation uses `Loyalty_Exclusion_Rule__mdt` as a stub)
- `loyaltyVoucherList` placed on Contact/checkout page; session cache populated from login (story 1.7)

## Error Handling
| Error | Handling |
|---|---|
| Validate fails for one voucher | `LoyaltyVoucherException` thrown; all redemptions aborted; LWC shows error message |
| Redeem fails mid-loop | `LoyaltyVoucherException` thrown; partial redemptions may have occurred — no automatic rollback |
| Cancel voucher fails (cancellation) | `LoyaltyVoucherException` caught; logged; points reversal continues |
| Promo code not found | `validateAndRedeemPromoCode` returns false; LWC shows "Invalid promo code" |
| LC 401 on any call | `LoyaltyAPIException(401)` → `LoyaltyVoucherException` wraps; surfaced as toast |

## Security
- `CheckoutService` — `with sharing`
- `LoyaltyVoucherService` — `with sharing`
- `LoyaltyPromotionService` — `with sharing`
- No PII in voucher codes or promo codes

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Single valid cert | `['CODE1']`, valid lpmId | Validate passes; Redeem called; order discounted |
| Multi-cert all valid | `['CODE1', 'CODE2']` both valid | Both validated; both redeemed |
| One cert invalid | `['CODE1', 'EXPIRED']` — EXPIRED fails | Validate aborts on EXPIRED; CODE1 also NOT redeemed |
| No certs | `[]` | Early return; no LC calls |
| Cancellation — cert reversal | Event with `Voucher_Ids_JSON__c = '["CODE1"]'` | `cancelVoucher('CODE1', 'ORDER_CANCELLED')` called |
| Valid promo code | `promoCode = 'SUMMER25'` matching CMDT record | Member enrolled in promotion; `true` returned |
| Invalid promo code | `promoCode = 'BADCODE'` | No CMDT match; `false` returned |

## Validation Queries
```sql
-- Order points status after certificate redemption
SELECT Status__c, Order_Id__c FROM Order_Points_Status__c WHERE Order_Id__c = '<orderId>'

-- Active exclusion rules used as promo code lookup (placeholder)
SELECT DeveloperName, Rule_Value__c FROM Loyalty_Exclusion_Rule__mdt WHERE Is_Active__c = true

-- Enrolled members with active vouchers (verify session data)
SELECT Id, Loyalty_Member_Id__c FROM Contact WHERE Has_Loyalty__c = true LIMIT 10
```

## Dependencies
- Story 1.7 — vouchers loaded at login; session data provides list to checkout LWC
- Story 1.25 — cancellation reversal calls `cancelVoucher`; both stories must be deployed together
- Named Credential `Loyalty_Cloud_API` configured
- `Loyalty_Exclusion_Rule__mdt` records deployed

## Known Gaps
- **Partial redemption rollback** (1.20): if `redeemVoucher` fails on the second code in a 2-cert list, the first cert is already redeemed in LC with no rollback; RICEF comment acknowledges "reversal on cancellation" but does not address this mid-redemption failure
- **Promo code table (1.21)**: `validateAndRedeemPromoCode` uses `Loyalty_Exclusion_Rule__mdt` as a lookup table for promo codes — this is a hardcoded stub; a real implementation needs a `PromoCode__c` custom object or CMDT type dedicated to promo codes
- **`issueVoucher`** method exists in `LoyaltyVoucherService` but is not called from `CheckoutService`; programmatic issuance flow is not wired to any story
- **Multi-cert UI in `loyaltyVoucherList`** — component shows filter tabs but no explicit "select to apply" checkbox UI is described; multi-cert accumulation for checkout relies on checkout page integration
