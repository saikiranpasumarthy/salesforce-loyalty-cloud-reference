import { LightningElement, track } from 'lwc';
import enrollMember        from '@salesforce/apex/LoyaltyEnrollmentController.enrollMember';
import checkEmailExists    from '@salesforce/apex/LoyaltyEnrollmentController.checkEmailExists';

const MONTH_OPTIONS = [
    { label: 'January', value: '1' }, { label: 'February', value: '2' },
    { label: 'March', value: '3' },   { label: 'April', value: '4' },
    { label: 'May', value: '5' },     { label: 'June', value: '6' },
    { label: 'July', value: '7' },    { label: 'August', value: '8' },
    { label: 'September', value: '9' },{ label: 'October', value: '10' },
    { label: 'November', value: '11' },{ label: 'December', value: '12' }
];

// Generate day options 1-31
const DAY_OPTIONS = Array.from({ length: 31 }, (_, i) => ({
    label: String(i + 1),
    value: String(i + 1)
}));

const MEMBER_TYPE_OPTIONS = [
    { label: 'Retail', value: 'Retail' },
    { label: 'Pro',    value: 'Pro' },
    { label: 'Student',value: 'Student' }
];

export default class LoyaltyEnrollmentForm extends LightningElement {

    @track firstName        = '';
    @track lastName         = '';
    @track email            = '';
    @track phone            = '';
    @track memberType       = 'Retail';
    @track dobMonth         = '';
    @track dobDay           = '';
    @track proLicenseNumber = '';
    @track proLicenseExpiry = '';
    @track schoolName       = '';
    @track graduationDate   = '';

    @track isLoading         = false;
    @track errorMessage      = '';
    @track duplicateWarning  = false;
    @track enrollmentSuccess = false;
    @track loyaltyId         = '';
    @track tier              = '';

    get memberTypeOptions() { return MEMBER_TYPE_OPTIONS; }
    get monthOptions()      { return MONTH_OPTIONS; }
    get dayOptions()        { return DAY_OPTIONS; }
    get isProMember()       { return this.memberType === 'Pro'; }
    get isStudentMember()   { return this.memberType === 'Student'; }
    get submitLabel()       { return this.isLoading ? 'Enrolling...' : 'Join Now'; }

    handleFirstName(evt)          { this.firstName        = evt.detail.value; }
    handleLastName(evt)           { this.lastName         = evt.detail.value; }
    handleEmail(evt)              { this.email            = evt.detail.value; this.duplicateWarning = false; }
    handlePhone(evt)              { this.phone            = evt.detail.value; }
    handleMemberType(evt)         { this.memberType       = evt.detail.value; }
    handleDobMonth(evt)           { this.dobMonth         = evt.detail.value; }
    handleDobDay(evt)             { this.dobDay           = evt.detail.value; }
    handleProLicense(evt)         { this.proLicenseNumber = evt.detail.value; }
    handleProLicenseExpiry(evt)   { this.proLicenseExpiry = evt.detail.value; }
    handleSchoolName(evt)         { this.schoolName       = evt.detail.value; }
    handleGraduationDate(evt)     { this.graduationDate   = evt.detail.value; }

    /**
     * Checks for duplicate email on blur — real-time UX feedback
     * without blocking submission.
     */
    async handleEmailBlur() {
        if (!this.email) return;
        try {
            const exists = await checkEmailExists({ email: this.email });
            this.duplicateWarning = exists;
        } catch (e) {
            // Silently ignore duplicate check errors — do not block enrollment
        }
    }

    async handleSubmit() {
        // Native form validation
        const inputs = this.template.querySelectorAll('lightning-input, lightning-combobox');
        const allValid = [...inputs].every(el => el.reportValidity());
        if (!allValid) return;

        this.isLoading    = true;
        this.errorMessage = '';

        try {
            const result = await enrollMember({
                firstName:  this.firstName,
                lastName:   this.lastName,
                email:      this.email,
                phone:      this.phone,
                memberType: this.memberType,
                dobMonth:   this.dobMonth  ? parseInt(this.dobMonth, 10)  : null,
                dobDay:     this.dobDay    ? parseInt(this.dobDay, 10)    : null
            });

            if (result.success) {
                this.enrollmentSuccess = true;
                this.loyaltyId         = result.loyaltyId;
                this.tier              = result.tier;
                this.dispatchEvent(new CustomEvent('enrolled', {
                    detail: { loyaltyId: result.loyaltyId, contactId: result.contactId }
                }));
            } else {
                this.errorMessage = result.errorMessage || 'Enrollment failed. Please try again.';
            }
        } catch (e) {
            this.errorMessage = 'An unexpected error occurred. Please contact support.';
        } finally {
            this.isLoading = false;
        }
    }
}
