import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import checkInVisit from '@salesforce/apex/VisitController.checkInVisit';
import checkOutVisit from '@salesforce/apex/VisitController.checkOutVisit';

export default class VisitCard extends NavigationMixin(LightningElement) {

    @api visit;

    get resolvedStatus() {
        return this._getField('Visit_Status__c') || '';
    }

    get outletName() {
        return this._getOutlet()?.Name || 'Unknown Outlet';
    }

    get outletAddress() {
        return this._getField('Address__c') || this._getOutlet()?.ShippingAddress || 'No Address Provided';
    }

    get statusLabel() {
        return this.resolvedStatus || 'Unknown';
    }

    get statusClass() {
        const status = this._normalizeStatus(this.resolvedStatus);
        return `status ${status.replace(/\s/g, '')}`;
    }

    // Prevents the "Card Click" from firing when you click a button
    handleButtonContainerClick(event) {
        event.stopPropagation();
    }

    handleViewDetail() {
        // Navigates to the standard Salesforce Record Page
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.visit.Id,
                actionName: 'view'
            }
        });
    }

    get showCheckIn() {
        return this._normalizeStatus(this.resolvedStatus) === 'approved';
    }

    get showCheckOut() {
        return this._normalizeStatus(this.resolvedStatus) === 'in progress';
    }

    get isCompleted() {
        return this._normalizeStatus(this.resolvedStatus) === 'completed';
    }

    handleCheckIn() {
        navigator.geolocation.getCurrentPosition(pos => {
            checkInVisit({
                visitId: this.visit.Id,
                lat: pos.coords.latitude.toString(),
                lon: pos.coords.longitude.toString()
            });
        });
    }

    handleCheckOut() {
        navigator.geolocation.getCurrentPosition(pos => {
            checkOutVisit({
                visitId: this.visit.Id,
                lat: pos.coords.latitude.toString(),
                lon: pos.coords.longitude.toString()
            });
        });
    }

    _getOutlet() {
        return this._getField('Outlet1__r')
            || this._getField('Outlet__r')
            || null;
    }

    _getField(apiName) {
        const record = this.visit || {};
        const lower = apiName.charAt(0).toLowerCase() + apiName.slice(1);
        const candidates = [
            `ibfsa__${apiName}`,
            apiName,
            `ibfsa__${lower}`,
            lower
        ];
        for (const key of candidates) {
            if (record[key] !== undefined) return record[key];
        }
        return undefined;
    }

    _normalizeStatus(value) {
        return (value || '')
            .toString()
            .trim()
            .toLowerCase()
            .replace(/[_-]+/g, ' ')
            .replace(/\s+/g, ' ');
    }
}