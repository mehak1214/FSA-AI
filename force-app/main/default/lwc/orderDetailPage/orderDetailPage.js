import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import currencyCode from '@salesforce/i18n/currency';
import getOrderDetail from '@salesforce/apex/OrdersByUserController.getOrderDetail';

export default class OrderDetailPage extends LightningElement {
    _orderId;
    order;
    isLoading = true;
    errorMessage = '';

    @api
    get orderId() {
        return this._orderId;
    }
    set orderId(value) {
        if (value && value !== this._orderId) {
            this._orderId = value;
            this.loadOrderDetail();
        }
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        const nextOrderId = pageRef?.state?.c__orderId;
        if (nextOrderId && nextOrderId !== this._orderId) {
            this.orderId = nextOrderId;
        }
    }

    connectedCallback() {
        if (!this._orderId) {
            this.isLoading = false;
        }
    }

    loadOrderDetail() {
        if (!this._orderId) {
            this.isLoading = false;
            this.errorMessage = 'Order id is missing from navigation.';
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        getOrderDetail({ orderId: this._orderId })
            .then((result) => {
                this.order = result;
                this.isLoading = false;
            })
            .catch((error) => {
                this.isLoading = false;
                this.order = null;
                this.errorMessage = error?.body?.message || 'Failed to load order details.';
            });
    }

    handleBack() {
        window.history.back();
    }

    get statusBadgeClass() {
        const status = (this.order?.status || '').toLowerCase();
        const safeStatus = status.replace(/[^a-z]+/g, '-').replace(/(^-|-$)/g, '') || 'default';
        return `status-badge ${safeStatus}`;
    }

    get formattedAmount() {
        const amount = this.order?.totalAmount || 0;
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: currencyCode
        }).format(amount);
    }

    get formattedOrderStartDate() {
        if (!this.order?.orderStartDate) {
            return '-';
        }

        return new Intl.DateTimeFormat('en-US', {
            year: 'numeric',
            month: 'short',
            day: '2-digit'
        }).format(new Date(this.order.orderStartDate));
    }

    get dealerName() {
        return this.order?.dealerName || 'Not available';
    }

    get activatedByName() {
        return this.order?.activatedByName || 'Not available';
    }

    get billingAddress() {
        return this.formatAddress(
            this.order?.billingStreet,
            this.order?.billingCity,
            this.order?.billingState,
            this.order?.billingPostalCode,
            this.order?.billingCountry
        );
    }

    get shippingAddress() {
        return this.formatAddress(
            this.order?.shippingStreet,
            this.order?.shippingCity,
            this.order?.shippingState,
            this.order?.shippingPostalCode,
            this.order?.shippingCountry
        );
    }

    get description() {
        return this.order?.description || 'No description provided.';
    }

    get orderType() {
        return this.order?.orderType || 'N/A';
    }

    get itemsCount() {
        return this.order?.productCount || 0;
    }

    formatAddress(street, city, state, postalCode, country) {
        const line1 = street || '';
        const line2Parts = [city, state, postalCode].filter(Boolean);
        const line2 = line2Parts.join(', ');
        const parts = [line1, line2, country].filter(Boolean);

        return parts.length ? parts.join(' | ') : 'Not available';
    }
}