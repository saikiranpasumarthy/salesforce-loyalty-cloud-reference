# STORY-3.1 — OneTrust: Privacy Deletion (GDPR Erasure / CCPA Delete)

**RICEF ID:** 3.1 | **Type:** API + Flow | **Complexity:** Complex | **Module:** SFSC, LC

## Business Purpose
Process right-to-erasure (GDPR) and CCPA deletion requests by unenrolling the member from Loyalty Cloud, cancelling active vouchers, clearing PII fields on the SFSC Contact, and writing an immutable audit trail — triggered either via OneTrust webhook or a Flow-driven agent request.

## Assumptions
- OneTrust sends deletion requests via OAuth 2.0 Connected App to `POST /services/apexrest/privacy/delete/`
- `Privacy_Request__c` custom object is the master record; `Privacy_Audit_Log__c` is a Master-Detail child
- Two entry points share the same `PrivacyDeletionService` workflow: OneTrust REST webhook and `Privacy_Request_Handler_Flow` (agent-initiated)
- Orders in terminal states (Delivered, Cancelled, Failed) do not block deletion
- Transaction Journal records are **not deleted** — retained for financial compliance
- Order records are **not deleted** — retained per commerce policy
- DML-before-callout rule enforced: all LC callouts (voucher cancel, unenroll) happen in Phase 1; all DML (Contact update, audit log insert) happen in Phase 2
- `PrivacyDeletionService` is `without sharing` — needs to read/write Contact regardless of agent's visibility

## User Flow

### OneTrust Webhook Path:
1. Privacy request received by OneTrust → OneTrust calls `POST /services/apexrest/privacy/delete/` with `{contactId, requestId, requestType='DELETION'}`
2. `PrivacyDeletionAPIController.doDelete()` validates fields and calls `PrivacyDeletionService.processPrivacyRequest`
3. Phase 1 (callouts): active vouchers cancelled → LC unenroll called
4. Phase 2 (DML): Contact PII cleared → `Privacy_Request__c` upserted → audit log entries inserted
5. HTTP 200 `{"status":"SUCCESS", "systemsUpdated":["LoyaltyCloud","SFSC"]}` returned

### Flow-Triggered Path:
1. Agent sets `Privacy_Request__c.Status__c = 'In_Progress'` on a record
2. `Privacy_Request_Handler_Flow` fires (record-triggered after-save)
3. Decision checks `Request_Type__c IN ('Erasure', 'CCPA_Delete')`
4. `PrivacyDeletionController.processPrivacyRequest(contactId, privacyRequestId)` called as `@InvocableMethod`
5. Same 4-gate workflow executes; flow updates status to `Completed` or `Failed`

## Components

**LWC:** None (API/Flow-driven)

**Apex:**
| Class | Method | Description |
|---|---|---|
| `PrivacyDeletionAPIController` | `doDelete()` | `POST /privacy/delete/*`; validates request body; calls service; formats response |
| `PrivacyDeletionController` | `processPrivacyRequest(List<DeletionRequest>)` | `@InvocableMethod`; delegates to `PrivacyDeletionService`; called from flow |
| `PrivacyDeletionService` | `processPrivacyRequest(contactId, source, requestId)` | Main 4-gate workflow: check orders → cancel vouchers → unenroll → clear PII → audit |
| `PrivacyDeletionService` | `unenrollFromLoyalty(lpmId, reason)` | Delegates to `LoyaltyMemberService.unenrollMember` → `POST /program-processes/Unenroll%20Member` |
| `PrivacyDeletionService` | `deactivateContact(contactId)` | Clears 12 PII fields; sets `FirstName='Deleted'`, `LastName='User {last4}'` |
| `PrivacyDeletionService` | `handleUnredeemedVouchers(lpmId)` | `getMemberVouchers` → loops active vouchers → `cancelVoucher(code, 'PRIVACY_REQUEST')` |
| `PrivacyDeletionService` | `ensurePrivacyRequest(contactId, requestId)` | Upserts `Privacy_Request__c` by `OneTrust_Request_Id__c`; returns master record Id |
| `PrivacyDeletionService` | `getLastQualifyingPurchaseDate(lpmId)` | Shared with `PointsExpiryService`; returns last `Status='Awarded'` date |
| `PrivacyAuditLogger` | `log(contactId, action, source, requestId, privacyRequestSfId)` | Inserts single `Privacy_Audit_Log__c`; insert-only immutability |
| `PrivacyAuditLogger` | `logBulk(entries)` | Bulk DML for multiple audit entries |
| `PrivacyAuditLogger` | `getAuditTrail(contactId)` | Returns all audit entries for a Contact (ordered desc) |

**Flows:**
- `Privacy_Request_Handler_Flow` — `Privacy_Request__c` record-triggered after-save; fires when `Status__c = 'In_Progress'`; decision: `Request_Type__c IN (Erasure, CCPA_Delete)`; calls `PrivacyDeletionController` @InvocableMethod; updates status to Completed or Failed

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Contact` | `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `FirstName` | `FirstName='Deleted'`, `LastName='User {last4}'`, `Email=null`, `Phone=null`, `MailingStreet=null`, `MailingCity=null`, `MailingPostalCode=null`, `DOB_Month__c=null`, `DOB_Day__c=null`, `Pro_License_Number__c=null`, `School_Name__c=null`, `RCC_Card_Number__c=null`, `Epsilon_Profile_Id__c=null` |
| `Order` | `Status__c`, `AccountId` | None (read for gate check only) |
| `Order_Points_Status__c` | `Status__c`, `Contact__c`, `CreatedDate` | None |
| `Privacy_Request__c` | `OneTrust_Request_Id__c` | `Contact__c`, `Status__c`, `Request_Type__c`, `Requested_At__c` |
| `Privacy_Audit_Log__c` | `Action__c`, `Detail__c`, `Performed_At__c` | `Privacy_Request__c` (MD), `Action__c`, `Detail__c`, `Performed_At__c` |

**Permission Sets:**
- `Loyalty_Integration_User` — required for OneTrust REST callin (Connected App)
- `Loyalty_Admin` — for agent-initiated flow path

## API Integration
| Operation | Endpoint | Method | Request | Response |
|---|---|---|---|---|
| Receive deletion request | `/services/apexrest/privacy/delete/` | POST | `{contactId, requestId, requestType:'DELETION'}` | `{status, systemsUpdated, timestamp}` |
| Cancel voucher (LC) | `/program-processes/Cancel%20Voucher` | POST | `{voucherCode, reason:'PRIVACY_REQUEST'}` | 200 OK |
| Unenroll member (LC) | `/program-processes/Unenroll%20Member` | POST | `{memberId: lpmId, reason:'PRIVACY_REQUEST'}` | 200 OK |
| Get member vouchers (LC) | `/member-vouchers?memberId={lpmId}` | GET | — | `List<{voucherCode, status}>` |

## Execution Sequence
```
OneTrust → POST /services/apexrest/privacy/delete/
{contactId: '003XXX', requestId: 'onetrust-uuid-1234', requestType: 'DELETION'}

1. PrivacyDeletionAPIController.doDelete()
2.   → validate: contactId, requestId not blank; requestType == 'DELETION'
3.   → PrivacyDeletionService.processPrivacyRequest('003XXX', 'OneTrust', 'onetrust-uuid-1234')

4. Gate 1: Open order check
   → SOQL: Order WHERE AccountId IN (SELECT AccountId FROM Contact WHERE Id='003XXX')
     AND Status NOT IN ('Delivered','Cancelled','Failed')
   → if found: throw LoyaltyAPIException(409, 'Cannot process deletion: Contact has N open orders')

5. SOQL: Contact WHERE Id='003XXX' → {Has_Loyalty__c, Loyalty_Member_Id__c, FirstName}

── PHASE 1: All callouts ────────────────────────────────────────────────
6. Gate 2: Cancel unredeemed vouchers
   → LoyaltyVoucherService.getMemberVouchers(lpmId) → List<VoucherDTO>
   → for each v where v.isActive():
       LoyaltyVoucherService.cancelVoucher(v.voucherCode, 'PRIVACY_REQUEST')
       → if LoyaltyVoucherException: WARN debug; continue

7. Gate 3: Unenroll from Loyalty Cloud
   → LoyaltyMemberService.unenrollMember(lpmId, 'PRIVACY_REQUEST')
   → POST /program-processes/Unenroll%20Member {memberId, reason}
   → 200 OK

── PHASE 2: All DML ─────────────────────────────────────────────────────
8. Gate 4: Deactivate Contact
   → deactivateContact('003XXX')
   → Contact update: FirstName='Deleted', LastName='User 3XXX', Email=null, Phone=null, [8 more PII fields]=null

9. ensurePrivacyRequest('003XXX', 'onetrust-uuid-1234')
   → SOQL: Privacy_Request__c WHERE OneTrust_Request_Id__c = 'onetrust-uuid-1234'
   → if existing: return existing.Id
   → else: insert Privacy_Request__c{Contact__c, OneTrust_Request_Id__c, Status__c='In_Progress', ...}

10. auditLogger.log(contactId, 'Vouchers_Cancelled', 'OneTrust', requestId, privacyRequestSfId)
    auditLogger.log(contactId, 'LC_Unenrolled', 'OneTrust', requestId, privacyRequestSfId)
    auditLogger.log(contactId, 'Contact_Anonymised', 'OneTrust', requestId, privacyRequestSfId)
    insert Privacy_Audit_Log__c{Action='Request_Completed', Detail='...systems:SFSC;LoyaltyCloud'}

11. → HTTP 200 {"status":"SUCCESS", "systemsUpdated":["LoyaltyCloud","SFSC"], "timestamp":"..."}
```

## Manual Setup Required
- Connected App for OneTrust OAuth 2.0 client credentials; provide `token_endpoint` + `client_id` + `client_secret` to OneTrust
- OneTrust webhook configuration: endpoint = `POST https://{org}.salesforce.com/services/apexrest/privacy/delete/`
- `Loyalty_Integration_User` permission set with access to `PrivacyDeletionAPIController` class
- `Privacy_Request__c` and `Privacy_Audit_Log__c` custom objects deployed
- `Privacy_Request_Handler_Flow` activated in the org
- OneTrust IP ranges allowlisted on the Connected App (optional but recommended)
- Audit log retention policy: records must be kept 7 years; implement a scheduled batch to archive (not delete) `Privacy_Audit_Log__c` records older than 7 years

## Error Handling
| Error | Handling |
|---|---|
| Open order exists | `LoyaltyAPIException(409)` → HTTP 422 `{"status":"ERROR","message":"Contact has N in-progress order(s)"}` |
| `requestType != 'DELETION'` | HTTP 400 `{"error":"requestType must be DELETION"}` |
| `contactId` not found in SOQL | `QueryException` propagates; HTTP 500 |
| `cancelVoucher` fails for one voucher | `LoyaltyVoucherException` caught; logged; loop continues |
| `unenrollMember` fails | Exception propagates from Phase 1 → HTTP 500 (no DML has occurred yet) |
| `deactivateContact` DML fails | Exception propagates; audit log not written; HTTP 500 |
| `ensurePrivacyRequest` SOQL fails | Exception propagates; HTTP 500 |
| Contact not loyalty-enrolled | `hasLoyalty=false` → Phase 1 callouts skipped; only Contact PII cleared |

## Security
- `PrivacyDeletionAPIController` — `global without sharing` (must see all Contacts regardless of sharing)
- `PrivacyDeletionService` — `without sharing` (same reason; operates on behalf of privacy law, not agent)
- `PrivacyAuditLogger` — `with sharing` (audit reads restricted to agents with visibility)
- `PrivacyDeletionController` — `with sharing` (flow-triggered; agent context)
- Audit logs are insert-only — no `update` or `delete` Apex methods exist; immutability by design

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Full deletion — enrolled member | Valid `contactId`, loyalty member, no open orders | Vouchers cancelled; LC unenrolled; Contact PII cleared; 3 audit log entries + 1 summary |
| Non-loyalty member | `Has_Loyalty__c=false` | Phase 1 skipped; Contact PII cleared; 1 audit entry (Contact_Anonymised) |
| Open order blocks deletion | Contact with in-progress Order | HTTP 422; no changes made |
| Voucher cancel fails | One of two vouchers returns error | Error logged; second voucher attempted; deletion continues |
| Duplicate request (same `requestId`) | Same OneTrust request sent twice | `ensurePrivacyRequest` finds existing `Privacy_Request__c`; audit re-logged but no duplicate record |
| Flow-triggered path | `Privacy_Request__c.Status__c='In_Progress'`, `Request_Type__c='Erasure'` | `PrivacyDeletionController` called; status updated to `Completed` |
| Wrong requestType | `requestType='EXPORT'` | HTTP 400 |

## Validation Queries
```sql
-- Privacy requests and their status
SELECT Id, Contact__c, Status__c, Request_Type__c, OneTrust_Request_Id__c, Requested_At__c
FROM Privacy_Request__c ORDER BY Requested_At__c DESC LIMIT 20

-- Audit trail for a specific contact
SELECT Action__c, Detail__c, Performed_At__c
FROM Privacy_Audit_Log__c
WHERE Privacy_Request__c IN (
  SELECT Id FROM Privacy_Request__c WHERE Contact__c = '<contactId>'
)
ORDER BY Performed_At__c DESC

-- Contacts that have been anonymised (FirstName='Deleted')
SELECT Id, FirstName, LastName, Has_Loyalty__c, Loyalty_Member_Id__c
FROM Contact WHERE FirstName = 'Deleted'

-- Open orders that would block deletion
SELECT Id, Status__c, AccountId FROM Order
WHERE Status__c NOT IN ('Delivered','Cancelled','Failed') LIMIT 20
```

## Dependencies
- `LoyaltyVoucherService.cancelVoucher` — shared with stories 1.20, 1.25
- `LoyaltyMemberService.unenrollMember` — used only by this story
- Story 1.7 — `LoyaltySessionCacheService` not called here; cache invalidation after deletion is a known gap
- `Privacy_Request__c` and `Privacy_Audit_Log__c` custom objects must be deployed
- Named Credential `Loyalty_Cloud_API` configured

## Known Gaps
- **No session cache invalidation**: after `deactivateContact`, `LoyaltySessionCacheService` still holds stale data for this Contact for up to 30 minutes; `refreshMemberData` is not called in the deletion workflow
- **`PrivacyDeletionService.unenrollMember` relies on `LoyaltyMemberService.unenrollMember`**: this method is not shown in the service class source in this repo — assumed to exist; must verify implementation
- **Audit log retention batch not implemented**: the class comments state records must be kept 7 years and archived to external storage, but no `PrivacyAuditRetentionBatch` class exists
- **`flagDuplicate` stub in `DeduplicationService`**: referenced as part of the privacy/dedup workflow but unimplemented
- **Transaction journals retained in LC**: the deletion service does not call any LC API to anonymise TJ records — member's purchase history remains in LC with the LPM ID; this may conflict with strict GDPR Article 17 interpretations
- **Flow status update**: `Privacy_Request_Handler_Flow` is responsible for updating `Status__c` to `Completed`/`Failed`, but the `PrivacyDeletionController` @InvocableMethod does not return a status to the flow — the flow must handle success/failure via fault paths
