import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent }       from 'lightning/platformShowToastEvent';
import getMemberPromotions      from '@salesforce/apex/LoyaltyPromotionController.getMemberPromotions';
import enrollForPromotion       from '@salesforce/apex/LoyaltyPromotionController.enrollForPromotion';
import optOutFromPromotion      from '@salesforce/apex/LoyaltyPromotionController.optOutFromPromotion';

export default class LoyaltyPromoEnrollment extends LightningElement {

    @api lpmId;

    @track promotions = [];
    @track isLoading  = false;

    connectedCallback() {
        if (this.lpmId) this.loadPromotions();
    }

    async loadPromotions() {
        this.isLoading = true;
        try {
            const raw = await getMemberPromotions({ lpmId: this.lpmId });
            this.promotions = (raw || []).map(p => ({
                ...p,
                canEnroll:        p.enrollmentStatus !== 'Enrolled',
                canOptOut:        p.enrollmentStatus === 'Enrolled',
                statusBadgeClass: p.enrollmentStatus === 'Enrolled'
                    ? 'slds-badge slds-theme_success'
                    : 'slds-badge'
            }));
        } catch (e) {
            this.promotions = [];
        } finally {
            this.isLoading = false;
        }
    }

    get hasPromotions() { return this.promotions.length > 0; }

    async handleEnroll(evt) {
        const promoId = evt.currentTarget.dataset.promoId;
        try {
            await enrollForPromotion({ lpmId: this.lpmId, promotionId: promoId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Enrolled', message: 'Member enrolled in promotion.', variant: 'success' }));
            await this.loadPromotions();
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: e.body?.message || 'Enrollment failed', variant: 'error' }));
        }
    }

    async handleOptOut(evt) {
        const promoId = evt.currentTarget.dataset.promoId;
        try {
            await optOutFromPromotion({ lpmId: this.lpmId, promotionId: promoId });
            this.dispatchEvent(new ShowToastEvent({ title: 'Opted Out', message: 'Member opted out of promotion.', variant: 'success' }));
            await this.loadPromotions();
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: e.body?.message || 'Opt-out failed', variant: 'error' }));
        }
    }
}
