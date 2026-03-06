import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class VisitTile extends LightningElement {

    @api visit;

    get outletAccount() {
        return this.visit?.ibfsa__Outlet1__r || this.visit?.Outlet1__r;
    }

    get resolvedVisitStatus() {
        return this.visit?.ibfsa__Visit_Status__c || this.visit?.Visit_Status__c || '';
    }

    /* =====================
       GETTERS
    ====================== */
    get visitNumber() {
        return this.visit?.Name || this.visit?.Id || '--';
    }

    get outletName() {
        const account = this.outletAccount;
        return account?.Name || 'Unknown Outlet';
    }

    get outletAddress() {
        const account = this.outletAccount;
        if (!account || !account.ShippingAddress) {
            return 'No Address Provided';
        }
        
        // Handle the case where ShippingAddress might be an object with address components
        if (typeof account.ShippingAddress === 'object' && account.ShippingAddress !== null) {
            const addr = account.ShippingAddress;
            const addressParts = [];
            
            // Build address from components
            if (addr.street) addressParts.push(addr.street);
            if (addr.city) addressParts.push(addr.city);
            if (addr.state) addressParts.push(addr.state);
            if (addr.postalCode) addressParts.push(addr.postalCode);
            if (addr.country) addressParts.push(addr.country);
            
            return addressParts.join(', ');
        }
        
        // If it's already a string, return as-is
        return account.ShippingAddress;
    }

    get visitStatus() {
        return this.resolvedVisitStatus || 'Unknown';
    }

    get outletPhone() {
        const account = this.outletAccount;
        return account?.Phone || account?.ibfsa__Phone__c || null;
    }

    get statusKey() {
        const normalized = this.normalizeStatus(this.resolvedVisitStatus);
        const cleaned = normalized.replace(/[^a-z]+/g, '-').replace(/(^-|-$)/g, '');
        return cleaned || 'unknown';
    }

    get statusBadgeClass() {
        return `status-badge ${this.statusKey}`;
    }

    get cardClass() {
        return `visit-card status-${this.statusKey}`;
    }

    /* =====================
       MAP (FIXED)
    ====================== */
    navigateToMap(event) {
        event?.stopPropagation();
        const account = this.outletAccount;

        const lat = account?.ibfsa__Outlet_Location__Latitude__s ?? account?.Outlet_Location__Latitude__s;
        const lon = account?.ibfsa__Outlet_Location__Longitude__s ?? account?.Outlet_Location__Longitude__s;

        if (lat === null || lat === undefined || lon === null || lon === undefined) {
            this.showToast('Location unavailable', 'Outlet location is not available.', 'error');
            return;
        }

        const mapUrl = `https://www.google.com/maps/search/?api=1&query=${lat},${lon}`;

        // Works in Salesforce desktop + mobile
        window.open(mapUrl, '_blank');
    }

    handleCall(event) {
        event?.stopPropagation();
        if (!this.outletPhone) {
            this.showToast('Phone unavailable', 'Outlet phone is not available.', 'warning');
            return;
        }
        window.open(`tel:${this.outletPhone}`, '_self');
    }

    handleEdit(event) {
        event?.stopPropagation();
        this.showToast('Edit', 'Edit action can be mapped here.', 'info');
    }

    handleCardClick() {
        this.dispatchEvent(
            new CustomEvent('openvisit', {
                detail: { visit: this.visit },
                bubbles: true,
                composed: true
            })
        );
    }

    handleCardKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleCardClick();
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    normalizeStatus(value) {
        return (value || '')
            .toString()
            .trim()
            .toLowerCase()
            .replace(/[_-]+/g, ' ')
            .replace(/\s+/g, ' ');
    }

}