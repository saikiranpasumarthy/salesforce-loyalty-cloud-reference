# STORY-1.2 — Existing User Enrollment

**RICEF ID:** 1.2 | **Type:** UI | **Complexity:** Medium | **Module:** SFSC, LC

## Business Purpose
Allow an authenticated SFSC Contact (who already has an account but no LPM) to join the loyalty program via a "Join Rewards" CTA on the Rewards page.

## Assumptions
- Contact already exists in SFSC (`Id` is known from authenticated session)
- Contact does not yet have `Has_Loyalty__c = true`
- Member type defaults to `Retail` unless overridden via `@api memberType` property
- No new Contact creation needed — only LPM creation and Contact field update
- Duplicate LPM guard: throws `DUPLICATE_MEMBER` if Contact already enrolled

## User Flow
1. Authenticated user views Rewards page → `loyaltyJoinCta` component renders (visible only when `Has_Loyalty__c = false`)
2. User clicks "Join Rewards" button
3. LWC calls `LoyaltyEnrollmentController.enrollMember(recordId, memberType)`
4. Service checks `Has_Loyalty__c` on Contact — throws if already enrolled
5. LC API called → LPM created
6. Contact updated with loyalty fields
7. `Loyalty_Enrollment_Event__e` published → welcome email triggered
8. LWC fires `refreshView` standard event; `loyaltyJoinCta` hides

## Components

**LWC:**
- `loyaltyJoinCta` — Single "Join Rewards" button; wire adapter reads `Contact.Has_Loyalty__c`; self-hides when true; calls `enrollMember` on click; fires `refreshView` on success

**Apex:**
| Class | Method | Description |
|---|---|---|
| `LoyaltyEnrollmentController` | `enrollMember(contactId, memberType)` | `@AuraEnabled`; routes to `enrollExistingMember` when Contact already has Id |
| `LoyaltyEnrollmentService` | `enrollExistingMember(contactId, memberType)` | Queries Contact; guards duplicate; builds enrollment request from Contact fields; calls LC API |
| `LoyaltyEnrollmentService` | `buildEnrollmentRequest(c, memberType)` | Constructs `EnrollmentRequest` from Contact + CMDT config |

**Flows:**
- `Welcome_Email_Trigger_Flow` — same as story 1.1; triggered by `Loyalty_Enrollment_Event__e`

**Platform Events:**
- `Loyalty_Enrollment_Event__e` — Published by `LoyaltyEnrollmentService.publishEnrollmentEvent()`; consumed by `Welcome_Email_Trigger_Flow`

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Contact` | `Id`, `FirstName`, `LastName`, `Email`, `Phone`, `Has_Loyalty__c`, `Loyalty_Member_Id__c` | `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `Loyalty_Member_Type__c` |

**Custom Metadata:**
- `Loyalty_Program_Config__mdt` — record `Default`; `Program_API_Name__c` used in request

**Permission Sets:**
- `Loyalty_Agent` — minimum to see and use the CTA on Contact records

## API Integration
| Field | Value |
|---|---|
| **Endpoint** | `POST /connect/loyalty/programs/{name}/individual-member-enrollments` |
| **Request fields** | `memberStatus=Active`, `memberType`, `loyaltyProgramName`, `enrollmentDate`, `contactDetails.{firstName, lastName, email, phone}` |
| **Response fields** | `loyaltyProgramMember.id`, `loyaltyProgramMember.membershipNumber`, `loyaltyProgramMember.currentTierName` |

## Execution Sequence
```
1. LWC: loyaltyJoinCta.handleJoinClick()
2. @AuraEnabled: LoyaltyEnrollmentController.enrollMember(recordId, memberType)
3. LoyaltyEnrollmentService.enrollExistingMember(contactId, memberType)
4.   → SOQL: Contact WHERE Id = :contactId (read fields)
5.   → if Has_Loyalty__c == true → throw LoyaltyEnrollmentException(DUPLICATE_MEMBER)
6.   → buildEnrollmentRequest(c, memberType)
7.     → SOQL: Loyalty_Program_Config__mdt WHERE DeveloperName = 'Default'
8.   → callEnrollmentAPI(req) → LoyaltyAPIClient.post('/individual-member-enrollments')
9.   → updateContactLoyaltyFields(contactId, lpmId, loyaltyId, memberType, req) → DML update Contact
10.  → publishEnrollmentEvent(contactId, lpmId, ...) → EventBus.publish(Loyalty_Enrollment_Event__e)
11.  → return EnrollmentResponse.ok(...)
12. LWC: success toast; fireEvent('refreshView') → Contact page refreshes
13. Wire adapter re-reads Has_Loyalty__c = true → loyaltyJoinCta re-renders as null/hidden
```

## Manual Setup Required
- `loyaltyJoinCta` placed on Contact Record Page in App Builder
- App Builder component visibility rule: `Contact.Has_Loyalty__c equals false` (prevents rendering for enrolled members)
- `Welcome_Email_Trigger_Flow` activated
- `Loyalty_Agent` permission set assigned to agents

## Error Handling
| Error | Source | Surfaced as |
|---|---|---|
| Already enrolled | `LoyaltyEnrollmentException(DUPLICATE_MEMBER)` | AuraHandledException → toast "Already enrolled" |
| LC API failure | `LoyaltyAPIException` | AuraHandledException → toast with message |
| Contact not found | SOQL returns empty | Null pointer → generic AuraHandledException |

## Security
- `LoyaltyEnrollmentController` — `with sharing`
- `LoyaltyEnrollmentService` — `with sharing`
- Wire adapter reads `Contact.Has_Loyalty__c` — FLS: agent needs Read on `Has_Loyalty__c` (covered by `Loyalty_Agent` permission set)
- No admin-only gate — `Loyalty_Agent` sufficient

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Happy path | Unenrolled Contact Id, memberType=Retail | Contact enrolled; `Has_Loyalty__c=true`; CTA hides |
| Already enrolled | Contact with `Has_Loyalty__c=true` | `DUPLICATE_MEMBER` exception; no LC call |
| Contact has no email | Contact with null Email | LC API called with null email; LC may reject → `LoyaltyAPIException` |
| LC returns 400 | Bad request to LC | AuraHandledException; Contact NOT updated |
| memberType = Pro | Contact Id, memberType=Pro | Contact.Loyalty_Member_Type__c = 'Pro' after |

## Validation Queries
```sql
-- Verify enrollment
SELECT Has_Loyalty__c, Loyalty_Member_Id__c, Loyalty_Member_Type__c
FROM Contact WHERE Id = '<contactId>'

-- Confirm CTA should hide (enrolled)
SELECT Has_Loyalty__c FROM Contact WHERE Has_Loyalty__c = true AND Id = '<contactId>'

-- Enrollment event fired
SELECT Contact_Id__c, Member_Type__c, Enrolled_At__c
FROM Loyalty_Enrollment_Event__e LIMIT 5
```

## Dependencies
- Story 1.1 shares `LoyaltyEnrollmentService` and `ContactMatchService` — both must be deployed
- `Loyalty_Program_Config__mdt` Default record must exist
- Named Credential `Loyalty_Cloud_API` configured

## Known Gaps
- **`loyaltyJoinCta` does not have a member type selector** — defaults to `Retail` unless admin sets `@api memberType` property in App Builder; no in-UI type selection for the end user
- **No phone-based duplicate check** at this entry point — only `Has_Loyalty__c` field check on the Contact itself
- **`enrollExistingMember` vs `enrollNewMember`**: routing decision (which method to call) is implicit in the controller; if `contactId` is null, controller falls through to `enrollNewMember` path
