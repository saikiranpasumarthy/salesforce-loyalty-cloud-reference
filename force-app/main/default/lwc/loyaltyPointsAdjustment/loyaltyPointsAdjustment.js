import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// In a full implementation these would call Apex wrappers around LoyaltyTransactionService
// For reference architecture, wired to the controller pattern below
import adjustPoints from '@salesforce/apex/LoyaltyTransactionController.adjustPoints';

const REASON_OPTIONS = [
    { label: 'Appeasement',  value: 'Appeasement' },
    { label: 'Correction',   value: 'Correction' },
    { label: 'Promotion',    value: 'Promotion' },
    { label: 'Other',        value: 'Other' }
];

const TYPE_OPTIONS = [
    { label: 'Credit (Add)',    value: 'Credit' },
    { label: 'Debit (Remove)',  value: 'Debit' }
];

export default class LoyaltyPointsAdjustment extends LightningElement {

    @api lpmId; // LPM Id of the member

    @track adjustmentType = 'Credit';
    @track amount         = '';
    @track reason         = '';
    @track notes          = '';
    @track showConfirm    = false;
    @track isLoading      = false;
    @track errorMessage   = '';

    get adjustmentTypeOptions() { return TYPE_OPTIONS; }
    get reasonOptions()         { return REASON_OPTIONS; }
    get submitLabel()           { return this.isLoading ? 'Processing...' : 'Confirm Adjustment'; }

    handleTypeChange(evt)  { this.adjustmentType = evt.detail.value; }
    handleAmount(evt)      { this.amount          = evt.detail.value; }
    handleReason(evt)      { this.reason          = evt.detail.value; }
    handleNotes(evt)       { this.notes           = evt.detail.value; }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleReview() {
        // Validate before showing confirmation step
        const inputs = this.template.querySelectorAll('lightning-input, lightning-combobox, lightning-textarea');
        if (![...inputs].every(el => el.reportValidity())) return;
        if (!this.amount || this.amount <= 0) return;

        this.errorMessage = '';
        this.showConfirm  = true;
    }

    handleBack() {
        this.showConfirm = false;
    }

    async handleConfirm() {
        this.isLoading    = true;
        this.errorMessage = '';
        try {
            await adjustPoints({
                lpmId:          this.lpmId,
                adjustmentType: this.adjustmentType,
                amount:         parseInt(this.amount, 10),
                reason:         this.reason,
                notes:          this.notes
            });
            this.dispatchEvent(new ShowToastEvent({
                title:   'Points Adjusted',
                message: `${this.adjustmentType} of ${this.amount} points applied successfully.`,
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('adjusted'));
        } catch (e) {
            this.errorMessage = e.body?.message || 'Adjustment failed. Please try again.';
        } finally {
            this.isLoading   = false;
            this.showConfirm = false;
        }
    }
}
