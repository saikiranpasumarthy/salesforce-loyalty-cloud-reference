/**
 * @description Request payload for a new loyalty enrollment.
 *              Constructed by controllers and passed to LoyaltyEnrollmentService.
 *              Validated in LoyaltyEnrollmentService.enrollNewMember before any DML or API call.
 */
public with sharing class EnrollmentRequest {

    /** Required — maps to Contact.FirstName */
    public String firstName       { get; set; }

    /** Required — maps to Contact.LastName */
    public String lastName        { get; set; }

    /** Required — primary identifier for duplicate detection and SFMC targeting */
    public String email           { get; set; }

    /** Optional — required for RCC card matching; stored on Contact.Phone */
    public String phone           { get; set; }

    /** Required — drives tier configuration: Retail | Pro | Student */
    public String memberType      { get; set; }

    /** Required — name of the Loyalty Management program (from Loyalty_Program_Config__mdt) */
    public String programName     { get; set; }

    /** Optional — day/month only (no year) stored as DOB_Month__c and DOB_Day__c for birthday promos */
    public Integer dobMonth       { get; set; }
    public Integer dobDay         { get; set; }

    /** Optional — Pro member fields */
    public String  proLicenseNumber { get; set; }
    public Date    proLicenseExpiry { get; set; }

    /** Optional — Student member fields */
    public String  schoolName       { get; set; }
    public Date    graduationDate   { get; set; }

    /** System-set — identifies which channel triggered enrollment (WEB/POS/BATCH/EVENT) */
    public String enrollmentSource  { get; set; }

    /**
     * @description Validates that mandatory fields are present.
     *              Throws LoyaltyEnrollmentException if validation fails.
     */
    public void validate() {
        List<String> missing = new List<String>();
        if (String.isBlank(firstName))   missing.add('firstName');
        if (String.isBlank(lastName))    missing.add('lastName');
        if (String.isBlank(email))       missing.add('email');
        if (String.isBlank(memberType))  missing.add('memberType');
        if (String.isBlank(programName)) missing.add('programName');

        if (!missing.isEmpty()) {
            throw new LoyaltyEnrollmentException(
                'Enrollment request missing required fields: ' + String.join(missing, ', '),
                LoyaltyEnrollmentException.EnrollmentErrorCode.MISSING_FIELDS
            );
        }
    }
}
