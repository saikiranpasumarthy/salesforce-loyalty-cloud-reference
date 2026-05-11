# STORY-1.3 — Enrollment via Event Registration (Epsilon Attribution)

**RICEF ID:** 1.3 | **Type:** API | **Complexity:** Medium | **Module:** SFSC, LC

## Business Purpose
When a member enrolls or updates their loyalty profile through an event registration channel (e.g., in-store event sign-up, partner portal), attribute the enrollment to an Epsilon campaign by populating `Epsilon_Profile_Id__c` on the Contact — enabling cross-channel engagement tracking and post-enrollment personalization.

## Assumptions
- Story 1.3 uses the same `LoyaltyEnrollmentService.enrollNewMember` code path as story 1.1, with the addition of an `epsilonProfileId` on the `EnrollmentRequest`
- `EnrollmentRequest.epsilonProfileId` is passed from the event registration form to `updateContactLoyaltyFields` → stored on `Contact.Epsilon_Profile_Id__c`
- If `epsilonProfileId` is null/blank, the field is not set — all other enrollment behavior is identical to story 1.1
- `ContactMatchService` checks `Epsilon_Profile_Id__c` in `mergeConsiderations` conflict detection but does not use it as a match identifier
- No separate enrollment endpoint exists for event registration — the same `POST /individual-member-enrollments` LC API is used
- `Welcome_Email_Trigger_Flow` fires on the `Loyalty_Enrollment_Event__e` regardless of enrollment channel — event registrants also receive the welcome email

## User Flow
1. Member attends an in-store event or partner portal → fills in event registration form
2. Registration form collects name, email, optional DOB, and Epsilon Profile ID from attribution tracking
3. `LoyaltyEnrollmentController.enrollMember(req)` called with `req.epsilonProfileId` set
4. `LoyaltyEnrollmentService.enrollNewMember(req)` runs the full new member flow:
   - Email validation → duplicate check → `ContactMatchService.matchOrCreateContact`
   - LC enrollment API → `updateContactLoyaltyFields` (sets `Epsilon_Profile_Id__c`)
   - Publish `Loyalty_Enrollment_Event__e`
5. Welcome email sent via `Welcome_Email_Trigger_Flow`
6. Epsilon system can now attribute the member's activity to the event campaign using `Epsilon_Profile_Id__c`

## Components

**LWC:**
- `loyaltyEnrollmentForm` — same component as story 1.1; must include a field for Epsilon Profile ID if used in event registration context (not confirmed in current LWC source)

**Apex:**
| Class | Method | Description |
|---|---|---|
| `LoyaltyEnrollmentController` | `enrollMember(req)` | `@AuraEnabled`; calls `enrollNewMember(req)`; same as story 1.1 |
| `LoyaltyEnrollmentService` | `enrollNewMember(req)` | Full enrollment flow; `req.epsilonProfileId` passed through to `updateContactLoyaltyFields` |
| `LoyaltyEnrollmentService` | `updateContactLoyaltyFields(contactId, lpmId, memberType, req)` | Sets `Epsilon_Profile_Id__c = req.epsilonProfileId` when non-blank |
| `ContactMatchService` | `matchOrCreateContact(dto)` | Same as story 1.1; Epsilon ID not used as match identifier but preserved on create |

**Flows:**
- `Welcome_Email_Trigger_Flow` — fires on `Loyalty_Enrollment_Event__e`; channel-agnostic

**Platform Events:**
- `Loyalty_Enrollment_Event__e` — published at enrollment completion; triggers welcome email

**Objects/Fields:**
| Object | Fields Read | Fields Written |
|---|---|---|
| `Contact` | `Email`, `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `Epsilon_Profile_Id__c` | `Epsilon_Profile_Id__c`, `Has_Loyalty__c`, `Loyalty_Member_Id__c`, `Loyalty_Member_Type__c` |

**Custom Metadata:**
- `Loyalty_Program_Config__mdt` — Default record; `Program_API_Name__c`, `Max_Enrollments_Per_Day__c`

**Permission Sets:**
- `Loyalty_Agent` — same as story 1.1

## API Integration
| Operation | Endpoint | Method | Key Request Fields | Key Response Fields |
|---|---|---|---|---|
| Enroll member | `/individual-member-enrollments` | POST | `contactDetails`, `memberType`, `enrollmentDate`, `epsilonProfileId` (if accepted by LC) | `loyaltyProgramMemberId`, `membershipNumber` |

## Execution Sequence
```
1. Event registration form → LoyaltyEnrollmentController.enrollMember(req)
   req = {firstName, lastName, email, memberType='Retail', epsilonProfileId='EPS-12345', channel='Event'}

2. LoyaltyEnrollmentService.enrollNewMember(req)
3.   → validateEnrollmentRequest(req) — email format, not blank
4.   → isDuplicateEnrollment(req.email) — SOQL Contact WHERE Email=:req.email AND Has_Loyalty__c=true
         → if true: throw LoyaltyEnrollmentException('Already enrolled')
5.   → ContactMatchService.matchOrCreateContact(req) → contactId
6.   → callEnrollmentAPI(req, contactId) → EnrollmentResponse{lpmId, membershipNumber}
        → POST /individual-member-enrollments {contactDetails, memberType, enrollmentDate}
7.   → updateContactLoyaltyFields(contactId, lpmId, memberType, req)
        → Contact update: Has_Loyalty__c=true, Loyalty_Member_Id__c=lpmId, Loyalty_Member_Type__c=memberType
        → if req.epsilonProfileId != null: Epsilon_Profile_Id__c = 'EPS-12345'
8.   → publishEnrollmentEvent(contactId, lpmId, req.firstName, memberType)
        → EventBus.publish(Loyalty_Enrollment_Event__e{...})

9. Welcome_Email_Trigger_Flow fires → welcome email sent to member
```

## Manual Setup Required
- Same as story 1.1 (Named Credential, `Loyalty_Program_Config__mdt`, permission sets)
- If `loyaltyEnrollmentForm` is used for event registration context, the `epsilonProfileId` input field must be added to the component (not currently in source)
- Epsilon integration team must configure attribution tracking to pass profile IDs to the enrollment form

## Error Handling
| Error | Handling |
|---|---|
| `epsilonProfileId` blank | Field not set on Contact; rest of enrollment proceeds normally |
| Already enrolled with same email | `LoyaltyEnrollmentException('Already enrolled')` thrown; handled as in story 1.1 |
| LC enrollment API fails | `LoyaltyAPIException` propagates; `AuraHandledException` to LWC |
| Epsilon profile ID too long | DML exception if `Epsilon_Profile_Id__c` field length exceeded; not explicitly handled |

## Security
- Same as story 1.1: `LoyaltyEnrollmentController` and `LoyaltyEnrollmentService` — `with sharing`
- `Epsilon_Profile_Id__c` is an external attribution ID; not PII in itself, but stored on the Contact record
- Privacy deletion (story 3.1) clears `Epsilon_Profile_Id__c` as part of Contact deactivation

## Test Scenarios
| Scenario | Input | Expected Result |
|---|---|---|
| Event enrollment with Epsilon ID | `epsilonProfileId = 'EPS-12345'` | Contact created/updated with `Epsilon_Profile_Id__c = 'EPS-12345'`; enrolled in LC |
| Event enrollment without Epsilon ID | `epsilonProfileId = null` | Enrollment succeeds; `Epsilon_Profile_Id__c` not set |
| Duplicate enrollment | Same email already enrolled | `LoyaltyEnrollmentException`; enrollment blocked |
| Contact already exists (match) | Email matches existing non-loyalty Contact | Existing Contact updated; LC enrollment called |

## Validation Queries
```sql
-- Members enrolled via Epsilon attribution
SELECT Id, Email, Has_Loyalty__c, Epsilon_Profile_Id__c, Loyalty_Member_Id__c
FROM Contact WHERE Epsilon_Profile_Id__c != null AND Has_Loyalty__c = true LIMIT 20

-- Recent enrollments without Epsilon attribution (for attribution gap analysis)
SELECT Id, CreatedDate, Loyalty_Member_Id__c
FROM Contact WHERE Has_Loyalty__c = true AND Epsilon_Profile_Id__c = null
AND CreatedDate = LAST_N_DAYS:30

-- Contacts with Epsilon IDs cleared by privacy deletion
SELECT Id, FirstName, Epsilon_Profile_Id__c FROM Contact
WHERE FirstName = 'Deleted' AND Loyalty_Member_Id__c != null
```

## Dependencies
- Story 1.1 — all base enrollment logic; story 1.3 is a thin extension
- Story 3.1 — `deactivateContact` clears `Epsilon_Profile_Id__c` on deletion
- Epsilon system integration: profile IDs must be generated and passed at event registration time

## Known Gaps
- **`loyaltyEnrollmentForm` LWC has no Epsilon Profile ID field**: the LWC source does not include an input for `epsilonProfileId`; event registration forms would need to either extend this component or call the Apex controller directly
- **`epsilonProfileId` not sent to LC API**: `callEnrollmentAPI` builds the LC payload from `contactDetails`, `memberType`, and `enrollmentDate`; if Epsilon Profile ID needs to be stored in LC (not just SFSC), the payload must be extended
- **No validation on Epsilon Profile ID format**: any string is accepted; the format (`EPS-XXXXX` or UUID etc.) is not validated in Apex
