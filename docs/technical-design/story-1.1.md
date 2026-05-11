# STORY-1.1 — New Account Enrollment

**RICEF ID:** 1.1 | **Type:** UI | **Complexity:** Complex | **Module:** SFSC, LC

## Business Purpose
Create a new SFSC Contact and simultaneously enroll them in the Loyalty Cloud program, publishing a welcome email trigger on success.

## Assumptions
- The registering user does not have an existing SFSC Contact
- Email uniqueness is validated before LC API is called
- `Loyalty_Program_Config__mdt` record `Default` exists with `Program_API_Name__c = 'LevelUp'`
- Named Credential `Loyalty_Cloud_API` is configured with OAuth 2.0
- Member type is one of: `Retail`, `Pro`, `Student`
- DOB is optional; Pro license and school name are type-specific optional fields
- Experian email verification is referenced in RICEF but not implemented in current codebase

## User Flow
1. Agent/customer opens enrollment form → `loyaltyEnrollmentForm` renders
2. Agent enters: first name, last name, email, phone, member type (+ DOB, license/school for Pro/Student)
3. On email field blur → `checkEmailExists(email)` fires; if duplicate + already enrolled → inline error shown
4. Agent clicks Submit → LWC calls `enrollMember(contactId, memberType)`
5. Service calls `ContactMatchService.matchOrCreateContact(dto)` → Contact found or created
6. LC API called → `POST /individual-member-enrollments` → LPM created
7. Contact updated: `Has_Loyalty__c = true`, `Loyalty_Member_Id__c`, `Loyalty_Member_Type__c`
8. `Loyalty_Enrollment_Event__e` published → `Welcome_Email_Trigger_Flow` sends email
9. LWC shows success toast with member ID; form resets

## Components

**LWC:**
- `loyaltyEnrollmentForm` — Registration form; calls `checkEmailExists` on blur, `enrollMember` on submit; renders inline duplicate error and success toast

**Apex:**
| Class | Method | Description |
|---|---|---|
| `LoyaltyEnrollmentController` | `enrollMember(contactId, memberType)` | `@AuraEnabled` entry point; delegates to service |
| `LoyaltyEnrollmentController` | `checkEmailExists(email)` | `@AuraEnabled(cacheable=true)` duplicate check |
| `LoyaltyEnrollmentService` | `enrollNewMember(req)` | Validates, match/creates Contact, calls LC API, updates Contact, publishes event |
| `LoyaltyEnrollmentService` | `checkDuplicateMember(email, phone)` | Throws `LoyaltyEnrollmentException(DUPLICATE_MEMBER)` if enrolled Contact found |
| `ContactMatchService` | `matchOrCreateContact(dto)` | Match by email → phone → loyaltyId → epsilon → create new; returns Contact Id |
| `ContactMatchService` | `findContactByEmail(email)` | Email-only lookup returning full Contact with `Has_Loyalty__c` |

**Flows:**
- `Welcome_Email_Trigger_Flow` — Trigger: `Loyalty_Enrollment_Event__e` platform event; Action: queries Contact for email + first name, calls `emailSimple` to send welcome email with LPM ID and program name

**Platform Events:**
- `Loyalty_Enrollment_Event__e` — Published by `LoyaltyEnrollmentService.publishEnrollmentEvent()`; consumed by `Welcome_Email_Trigger_Flow`

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Contact` | `Email`, `Phone`, `Has_Loyalty__c`, `Loyalty_Member_Id__c` | `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `Loyalty_Member_Type__c`, `DOB_Month__c`, `DOB_Day__c`, `Pro_License_Number__c`, `Pro_License_Expiry__c`, `School_Name__c`, `Graduation_Date__c` |
| `Loyalty_Enrollment_Event__e` | — | `Contact_Id__c`, `Loyalty_Member_Id__c`, `Member_Type__c`, `Program_Name__c`, `Enrolled_At__c` |

**Custom Metadata:**
- `Loyalty_Program_Config__mdt` — record `Default`; fields used: `Program_API_Name__c`

**Permission Sets:**
- `Loyalty_Agent` — minimum required for agents
- `Loyalty_Admin` — for admin users who also enroll

## API Integration
| Field | Value |
|---|---|
| **Endpoint** | `POST /connect/loyalty/programs/{Program_API_Name__c}/individual-member-enrollments` |
| **Named Credential** | `Loyalty_Cloud_API` |
| **Request fields** | `memberStatus`, `memberType`, `loyaltyProgramName`, `enrollmentDate`, `contactDetails.{firstName, lastName, email, phone}`, optional: `dobMonth`, `dobDay` |
| **Response fields** | `loyaltyProgramMember.id` (lpmId), `loyaltyProgramMember.membershipNumber` (loyaltyId), `loyaltyProgramMember.currentTierName` |

## Execution Sequence
```
1. LWC: loyaltyEnrollmentForm.handleSubmit()
2. @AuraEnabled: LoyaltyEnrollmentController.enrollMember(contactId, memberType)
3. LoyaltyEnrollmentService.enrollNewMember(req)
4.   → req.validate() — throw on blank required fields
5.   → checkDuplicateMember(email, phone)
6.     → ContactMatchService.findContactByEmail(email) — SOQL Contact
7.     → ContactMatchService.findContactByPhone(phone) — SOQL Contact
8.   → ContactMatchService.matchOrCreateContact(dto)
9.     → findBestMatch(dto) — single SOQL: Contact WHERE email OR phone OR loyaltyId OR epsilon
10.    → If found: updateContactFields(c, dto); if changed → DML update Contact
11.    → If not found → DML insert Contact
12.  → callEnrollmentAPI(req) → LoyaltyAPIClient.post('/individual-member-enrollments', payload)
13.    → Named Credential HTTP POST → LC responds {loyaltyProgramMember.id, membershipNumber, tier}
14.  → updateContactLoyaltyFields(contactId, lpmId, ...) → DML update Contact
15.  → publishEnrollmentEvent(...) → EventBus.publish(Loyalty_Enrollment_Event__e)
16.  → return EnrollmentResponse.ok(...)
17. Platform Event fires → Welcome_Email_Trigger_Flow
18.   → SOQL Contact for email + first name
19.   → emailSimple action → Welcome email sent
20. LWC: success toast shown; form reset
```

## Manual Setup Required
- Named Credential `Loyalty_Cloud_API` switched to OAuth 2.0 in Setup
- `loyaltyEnrollmentForm` placed on a Lightning App Page and activated (or Contact record page)
- `Welcome_Email_Trigger_Flow` activated in Setup → Flows
- `Loyalty_Program_Config__mdt` record `Default` has correct `Program_API_Name__c`
- `Loyalty_Agent` or `Loyalty_Admin` permission set assigned to all agents

## Error Handling
| Error | Class | How surfaced |
|---|---|---|
| Duplicate enrolled email | `LoyaltyEnrollmentException(DUPLICATE_MEMBER)` | AuraHandledException → inline LWC error label |
| Duplicate enrolled phone | `LoyaltyEnrollmentException(DUPLICATE_MEMBER)` | AuraHandledException → inline LWC error |
| LC API 4xx/5xx | `LoyaltyAPIException(statusCode)` | AuraHandledException → toast error in LWC |
| LC API timeout / network | `NetworkException` | AuraHandledException → toast "Service unavailable" |
| Missing required field | `LoyaltyEnrollmentException` from `req.validate()` | AuraHandledException → toast |
| Named Credential not OAuth | HTTP 401 from LC | `LoyaltyAPIException(401)` → toast |

## Security
- `LoyaltyEnrollmentController` — `with sharing`; agent must have Read on Contact
- `LoyaltyEnrollmentService` — `with sharing`
- `ContactMatchService` — `with sharing`; cannot access records invisible to running user
- FLS: Contact fields (`Has_Loyalty__c`, `Loyalty_Member_Id__c`, etc.) require Edit permission via `Loyalty_Agent` permission set
- Named Credential OAuth token injected by Salesforce; agent never sees credentials

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Happy path — Retail | New email, phone, memberType=Retail | Contact created; `Has_Loyalty__c=true`; event published; welcome email sent |
| Happy path — Pro | New email + Pro license number | Contact created with `Pro_License_Number__c` set |
| Duplicate email (enrolled) | Email matching enrolled Contact | `LoyaltyEnrollmentException(DUPLICATE_MEMBER)`; no LC call made |
| Duplicate phone (enrolled) | Phone matching enrolled Contact | `LoyaltyEnrollmentException(DUPLICATE_MEMBER)` |
| Email exists but not enrolled | Email of unenrolled Contact | Contact matched; enrollment proceeds (no DUPLICATE error) |
| LC API 500 | LC returns 5xx | `LoyaltyAPIException`; Contact not updated |
| Missing email | `email = null` | `req.validate()` throws; LWC shows validation error |
| Welcome email — no contact email | Contact with null Email | Flow's decision node "No Email — Skip" fires; no email sent; no error |

## Validation Queries
```sql
-- Confirm Contact enrolled correctly
SELECT Has_Loyalty__c, Loyalty_Member_Id__c, Loyalty_Member_Type__c
FROM Contact WHERE Email = 'test@example.com'

-- Confirm enrollment event was published (within minutes)
SELECT Contact_Id__c, Loyalty_Member_Id__c, Member_Type__c, Enrolled_At__c
FROM Loyalty_Enrollment_Event__e LIMIT 10

-- Confirm no duplicate LPM IDs
SELECT Loyalty_Member_Id__c, COUNT(Id) cnt FROM Contact
WHERE Loyalty_Member_Id__c != null GROUP BY Loyalty_Member_Id__c HAVING COUNT(Id) > 1

-- Confirm contact fields written
SELECT Id, Has_Loyalty__c, DOB_Month__c, Pro_License_Number__c
FROM Contact WHERE Has_Loyalty__c = true AND CreatedDate = TODAY
```

## Dependencies
- Named Credential `Loyalty_Cloud_API` configured (infra)
- `Loyalty_Program_Config__mdt` record `Default` deployed
- `Loyalty_Enrollment_Event__e` platform event object deployed
- `Welcome_Email_Trigger_Flow` deployed and activated

## Known Gaps
- **Experian email verification** (RICEF comment): Not implemented — no external Experian API call in codebase; enrollment proceeds with any email format
- **`enrollmentSource` field** on `EnrollmentRequest` populated as `'SERVICE_CLOUD'` when called from controller; event registration source (`'EVENT_REG'`) not wired to a separate form
- **DOB validation**: `req.dobMonth` / `req.dobDay` accepted but no range validation (month 1-12, day 1-31)
- **LWC duplicate check** calls `checkEmailExists` not `checkDuplicateMember`; phone-duplicate check only happens inside the service on submit (not on phone field blur)
