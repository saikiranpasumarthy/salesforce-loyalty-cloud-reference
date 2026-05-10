# Data Model

## Custom Objects

### Contact (extended)

Standard Salesforce Contact with the following custom fields:

| Field | Type | Purpose |
|---|---|---|
| `Has_Loyalty__c` | Checkbox | True when the Contact has an active LC membership |
| `Loyalty_Member_Id__c` | Text(50), ExternalId, Unique | Loyalty Cloud member identifier |
| `Loyalty_Member_Type__c` | Picklist (Retail/Pro/Student) | Membership segment |
| `RCC_Active__c` | Checkbox | True when an RCC card is linked |
| `RCC_Card_Number__c` | Text(30), ExternalId, Unique | Physical RCC barcode |
| `Country_Code__c` | Text(2) | ISO 3166-1 alpha-2 — drives GDPR/CCPA/PIPEDA jurisdiction |
| `DOB_Month__c` | Number(2) | Birth month for birthday promotions |
| `DOB_Day__c` | Number(2) | Birth day for birthday promotions |
| `Pro_License_Number__c` | Text(50) | Pro-tier professional licence |
| `Pro_License_Expiry__c` | Date | Pro membership expires after this date |
| `School_Name__c` | Text(120) | Student-tier educational institution |
| `Graduation_Date__c` | Date | Student membership expires after this date |
| `Epsilon_Profile_Id__c` | Text(50), ExternalId, Unique | Epsilon CRM identifier for deduplication |

---

### RCC_Import_Record__c

Staging table for RCC card batch imports. One record per row in the uploaded CSV file.

| Field | Type | Notes |
|---|---|---|
| Name | AutoNumber (RCC-{N}) | Auto-assigned |
| `Card_Number__c` | Text(30) | Required |
| `Contact__c` | Lookup(Contact) | Null until contact-match phase |
| `Email__c` | Email | From CSV |
| `Member_Type__c` | Text(20) | From CSV |
| `Status__c` | Picklist | Pending → Matched → Enrolled / Failed / Duplicate |
| `Error_Message__c` | LongTextArea | Set on failure |
| `Batch_Job_Id__c` | Text(18) | AsyncApexJob Id |

---

### Batch_Run_Log__c

Audit record written by batch `finish()` methods. One record per batch execution.

| Field | Type | Notes |
|---|---|---|
| Name | AutoNumber (BRL-{N}) | Auto-assigned |
| `Batch_Type__c` | Picklist | RCC_Card_Import / Points_Expiry / Tier_Recalculation |
| `Total_Processed__c` | Number | Count of scope records |
| `Total_Succeeded__c` | Number | |
| `Total_Failed__c` | Number | |
| `Completed_At__c` | DateTime | finish() timestamp |
| `Error_Summary__c` | LongTextArea | First N errors from `BatchStats.errors` |
| `Apex_Job_Id__c` | Text(18) | AsyncApexJob Id |

---

### Order_Points_Status__c

Tracks qualifying-purchase points per order. Used by `PointsExpiryService` to determine the CA exception (qualifying purchase within 365 days prevents expiry).

| Field | Type | Notes |
|---|---|---|
| Name | AutoNumber (OPS-{N}) | Auto-assigned |
| `Contact__c` | Lookup(Contact) | |
| `Order_Id__c` | Text(50), ExternalId, Unique | External order reference |
| `Status__c` | Picklist | Pending → Awarded / Cancelled / Expired |
| `Order_Date__c` | Date | |
| `Points_Awarded__c` | Number(12,2) | |

---

### Privacy_Request__c

Represents a GDPR Article 17 erasure, CCPA deletion, or access request.

| Field | Type | Notes |
|---|---|---|
| Name | AutoNumber (PRQ-{N}) | Auto-assigned |
| `Contact__c` | Lookup(Contact) | Cleared after anonymisation |
| `Request_Type__c` | Picklist | Erasure / CCPA_Delete / Access / Portability |
| `Status__c` | Picklist | New → In_Progress → Completed / Failed / Blocked |
| `Jurisdiction__c` | Picklist | GDPR / CCPA / PIPEDA / Other |
| `Requested_At__c` | DateTime | From OneTrust webhook payload |
| `Completed_At__c` | DateTime | Set by flow on completion |
| `OneTrust_Request_Id__c` | Text(100), ExternalId, Unique | Idempotency key |

---

### Privacy_Audit_Log__c (child of Privacy_Request__c)

Immutable audit trail. One record per step of the 4-gate deletion process.

| Field | Type | Notes |
|---|---|---|
| Name | AutoNumber (PAL-{N}) | Auto-assigned |
| `Privacy_Request__c` | MasterDetail | Parent — cascade-delete with request |
| `Action__c` | Picklist | Open_Orders_Check / Vouchers_Cancelled / LC_Unenrolled / Contact_Anonymised / Request_Completed / Request_Failed |
| `Detail__c` | LongTextArea | Free-text detail |
| `Performed_At__c` | DateTime | |

---

## Custom Metadata Types

### Loyalty_Program_Config__mdt

Program-level configuration. Queried by `LoyaltyEnrollmentService` and `PointsExpiryService`.

| Field | Purpose |
|---|---|
| `Program_API_Name__c` | LC endpoint segment: `/connect/loyalty/programs/{name}/...` |
| `Currency_ISO_Code__c` | ISO 4217 code for transaction journals |
| `Max_Enrollments_Per_Day__c` | Soft daily enrollment cap (warning, not block) |
| `Points_Expiry_Days__c` | Inactivity window before expiry |
| `Is_Active__c` | Inactive programs reject enrollments |

**Records shipped:** `Default_Program` (USD), `CA_Program` (CAD)

---

### Loyalty_Exclusion_Rule__mdt

Cart-line exclusion rules. Queried (and lazy-cached) by `LoyaltyCartEvaluationService`.

| Field | Purpose |
|---|---|
| `Rule_Type__c` | Category / SKU / Brand |
| `Rule_Value__c` | Case-insensitive match value |
| `Program_Config__c` | Optional program scope (blank = all programs) |
| `Is_Active__c` | Inactive rules are skipped |

**Records shipped:** Exclude_Gift_Cards (SKU=GIFTCARD), Exclude_Tobacco, Exclude_Fuel (Category), Exclude_Generic_Brand (Brand)

---

### Tier_Mapping__mdt

Legacy code → canonical tier name. Queried and cached by `TierMappingService`.

| Field | Purpose |
|---|---|
| `Legacy_Code__c` | External tier code (e.g., "Upper", "Pro_Elite") |
| `Canonical_Tier__c` | LC tier name (e.g., "Elite", "Preferred") |
| `Member_Type__c` | Retail / Pro / Student (blank = all) |
| `Sort_Order__c` | Numeric rank for tier progression |

**Records shipped:** Upper (Elite/Retail), Base (Preferred/Retail), Conversion (Preferred/Retail), Pro_Elite (Elite/Pro), Student_Elite (Elite/Student), Pro_Preferred (Preferred/Pro), Student_Preferred (Preferred/Student), Not_Converted (Member/Retail)

---

## Platform Events

### Loyalty_Enrollment_Event__e (HighVolume, PublishAfterCommit)

Published by `LoyaltyEnrollmentService` after successful enrollment. Consumed by `Welcome_Email_Trigger_Flow` and any downstream Epsilon/CDP integrations.

| Field | Type |
|---|---|
| `Contact_Id__c` | Text(18) |
| `Loyalty_Member_Id__c` | Text(50) |
| `Member_Type__c` | Text(20) |
| `Program_Name__c` | Text(100) |
| `Enrolled_At__c` | DateTime |

---

### Order_Fulfilment_Event__e (HighVolume, PublishAfterCommit)

Published by the external order management system. Consumed by `OrderFulfilmentEventHandler` to accrue points.

| Field | Type |
|---|---|
| `Order_Id__c` | Text(50) — idempotency key |
| `Contact_Id__c` | Text(18) |
| `Loyalty_Member_Id__c` | Text(50) |
| `Order_Amount__c` | Number(16,2) |
| `Order_Date__c` | DateTime |
| `Cart_Lines_JSON__c` | LongTextArea — JSON array of CartLineItem DTOs |

---

### Order_Cancellation_Event__e (HighVolume, PublishAfterCommit)

Published by the order management system on cancellation. Consumed by `OrderCancellationEventHandler` to reverse vouchers and debit points.

| Field | Type |
|---|---|
| `Order_Id__c` | Text(50) |
| `Contact_Id__c` | Text(18) |
| `Loyalty_Member_Id__c` | Text(50) |
| `Points_To_Reverse__c` | Number(12,2) |
| `Voucher_Ids_JSON__c` | Text(4096) — JSON array |
| `Cancelled_At__c` | DateTime |

---

## Entity Relationship Overview

```
Contact ──< Order_Points_Status__c
Contact ──< RCC_Import_Record__c (match result)
Contact ──< Privacy_Request__c
  Privacy_Request__c ──< Privacy_Audit_Log__c

Loyalty_Program_Config__mdt ──< Loyalty_Exclusion_Rule__mdt

[External] Order Management System
  → publishes Order_Fulfilment_Event__e / Order_Cancellation_Event__e
  → consumed by Apex EventBus triggers
```
