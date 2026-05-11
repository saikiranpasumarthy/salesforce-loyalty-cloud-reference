# Validation Queries — Ready-to-Run SOQL

Run these in Setup → Developer Console → Query Editor or via `sf data query`.

---

## Enrollment

```sql
-- All enrolled members
SELECT Id, FirstName, LastName, Email, Loyalty_Member_Id__c, Loyalty_Member_Type__c, CreatedDate
FROM Contact
WHERE Has_Loyalty__c = true
ORDER BY CreatedDate DESC
LIMIT 50

-- Members enrolled today
SELECT Id, FirstName, LastName, Email, Loyalty_Member_Id__c
FROM Contact
WHERE Has_Loyalty__c = true
AND CreatedDate = TODAY

-- Members missing LPM Id (enrollment may have failed after Contact update)
SELECT Id, FirstName, LastName, Email
FROM Contact
WHERE Has_Loyalty__c = true
AND Loyalty_Member_Id__c = null

-- RCC card holders
SELECT Id, FirstName, LastName, Email, RCC_Card_Number__c, RCC_Active__c
FROM Contact
WHERE RCC_Card_Number__c != null
ORDER BY CreatedDate DESC
LIMIT 50
```

---

## RCC Batch Import

```sql
-- Pending RCC import records
SELECT Id, Card_Number__c, Email__c, Member_Type__c, CreatedDate
FROM RCC_Import_Record__c
WHERE Status__c = 'Pending'
ORDER BY CreatedDate ASC

-- Failed RCC import records
SELECT Id, Card_Number__c, Email__c, Error_Message__c, Batch_Job_Id__c
FROM RCC_Import_Record__c
WHERE Status__c = 'Failed'
ORDER BY CreatedDate DESC
LIMIT 50

-- Recent batch run logs
SELECT Batch_Type__c, Total_Processed__c, Total_Succeeded__c, Total_Failed__c,
       Completed_At__c, Apex_Job_Id__c
FROM Batch_Run_Log__c
ORDER BY Completed_At__c DESC
LIMIT 20

-- Batch runs with failures
SELECT Batch_Type__c, Total_Failed__c, Error_Summary__c, Completed_At__c
FROM Batch_Run_Log__c
WHERE Total_Failed__c > 0
ORDER BY Completed_At__c DESC

-- RCC batch stats for last 30 days
SELECT Batch_Type__c, SUM(Total_Processed__c) totalProcessed,
       SUM(Total_Succeeded__c) totalSucceeded, SUM(Total_Failed__c) totalFailed
FROM Batch_Run_Log__c
WHERE Batch_Type__c = 'RCC_Card_Import'
AND Completed_At__c = LAST_N_DAYS:30
GROUP BY Batch_Type__c
```

---

## Points & Order Status

```sql
-- All Order_Points_Status records for a specific contact
SELECT Id, Status__c, Order_Id__c, Points_Awarded__c, CreatedDate
FROM Order_Points_Status__c
WHERE Contact__c = '<contactId>'
ORDER BY CreatedDate DESC

-- Recently awarded points
SELECT Id, Contact__c, Order_Id__c, Points_Awarded__c, CreatedDate
FROM Order_Points_Status__c
WHERE Status__c = 'Awarded'
AND CreatedDate = TODAY
ORDER BY CreatedDate DESC

-- Failed points transactions (need investigation)
SELECT Id, Contact__c, Order_Id__c, CreatedDate
FROM Order_Points_Status__c
WHERE Status__c = 'Failed'
ORDER BY CreatedDate DESC
LIMIT 50

-- Reversed (cancelled orders)
SELECT Id, Contact__c, Order_Id__c, Points_Awarded__c, CreatedDate
FROM Order_Points_Status__c
WHERE Status__c = 'Reversed'
AND CreatedDate = THIS_MONTH
ORDER BY CreatedDate DESC

-- Points status distribution
SELECT Status__c, COUNT(Id) cnt
FROM Order_Points_Status__c
GROUP BY Status__c
```

---

## Privacy / GDPR

```sql
-- All privacy deletion requests
SELECT Id, OneTrust_Request_Id__c, Status__c, Request_Type__c, Requested_At__c,
       Contact__c
FROM Privacy_Request__c
ORDER BY Requested_At__c DESC
LIMIT 50

-- In-progress requests (may need follow-up)
SELECT Id, OneTrust_Request_Id__c, Status__c, Requested_At__c, Contact__c
FROM Privacy_Request__c
WHERE Status__c = 'In_Progress'
ORDER BY Requested_At__c ASC

-- Audit logs for a specific request
SELECT Action__c, Detail__c, Performed_At__c
FROM Privacy_Audit_Log__c
WHERE Privacy_Request__c = '<privacyRequestId>'
ORDER BY Performed_At__c ASC

-- All audit log entries today
SELECT Action__c, Detail__c, Performed_At__c
FROM Privacy_Audit_Log__c
WHERE Performed_At__c = TODAY
ORDER BY Performed_At__c DESC

-- Contacts that have been anonymised (PII cleared)
SELECT Id, FirstName, LastName, Has_Loyalty__c, Loyalty_Member_Id__c
FROM Contact
WHERE FirstName = 'Deleted'
ORDER BY LastName ASC
LIMIT 50

-- Verify specific contact was anonymised correctly
SELECT Id, FirstName, LastName, Email, Phone, MailingStreet,
       RCC_Card_Number__c, Pro_License_Number__c, Has_Loyalty__c, Loyalty_Member_Id__c
FROM Contact
WHERE Id = '<contactId>'
```

---

## Points Expiry

```sql
-- US contacts eligible for expiry check (all US loyalty members)
SELECT Id, FirstName, LastName, Email, Loyalty_Member_Id__c, Country_Code__c
FROM Contact
WHERE Country_Code__c = 'US'
AND Has_Loyalty__c = true
AND Loyalty_Member_Id__c != null
ORDER BY LastName ASC

-- CA contacts (should never be in expiry batch)
SELECT Id, FirstName, LastName, Email, Loyalty_Member_Id__c
FROM Contact
WHERE Country_Code__c = 'CA'
AND Has_Loyalty__c = true

-- Members with qualifying purchases in the last year (should be skipped)
SELECT Contact__r.Email, Contact__r.Loyalty_Member_Id__c, MAX(CreatedDate) lastPurchase
FROM Order_Points_Status__c
WHERE Status__c = 'Awarded'
AND CreatedDate = LAST_N_DAYS:365
GROUP BY Contact__r.Email, Contact__r.Loyalty_Member_Id__c
LIMIT 100

-- Points expiry batch run history
SELECT Total_Processed__c, Total_Succeeded__c, Total_Failed__c, Completed_At__c
FROM Batch_Run_Log__c
WHERE Batch_Type__c = 'PointsExpiryBatch'
ORDER BY Completed_At__c DESC
```

---

## Tier & Member Profile

```sql
-- Members by member type
SELECT Loyalty_Member_Type__c, COUNT(Id) cnt
FROM Contact
WHERE Has_Loyalty__c = true
GROUP BY Loyalty_Member_Type__c

-- Pro members with license numbers
SELECT Id, FirstName, LastName, Email, Pro_License_Number__c, Pro_License_Expiry__c
FROM Contact
WHERE Loyalty_Member_Type__c = 'Pro'
AND Has_Loyalty__c = true
ORDER BY Pro_License_Expiry__c ASC NULLS FIRST

-- Student members
SELECT Id, FirstName, LastName, Email, School_Name__c, Graduation_Date__c
FROM Contact
WHERE Loyalty_Member_Type__c = 'Student'
AND Has_Loyalty__c = true
```

---

## Scheduled Jobs

```sql
-- Verify scheduled batch jobs
SELECT Id, JobType, CronExpression, NextFireTime, State, CronJobDetail.Name
FROM CronTrigger
WHERE CronJobDetail.Name LIKE '%Loyalty%'
   OR CronJobDetail.Name LIKE '%RCC%'
   OR CronJobDetail.Name LIKE '%Points%'
ORDER BY NextFireTime ASC

-- Active async Apex jobs
SELECT Id, Status, JobType, MethodName, NumberOfErrors, TotalJobItems, CompletedDate
FROM AsyncApexJob
WHERE JobType = 'BatchApex'
AND CreatedDate = TODAY
ORDER BY CreatedDate DESC
```

---

## System Health Checks

```sql
-- CMDT config verification
SELECT DeveloperName, Program_API_Name__c, Currency_ISO_Code__c,
       Max_Enrollments_Per_Day__c, Is_Active__c
FROM Loyalty_Program_Config__mdt

-- Tier mapping records
SELECT DeveloperName, Legacy_Code__c, Canonical_Tier__c, Member_Type__c
FROM Tier_Mapping__mdt
ORDER BY DeveloperName ASC

-- Active exclusion rules
SELECT DeveloperName, Rule_Value__c, Is_Active__c
FROM Loyalty_Exclusion_Rule__mdt
WHERE Is_Active__c = true

-- Contacts enrolled in the last 7 days
SELECT COUNT(Id) newEnrollments
FROM Contact
WHERE Has_Loyalty__c = true
AND CreatedDate = LAST_N_DAYS:7

-- Contacts with duplicate loyalty IDs (should be 0)
SELECT Loyalty_Member_Id__c, COUNT(Id) cnt
FROM Contact
WHERE Loyalty_Member_Id__c != null
GROUP BY Loyalty_Member_Id__c
HAVING COUNT(Id) > 1
```
