import { LightningElement, api, track, wire } from 'lwc';
import getSessionLoyaltyData from '@salesforce/apex/LoyaltyLoginController.getSessionLoyaltyData';
import refreshLoyaltyData    from '@salesforce/apex/LoyaltyLoginController.refreshLoyaltyData';

export default class LoyaltyMemberDashboard extends LightningElement {

    /** Contact record Id — set by the record page context */
    @api recordId;

    @track isLoading    = true;
    @track hasError     = false;
    @track errorMessage = '';
    @track memberData   = null;
    @track showAdjustModal = false;

    connectedCallback() {
        this.loadMemberData();
    }

    async loadMemberData() {
        this.isLoading = true;
        this.hasError  = false;
        try {
            this.memberData = await getSessionLoyaltyData({ contactId: this.recordId });
        } catch (e) {
            this.hasError     = true;
            this.errorMessage = 'Unable to load loyalty data. ' + (e.body?.message || '');
        } finally {
            this.isLoading = false;
        }
    }

    // ── Computed getters ─────────────────────────────────────────────────────

    get hasMemberData()  { return this.memberData && this.memberData.hasLoyalty && !this.isLoading && !this.hasError; }
    get hasNoLoyalty()   { return this.memberData && !this.memberData.hasLoyalty && !this.isLoading && !this.hasError; }

    get loyaltyId()      { return this.memberData?.loyaltyId || '—'; }
    get tier()           { return this.memberData?.tier || 'Preferred'; }
    get memberType()     { return this.memberData?.memberType || 'Retail'; }
    get lpmId()          { return this.memberData?.lpmId; }
    get nextTierName()   { return this.memberData?.tier === 'Preferred' ? 'Elite' : 'Elite (Max)'; }

    get pointsBalance() {
        const bal = this.memberData?.pointsBalance;
        return bal != null ? bal.toLocaleString() : '0';
    }

    get pointsToNextTier() {
        const pts = this.memberData?.pointsToNextTier;
        return pts != null ? pts.toLocaleString() : '—';
    }

    get tierProgress() {
        if (!this.memberData?.pointsBalance || !this.memberData?.nextTierThreshold) return 0;
        return Math.min(100, Math.round((this.memberData.pointsBalance / this.memberData.nextTierThreshold) * 100));
    }

    get tierBadgeClass() {
        const base = 'slds-badge ';
        return this.memberData?.tier === 'Elite'
            ? base + 'slds-badge_lightest slds-theme_warning'
            : base + 'slds-theme_success';
    }

    get lastRefreshed() {
        if (!this.memberData?.lastRefreshed) return '';
        const d = new Date(this.memberData.lastRefreshed);
        return d.toLocaleString();
    }

    // ── Handlers ─────────────────────────────────────────────────────────────

    async handleRefresh() {
        this.isLoading = true;
        try {
            this.memberData = await refreshLoyaltyData({ contactId: this.recordId });
        } catch (e) {
            this.hasError = true;
            this.errorMessage = 'Refresh failed: ' + (e.body?.message || e.message);
        } finally {
            this.isLoading = false;
        }
    }

    handleAdjustPoints() {
        this.showAdjustModal = true;
    }

    handleAdjustClose() {
        this.showAdjustModal = false;
    }

    handleAdjusted() {
        this.showAdjustModal = false;
        this.handleRefresh(); // Refresh balance after adjustment
    }

    handleViewHistory() {
        this.dispatchEvent(new CustomEvent('viewhistory', { detail: { lpmId: this.lpmId } }));
    }

    handleUnenroll() {
        this.dispatchEvent(new CustomEvent('unenroll', { detail: { lpmId: this.lpmId } }));
    }
}
