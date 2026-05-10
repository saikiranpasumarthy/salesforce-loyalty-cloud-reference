import { LightningElement, api, track } from 'lwc';
import getSessionLoyaltyData from '@salesforce/apex/LoyaltyLoginController.getSessionLoyaltyData';

const CACHE_TTL_MINUTES = 5; // Do not re-call if data is fresh < 5 min (session cache)

export default class LoyaltyPointsBalance extends LightningElement {

    @api recordId; // Contact Id from record page context

    @track isLoading   = true;
    @track hasError    = false;
    @track sessionData = null;
    @track lastFetched = null;

    connectedCallback() {
        this.loadData();
    }

    async loadData() {
        // Check if the data in memory is still fresh (< 5 min) before calling Apex
        if (this.sessionData && this.lastFetched) {
            const ageMs = Date.now() - this.lastFetched;
            if (ageMs < CACHE_TTL_MINUTES * 60 * 1000) return; // Still fresh
        }

        this.isLoading = true;
        this.hasError  = false;
        try {
            this.sessionData = await getSessionLoyaltyData({ contactId: this.recordId });
            this.lastFetched = Date.now();
        } catch (e) {
            this.hasError = true;
        } finally {
            this.isLoading = false;
        }
    }

    async handleRetry() {
        this.lastFetched = null; // Force refresh
        await this.loadData();
    }

    get formattedBalance() {
        const bal = this.sessionData?.pointsBalance;
        return bal != null ? bal.toLocaleString('en-US') : '—';
    }

    get currencyName() {
        return 'Reward Points';
    }

    get showExpiry() {
        return this.sessionData?.expiryDate != null && !this.sessionData?.isCAMember;
    }

    get expiryDateFormatted() {
        if (!this.sessionData?.expiryDate) return '';
        return new Date(this.sessionData.expiryDate).toLocaleDateString('en-US', {
            year: 'numeric', month: 'short', day: 'numeric'
        });
    }

    get expiryClass() {
        if (!this.sessionData?.expiryDate) return '';
        const daysUntil = Math.ceil(
            (new Date(this.sessionData.expiryDate) - new Date()) / (1000 * 60 * 60 * 24)
        );
        return daysUntil <= 30
            ? 'slds-text-color_error slds-text-body_small'
            : 'slds-text-color_weak slds-text-body_small';
    }

    get lastRefreshedFormatted() {
        if (!this.lastFetched) return '';
        return new Date(this.lastFetched).toLocaleTimeString('en-US', {
            hour: '2-digit', minute: '2-digit'
        });
    }
}
