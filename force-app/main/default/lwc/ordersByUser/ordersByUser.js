import { LightningElement, track, api } from 'lwc';
import currencyCode from '@salesforce/i18n/currency';
import getOrdersByFranchiseId from '@salesforce/apex/OrdersByUserController.getOrdersByActivatedByUser';
import getOrdersByFranchiseIdWithStatus from '@salesforce/apex/OrdersByUserController.getOrdersByActivatedByUserWithStatus';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class OrdersByUser extends LightningElement {

    /* =========================================================
       TRACKED PROPERTIES
       ========================================================= */
    @track orders           = [];
    @track isLoading        = false;
    @track errorMessage     = '';
    @track selectedStatus   = 'All';
    @track selectedOrderTab = 'ALL';
    _visitFranchiseId       = null;

    @api
    get visitFranchiseId() {
        return this._visitFranchiseId;
    }

    set visitFranchiseId(value) {
        const next = value || null;
        if (next === this._visitFranchiseId) return;
        this._visitFranchiseId = next;
        this.loadOrders();
    }

    /* =========================================================
       LIFECYCLE
       ========================================================= */
    connectedCallback() {
        this.loadOrders();
    }

    /* =========================================================
       GETTERS
       ========================================================= */
    get hasOrders() {
        return this.visibleOrders.length > 0;
    }

    get noOrdersToDisplay() {
        return !this.isLoading && !this.hasOrders && !this.errorMessage;
    }

    get visibleOrders() {
        if (!this.orders || this.orders.length === 0) return [];
        if (this.selectedOrderTab === 'ALL') return this.orders;
        return this.orders.filter(o => this.matchesOrderTab(o.orderType));
    }

    get allTabClass()     { return `obu-tab-pill${this.selectedOrderTab === 'ALL'     ? ' active' : ''}`; }
    get sampleTabClass()  { return `obu-tab-pill${this.selectedOrderTab === 'SAMPLE'  ? ' active' : ''}`; }
    get regularTabClass() { return `obu-tab-pill${this.selectedOrderTab === 'REGULAR' ? ' active' : ''}`; }

    /* =========================================================
       LOAD ORDERS
       ========================================================= */
    loadOrders() {
        if (!this._visitFranchiseId) {
            this.orders    = [];
            this.isLoading = false;
            return;
        }

        this.isLoading    = true;
        this.errorMessage = '';

        const method = this.selectedStatus === 'All'
            ? getOrdersByFranchiseId
            : getOrdersByFranchiseIdWithStatus;

        const params = this.selectedStatus === 'All'
            ? { visitFranchiseId: this._visitFranchiseId }
            : { status: this.selectedStatus, visitFranchiseId: this._visitFranchiseId };

        method(params)
            .then(result => {
                this.orders = result.map(order => ({
                    ...order,
                    orderType:          order.orderType || 'N/A',
                    productCount:       order.productCount || 0,
                    formattedAmount:    this.formatCurrency(order.totalAmount),
                    formattedOrderDate: this.formatDate(order.orderDate),
                    statusClass:        this.getStatusClass(order.status)
                }));
                this.isLoading = false;
            })
            .catch(error => {
                this.handleError('Failed to load orders', error);
                this.isLoading = false;
            });
    }

    /* =========================================================
       EVENT HANDLERS
       ========================================================= */
    handleTabChange(event) {
        this.selectedOrderTab = event.currentTarget.dataset.tab;
    }

    handleCardClick(event) {
        const orderId = event.currentTarget.dataset.orderId;
        if (!orderId) return;
        // Dispatch to parent (visitDetail) which opens c-order-detail
        this.dispatchEvent(new CustomEvent('orderselected', {
            detail: { order: { orderId } },
            bubbles: true,
            composed: true
        }));
    }

    /* =========================================================
       UTILITIES
       ========================================================= */
    getStatusClass(status) {
        const map = {
            'Draft':     'obu-status-badge obu-status-draft',
            'Activated': 'obu-status-badge obu-status-active',
            'Completed': 'obu-status-badge obu-status-done',
            'Cancelled': 'obu-status-badge obu-status-cancelled'
        };
        return map[status] || 'obu-status-badge obu-status-default';
    }

    formatCurrency(amount) {
        return new Intl.NumberFormat('en-IN', {
            style:                 'currency',
            currency:              currencyCode || 'INR',
            maximumFractionDigits: 2
        }).format(amount || 0);
    }

    formatDate(dateValue) {
        if (!dateValue) return '--';
        try {
            return new Date(dateValue).toLocaleDateString('en-IN', {
                day: '2-digit', month: 'short', year: 'numeric'
            });
        } catch { return '--'; }
    }

    handleError(message, error) {
        console.error(message, error);
        this.errorMessage = message;
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }

    matchesOrderTab(orderTypeValue) {
        const type = (orderTypeValue || '').toLowerCase();
        if (this.selectedOrderTab === 'SAMPLE')  return type.includes('sample');
        if (this.selectedOrderTab === 'REGULAR') return type.includes('regular');
        return true;
    }
}