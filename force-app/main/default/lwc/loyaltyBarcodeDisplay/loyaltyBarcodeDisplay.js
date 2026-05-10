/**
 * Renders the loyalty member's ID as a scannable barcode using JsBarcode.
 *
 * STATIC RESOURCE SETUP:
 *   Upload JsBarcode.all.min.js as a static resource named 'JsBarcode'.
 *   Download from: https://github.com/lindell/JsBarcode/releases
 *
 * FORMAT: CODE128 — compact and supports alphanumeric loyalty IDs.
 */
import { LightningElement, api, track, wire } from 'lwc';
import { loadScript }           from 'lightning/platformResourceLoader';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import JsBarcode                from '@salesforce/resourceUrl/JsBarcode';

import LOYALTY_ID_FIELD   from '@salesforce/schema/Contact.Loyalty_Member_Id__c';
import FIRST_NAME_FIELD   from '@salesforce/schema/Contact.FirstName';
import LAST_NAME_FIELD    from '@salesforce/schema/Contact.LastName';

export default class LoyaltyBarcodeDisplay extends LightningElement {

    @api recordId;

    @track isScriptLoaded = false;
    @track loyaltyId      = null;
    @track memberName     = '';

    @wire(getRecord, { recordId: '$recordId', fields: [LOYALTY_ID_FIELD, FIRST_NAME_FIELD, LAST_NAME_FIELD] })
    wiredRecord({ data, error }) {
        if (data) {
            this.loyaltyId  = getFieldValue(data, LOYALTY_ID_FIELD);
            const first     = getFieldValue(data, FIRST_NAME_FIELD) || '';
            const last      = getFieldValue(data, LAST_NAME_FIELD)  || '';
            this.memberName = `${first} ${last}`.trim();
            this.renderBarcode();
        }
    }

    connectedCallback() {
        loadScript(this, JsBarcode)
            .then(() => {
                this.isScriptLoaded = true;
                this.renderBarcode();
            })
            .catch(e => console.error('JsBarcode load failed:', e));
    }

    get hasLoyaltyId() { return !!this.loyaltyId; }

    renderBarcode() {
        if (!this.isScriptLoaded || !this.loyaltyId) return;

        const svgEl = this.refs?.barcodeEl;
        if (!svgEl) return;

        // eslint-disable-next-line no-undef
        JsBarcode(svgEl, this.loyaltyId, {
            format:      'CODE128',
            width:       2,
            height:      60,
            displayValue: false,
            margin:      10
        });
    }

    handleRefresh() {
        // Force a re-render of the barcode after explicit refresh
        this.renderBarcode();
    }
}
