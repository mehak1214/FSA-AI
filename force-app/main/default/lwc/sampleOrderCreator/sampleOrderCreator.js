import { LightningElement, api, track, wire } from 'lwc';
import getPicklistValues from '@salesforce/apex/SampleOrderController.getPicklistValues';
import getSampleProducts from '@salesforce/apex/SampleOrderController.getSampleProducts';
import createSampleOrder from '@salesforce/apex/SampleOrderController.createSampleOrder';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class SampleOrderCreator extends NavigationMixin(LightningElement) {

    @api recordId;
    @track order = {};
    @track lines = [];

    purposeOptions = [];
    unitOptions = [];
    products = [];

    purposeObjectApiName = 'Sample_Order__c';
    purposeFieldApiName = 'Purpose__c';
    purposeFallbackTried = false;

    unitObjectApiName = 'Sample_Order_Line__c';
    unitFieldApiName = 'UnitOfMeasure__c';
    unitFallbackTried = false;

    @wire(getPicklistValues, {
        objectApiName: '$purposeObjectApiName',
        fieldApiName: '$purposeFieldApiName'
    })
    wiredPurpose({ data, error }) {
        if (data) {
            this.purposeOptions = data.map((value) => ({ label: value, value }));
            return;
        }
        if (error && !this.purposeFallbackTried) {
            this.purposeFallbackTried = true;
            this.purposeObjectApiName = 'ibfsa__Sample_Order__c';
            this.purposeFieldApiName = 'ibfsa__Purpose__c';
            return;
        }
        if (error) {
            this.showToast('Error', this._extractError(error) || 'Unable to load purpose options.', 'error');
        }
    }

    @wire(getPicklistValues, {
        objectApiName: '$unitObjectApiName',
        fieldApiName: '$unitFieldApiName'
    })
    wiredUnits({ data, error }) {
        if (data) {
            this.unitOptions = data.map((value) => ({ label: value, value }));
            return;
        }
        if (error && !this.unitFallbackTried) {
            this.unitFallbackTried = true;
            this.unitObjectApiName = 'ibfsa__Sample_Order_Line__c';
            this.unitFieldApiName = 'ibfsa__UnitOfMeasure__c';
            return;
        }
        if (error) {
            this.showToast('Error', this._extractError(error) || 'Unable to load UOM options.', 'error');
        }
    }

    @wire(getSampleProducts)
    wiredProducts({ data }) {
        if (data) {
            this.products = data.map((product) => ({ label: product.Name, value: product.Id }));
        }
    }

    handleHeaderChange(event) {
        this.order = {
            ...this.order,
            [event.target.dataset.field]: event.target.value
        };
    }

    addLine() {
        this.lines = [...this.lines, { uid: Date.now().toString() }];
    }

    handleLineChange(event) {
        const idx = Number(event.target.dataset.index);
        const field = event.target.dataset.field;
        const updated = [...this.lines];
        updated[idx] = {
            ...(updated[idx] || {}),
            [field]: event.target.value
        };
        this.lines = updated;
    }

    removeLine(event) {
        const idx = Number(event.target.dataset.index);
        this.lines = this.lines.filter((_, index) => index !== idx);
    }

    save() {
        const cleanLines = this.lines.map((line) => {
            const copy = { ...line };
            delete copy.uid;
            return copy;
        });

        createSampleOrder({
            orderRec: this.order,
            parentId: this.recordId,
            lines: cleanLines
        })
            .then((res) => {
                this.showToast('Success', 'Sample Order created', 'success');
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: res.sampleOrderId,
                        actionName: 'view'
                    }
                });
            })
            .catch((err) => {
                this.showToast('Error', this._extractError(err) || 'Failed to create sample order.', 'error');
            });
    }

    _extractError(err) {
        return err?.body?.message || err?.message || '';
    }

    showToast(title, msg, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message: msg, variant }));
    }
}