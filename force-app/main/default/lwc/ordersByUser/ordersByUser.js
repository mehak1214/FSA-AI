import { LightningElement, track, api } from 'lwc';
import currencyCode from '@salesforce/i18n/currency';
import getOrdersByFranchiseId from '@salesforce/apex/OrdersByUserController.getOrdersByActivatedByUser';
import getOrdersByFranchiseIdWithStatus from '@salesforce/apex/OrdersByUserController.getOrdersByActivatedByUserWithStatus';
import getOrderDetail from '@salesforce/apex/OrdersByUserController.getOrderDetail';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class OrdersByUser extends LightningElement {

    /* =========================================================
       TRACKED PROPERTIES
       ========================================================= */
    @track orders          = [];
    @track isLoading       = false;
    @track errorMessage    = '';
    @track selectedStatus  = 'All';
    @track selectedOrderTab = 'ALL';
    @track isDetailOpen    = false;   // true = detail view, false = list view
    @track isDetailLoading = false;
    @track selectedOrder   = null;
    @track isCreateCaseModalOpen = false;
    _visitFranchiseId      = null;

    @api
    get visitFranchiseId() {
        return this._visitFranchiseId;
    }

    set visitFranchiseId(value) {
        const nextFranchiseId = value || null;
        if (nextFranchiseId === this._visitFranchiseId) return;
        this._visitFranchiseId = nextFranchiseId;
        this.loadOrders();
    }

    /* =========================================================
       STATUS OPTIONS
       ========================================================= */
    statusOptions = [
        { label: 'All',       value: 'All' },
        { label: 'Draft',     value: 'Draft' },
        { label: 'Activated', value: 'Activated' },
        { label: 'Completed', value: 'Completed' },
        { label: 'Cancelled', value: 'Cancelled' }
    ];

    /* =========================================================
       GETTERS
       ========================================================= */
    get hasOrders() {
        return this.visibleOrders && this.visibleOrders.length > 0;
    }

    get noOrdersToDisplay() {
        return !this.isLoading && !this.hasOrders && !this.errorMessage;
    }

    get isAllTab()     { return this.selectedOrderTab === 'ALL'; }
    get isSampleTab()  { return this.selectedOrderTab === 'SAMPLE'; }
    get isRegularTab() { return this.selectedOrderTab === 'REGULAR'; }

    get allTabClass()     { return `orders-tab${this.isAllTab     ? ' active' : ''}`; }
    get sampleTabClass()  { return `orders-tab${this.isSampleTab  ? ' active' : ''}`; }
    get regularTabClass() { return `orders-tab${this.isRegularTab ? ' active' : ''}`; }

    get visibleOrders() {
        if (!this.orders || this.orders.length === 0) return [];
        if (this.selectedOrderTab === 'ALL') return this.orders;
        return this.orders.filter(o => this.matchesOrderTab(o.orderType));
    }

    /* =========================================================
       LIFECYCLE
       ========================================================= */
    connectedCallback() {
        this.loadOrders();
    }

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
                    formattedOrderDate: this.formatDate(order.orderDate)
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
    handleStatusChange(event) {
        this.selectedStatus = event.detail.value;
        this.loadOrders();
    }

    handleTabChange(event) {
        this.selectedOrderTab = event.currentTarget.dataset.tab;
    }

    handleCardClick(event) {
        const orderId = event.currentTarget.dataset.orderId;
        this.openOrderDetail(orderId);
    }

    openOrderDetail(orderId) {
        this.isDetailOpen    = true;
        this.isDetailLoading = true;
        this.selectedOrder   = null;

        getOrderDetail({ orderId })
            .then(result => {
                this.selectedOrder = {
                    ...result,
                    orderType:               result.orderType || 'N/A',
                    productCount:            result.productCount || 0,
                    formattedAmount:         this.formatCurrency(result.totalAmount),
                    formattedOrderStartDate: this.formatDate(result.orderStartDate),
                    billingAddress:          this.formatAddress(
                        result.billingStreet, result.billingCity,
                        result.billingState,  result.billingPostalCode, result.billingCountry
                    ),
                    shippingAddress: this.formatAddress(
                        result.shippingStreet, result.shippingCity,
                        result.shippingState,  result.shippingPostalCode, result.shippingCountry
                    )
                };
                this.isDetailLoading = false;
            })
            .catch(error => {
                this.isDetailLoading = false;
                this.handleError('Failed to load order details', error);
            });
    }

    // "Back to Orders" — returns to list view
    handleCloseDetail() {
        this.isDetailOpen  = false;
        this.selectedOrder = null;
    }

    // Handle opening Create Case modal
    handleOpenCreateCase() {
        const createCaseModal = this.template.querySelector('c-create-case-modal');
        if (createCaseModal && this.selectedOrder) {
            createCaseModal.openModal(
                this.selectedOrder.orderId,
                this.selectedOrder.accountId
            );
        }
    }

    // Handle case creation success
    handleCaseCreated(event) {
        const { caseId, caseNumber } = event.detail;
        this.showToast('Success', `Case ${caseNumber} has been created and submitted for approval!`, 'success');
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    /* =========================================================
       UTILITIES
       ========================================================= */
    formatCurrency(amount) {
        return new Intl.NumberFormat('en-US', {
            style:    'currency',
            currency: currencyCode
        }).format(amount || 0);
    }

    formatDate(dateValue) {
        if (!dateValue) return '-';
        return new Intl.DateTimeFormat('en-US', {
            year: 'numeric', month: 'short', day: '2-digit'
        }).format(new Date(dateValue));
    }

    formatAddress(street, city, state, postalCode, country) {
        const line2 = [city, state, postalCode].filter(Boolean).join(', ');
        const parts = [street, line2, country].filter(Boolean);
        return parts.length ? parts.join(' | ') : 'Not available';
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