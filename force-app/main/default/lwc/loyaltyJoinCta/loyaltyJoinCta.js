import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent }       from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import enrollExistingContact    from '@salesforce/apex/LoyaltyEnrollmentController.enrollExistingContact';
import HAS_LOYALTY_FIELD        from '@salesforce/schema/Contact.Has_Loyalty__c';

export default class LoyaltyJoinCta extends LightningElement {

    @api recordId;
    @api memberType = 'Retail'; // default; can be overridden via component attribute

    @track isLoading     = false;
    @track errorMessage  = '';

    @wire(getRecord, { recordId: '$recordId', fields: [HAS_LOYALTY_FIELD] })
    contact;

    get hasLoyalty() {
        return getFieldValue(this.contact?.data, HAS_LOYALTY_FIELD) === true;
    }

    get ctaLabel() { return this.isLoading ? 'Joining...' : 'Join Rewards'; }

    async handleJoin() {
        this.isLoading    = true;
        this.errorMessage = '';
        try {
            const result = await enrollExistingContact({
                contactId:  this.recordId,
                memberType: this.memberType
            });
            if (result.success) {
                this.dispatchEvent(new ShowToastEvent({
                    title:   'Welcome!',
                    message: 'You have been enrolled. Your Loyalty ID: ' + result.loyaltyId,
                    variant: 'success'
                }));
                // The @wire will auto-refresh Has_Loyalty__c — CTA hides automatically
            } else {
                this.errorMessage = result.errorMessage || 'Enrollment failed.';
            }
        } catch (e) {
            this.errorMessage = 'An error occurred. Please try again.';
        } finally {
            this.isLoading = false;
        }
    }
}
