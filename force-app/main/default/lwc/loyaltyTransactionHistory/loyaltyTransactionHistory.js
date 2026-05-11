import { LightningElement, api, track } from 'lwc';
import getTransactionHistory from '@salesforce/apex/LoyaltyTransactionController.getTransactionHistory';

const COLUMNS = [
    { label: 'Date',             fieldName: 'activityDate',    type: 'date', typeAttributes: { year: 'numeric', month: 'short', day: '2-digit' } },
    { label: 'Type',             fieldName: 'journalTypeName', type: 'text' },
    { label: 'Points',           fieldName: 'pointsChange',    type: 'number', cellAttributes: { class: { fieldName: 'pointsClass' } } },
    { label: 'Balance After',    fieldName: 'balanceAfter',    type: 'number' },
    { label: 'Order Reference',  fieldName: 'referenceId',     type: 'text' },
    { label: 'Status',           fieldName: 'status',          type: 'text' }
];

const TYPE_OPTIONS = [
    { label: 'All Types',  value: '' },
    { label: 'Earn',       value: 'Purchase' },
    { label: 'Redeem',     value: 'Redemption' },
    { label: 'Expire',     value: 'Expiry' },
    { label: 'Adjust',     value: 'Manual Adjustment' }
];

export default class LoyaltyTransactionHistory extends LightningElement {

    @api lpmId;
    @api recordId; // Contact Id (to derive lpmId if not passed directly)

    @track transactions   = [];
    @track isLoading      = false;
    @track noMoreData     = false;
    @track fromDate       = this._defaultFromDate();
    @track toDate         = new Date().toISOString().split('T')[0];
    @track typeFilter     = '';
    @track pageSize       = 25;
    @track pageToken      = null;

    columns         = COLUMNS;
    typeFilterOptions = TYPE_OPTIONS;

    connectedCallback() {
        this.loadHistory(true);
    }

    async loadHistory(reset = false) {
        if (reset) {
            this.transactions = [];
            this.pageToken    = null;
            this.noMoreData   = false;
        }

        this.isLoading = true;
        try {
            const result = await getTransactionHistory({
                lpmId:      this.lpmId,
                fromDate:   this.fromDate,
                toDate:     this.toDate,
                typeFilter: this.typeFilter,
                pageSize:   this.pageSize,
                pageToken:  this.pageToken
            });

            const mapped = (result?.transactionJournals || []).map(t => ({
                id:              t.id,
                activityDate:    t.activityDate,
                journalTypeName: t.journalTypeName,
                pointsChange:    t.pointsChange,
                balanceAfter:    t.runningBalance,
                referenceId:     t.referenceId,
                status:          t.status,
                pointsClass:     t.pointsChange >= 0 ? 'slds-text-color_success' : 'slds-text-color_error'
            }));

            this.transactions = reset ? mapped : [...this.transactions, ...mapped];
            this.pageToken    = result?.nextPageToken || null;
            this.noMoreData   = !this.pageToken;
        } catch (e) {
            this.transactions = [];
        } finally {
            this.isLoading = false;
        }
    }

    get hasTransactions() { return this.transactions.length > 0; }

    handleFromDate(evt)   { this.fromDate   = evt.detail.value; }
    handleToDate(evt)     { this.toDate     = evt.detail.value; }
    handleTypeFilter(evt) { this.typeFilter = evt.detail.value; }
    handleSearch()        { this.loadHistory(true); }
    handleLoadMore()      { this.loadHistory(false); }

    _defaultFromDate() {
        const d = new Date();
        d.setMonth(d.getMonth() - 3);
        return d.toISOString().split('T')[0];
    }
}
