/**
 * Tier override component — admin only.
 * Requires Loyalty_Admin permission set to be assigned to the running user.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import updateMemberTier   from '@salesforce/apex/LoyaltyTierController.updateMemberTier';

const TIER_OPTIONS = [
    { label: 'Preferred', value: 'Preferred' },
    { label: 'Elite',     value: 'Elite' }
];

export default class LoyaltyTierManagement extends LightningElement {

    @api lpmId;
    @api currentTier = 'Preferred';

    @track selectedTier    = '';
    @track overrideReason  = '';
    @track isLoading       = false;
    @track errorMessage    = '';

    get tierOptions()      { return TIER_OPTIONS; }
    get hasError()         { return !!this.errorMessage; }
    get saveLabel()        { return this.isLoading ? 'Updating...' : 'Update Tier'; }
    get isSaveDisabled()   { return this.isLoading || !this.selectedTier || !this.overrideReason; }

    get currentTierClass() {
        return this.currentTier === 'Elite'
            ? 'slds-badge slds-theme_warning'
            : 'slds-badge slds-theme_success';
    }

    handleTierChange(evt)   { this.selectedTier   = evt.detail.value; }
    handleReasonChange(evt) { this.overrideReason = evt.detail.value; }

    async handleSave() {
        if (!this.selectedTier || !this.overrideReason.trim()) return;

        this.isLoading    = true;
        this.errorMessage = '';
        try {
            await updateMemberTier({
                lpmId:  this.lpmId,
                tier:   this.selectedTier,
                reason: this.overrideReason
            });
            this.dispatchEvent(new ShowToastEvent({
                title:   'Tier Updated',
                message: `Member tier changed to ${this.selectedTier}.`,
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('tierupdated', {
                detail: { newTier: this.selectedTier }
            }));
            this.selectedTier   = '';
            this.overrideReason = '';
        } catch (e) {
            this.errorMessage = e.body?.message || 'Tier update failed. Please try again.';
        } finally {
            this.isLoading = false;
        }
    }
}
