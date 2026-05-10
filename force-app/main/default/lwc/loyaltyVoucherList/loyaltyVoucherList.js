import { LightningElement, api, track } from 'lwc';
import getSessionLoyaltyData from '@salesforce/apex/LoyaltyLoginController.getSessionLoyaltyData';

const COLUMNS = [
    { label: 'Code',          fieldName: 'voucherCode',           type: 'text' },
    { label: 'Value',         fieldName: 'value',                 type: 'currency', typeAttributes: { currencyCode: 'USD' } },
    { label: 'Status',        fieldName: 'status',                type: 'text' },
    { label: 'Expires',       fieldName: 'expiryDateFormatted',   type: 'text' },
    { label: 'Description',   fieldName: 'voucherDefinitionName', type: 'text' },
    {
        type: 'action',
        typeAttributes: {
            rowActions: [
                { label: 'Apply Voucher', name: 'apply' },
                { label: 'View Details',  name: 'view' }
            ]
        }
    }
];

export default class LoyaltyVoucherList extends LightningElement {

    @api recordId;

    @track isLoading     = true;
    @track allVouchers   = [];
    @track activeFilter  = 'Active';

    columns = COLUMNS;

    connectedCallback() {
        this.loadVouchers();
    }

    async loadVouchers() {
        this.isLoading = true;
        try {
            const data = await getSessionLoyaltyData({ contactId: this.recordId });
            // Format expiry dates for display; flag expiring-soon vouchers
            this.allVouchers = (data?.availableVouchers || []).map(v => ({
                ...v,
                expiryDateFormatted : v.expiryDate
                    ? new Date(v.expiryDate).toLocaleDateString()
                    : '—',
                // Expiry within 7 days gets a visual warning
                isExpiringSoon : v.expiryDate
                    && (new Date(v.expiryDate) - new Date()) / 86400000 <= 7
                    && v.status === 'ACTIVE'
            }));
        } catch (e) {
            this.allVouchers = [];
        } finally {
            this.isLoading = false;
        }
    }

    get filteredVouchers() {
        return this.allVouchers.filter(v => v.status === this.activeFilter.toUpperCase());
    }

    get hasVouchers() { return this.filteredVouchers.length > 0; }

    // Button variant toggles for active filter
    get activeVariant()   { return this.activeFilter === 'Active'   ? 'brand' : 'neutral'; }
    get redeemedVariant() { return this.activeFilter === 'Redeemed' ? 'brand' : 'neutral'; }
    get expiredVariant()  { return this.activeFilter === 'Expired'  ? 'brand' : 'neutral'; }

    filterActive()   { this.activeFilter = 'Active'; }
    filterRedeemed() { this.activeFilter = 'Redeemed'; }
    filterExpired()  { this.activeFilter = 'Expired'; }

    handleRowAction(event) {
        const { action, row } = event.detail;
        this.dispatchEvent(new CustomEvent('voucheraction', {
            detail: { actionName: action.name, voucher: row }
        }));
    }
}
