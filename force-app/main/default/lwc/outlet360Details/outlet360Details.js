import { api, LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getOutlet360Summary from '@salesforce/apex/Outlet360Controller.getOutlet360Summary';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';

export default class Outlet360Details extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    relatedLists = [];
    recentOrders = [];
    allOrders = [];
    orderProducts = [];
    recentInvoices = [];
    isLoading = false;
    loadError;
    scannedRelationships = 0;
    totalRelationships = 0;
    isTruncated = false;
    pastRevenue = 0;
    ordersCount = 0;
    totalOrdersCount = 0;
    invoicesCount = 0;
    ordersObjectApiName;
    invoicesObjectApiName;
    outletName;
    outletCode;
    outletStatus;
    outletPhone;
    outletAddress;
    ownerName;
    ownerEmail;
    isOrderModalOpen = false;
    _lastLoadKey;

    contacts = [];
    contactsError;

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Contacts',
        fields: ['Contact.Id', 'Contact.Name', 'Contact.Title', 'Contact.Phone', 'Contact.Email']
    })
    wiredContacts({ data, error }) {
        if (data) {
            this.contacts = data.records.map(r => {
                const f = r.fields;
                const phone = f.Phone?.value;
                const email = f.Email?.value;
                const name = f.Name?.value || '--';
                const initials = name
                    .split(' ')
                    .filter(Boolean)
                    .slice(0, 2)
                    .map(w => w[0].toUpperCase())
                    .join('');
                return {
                    rowKey: f.Id?.value || r.id,
                    name,
                    initials,
                    title: f.Title?.value || null,
                    phone: phone || null,
                    email: email || null,
                    phoneHref: phone ? `tel:${phone}` : null,
                    emailHref: email ? `mailto:${email}` : null
                };
            });
            this.contactsError = null;
        } else if (error) {
            this.contacts = [];
            this.contactsError = error?.body?.message || 'Unable to load contacts.';
        }
    }
    pendingAmount = 0;
    overdueCount = 0;
    lastPaymentDate = null;
    //customreRating;
    // Payment rating: average of Payment_Score__c field from all related Payment records
    paymentRating = 0;
    // Visit rating: average of Rating field from all related Visit records
    visitRating = 0;

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        // Keep component state aligned when route params are updated in-place.
        const state = pageRef?.state || {};
        const stateRecordId = state.c__recordId;
        const stateObjectApiName = state.c__objectApiName;

        let didChange = false;
        if (stateRecordId && stateRecordId !== this.recordId) {
            this.recordId = stateRecordId;
            didChange = true;
        }
        if (stateObjectApiName && stateObjectApiName !== this.objectApiName) {
            this.objectApiName = stateObjectApiName;
            didChange = true;
        }

        if (didChange) {
            this.loadData();
        }
    }

    connectedCallback() {
        // Handles contexts where pageRef wiring is delayed in mobile containers.
        this.initializeFromUrl();
        this.loadData();
    }

    initializeFromUrl() {
        try {
            const params = new URLSearchParams(window.location.search);
            const urlRecordId = params.get('c__recordId');
            const urlObjectApiName = params.get('c__objectApiName');

            if (urlRecordId && !this.recordId) {
                this.recordId = urlRecordId;
            }
            if (urlObjectApiName && !this.objectApiName) {
                this.objectApiName = urlObjectApiName;
            }
        } catch (error) {
            // no-op
        }
    }

    get hasRecordContext() {
        return !!this.recordId;
    }

    get hasRelatedLists() {
        return this.relatedLists.length > 0;
    }

    get resolvedObjectApiName() {
        return this.objectApiName || 'Account';
    }

    get relatedSectionTitle() {
        return `Related Data (${this.relatedLists.length})`;
    }

    get displayOutletName() {
        return this.outletName || 'Outlet';
    }

    get avatarLetter() {
        return this.outletName ? this.outletName.charAt(0).toUpperCase() : 'O';
    }

    get ownerEmailHref() {
        return this.ownerEmail ? `mailto:${this.ownerEmail}` : null;
    }

    get statusPillClass() {
        if (!this.outletStatus) return 'status-pill';
        const s = this.outletStatus.toLowerCase().trim();
        return s === 'active' ? 'status-pill status-text-active' : 'status-pill status-text-inactive';
    }

    get hasOutletSubInfo() {
        return !!(this.outletCode || this.outletStatus || this.outletPhone || this.outletAddress);
    }

    get hasRecentOrders() {
        return this.recentOrders.length > 0;
    }

    get hasAllOrders() {
        return this.allOrders.length > 0;
    }

    get hasOrderProducts() {
        return this.orderProducts.length > 0;
    }

    get hasRecentInvoices() {
        return this.recentInvoices.length > 0;
    }

    get pastRevenueLabel() {
        return this.formatCurrency(this.pastRevenue);
    }

    get ordersSectionLabel() {
        return `Orders (${this.totalOrdersCount || this.ordersCount})`;
    }

    get invoicesSectionLabel() {
        return `Invoices (${this.invoicesCount})`;
    }

    get pendingAmountLabel() {
        return this.formatCurrency(this.pendingAmount);
    }

    get lastPaymentDateLabel() {
        if (!this.lastPaymentDate) return '--';
        return this.formatDate(this.lastPaymentDate);
    }

    get hasPaymentOverview() {
        return this.pendingAmount > 0 || this.overdueCount > 0 || this.lastPaymentDate;
    }

    /**
     * Calculate and return the Customer Rating based on Visit and Payment ratings
     * Formula: Customer Rating = (Visit Rating × 0.6) + (Payment Rating × 0.4)
     * This weighted average gives more importance to visit ratings (60%) over payment ratings (40%)
     * @returns {string} Customer rating with exactly one decimal place, or '--' if no data available
     */
    get customerRating() {
        // Return '--' if both ratings are zero (no data available)
        if (this.visitRating === 0 && this.paymentRating === 0) {
            return '--';
        }

        // Calculate customer rating using the weighted formula
        const weightedRating = (this.visitRating * 0.6) + (this.paymentRating * 0.4);
        
        // Return value with exactly one decimal place (e.g., 3.0, 4.2, 5.1)
        return weightedRating.toFixed(1);
    }

    get ratingValue() {
        // Returns numeric value for star display, or 0 if no data
        if (this.visitRating === 0 && this.paymentRating === 0) {
            return 0;
        }
        return parseFloat((this.visitRating * 0.6) + (this.paymentRating * 0.4));
    }

    get starList() {
        // Create a list of 5 stars with appropriate fill status based on rating
        const rating = this.ratingValue;
        return [1, 2, 3, 4, 5].map(n => ({
            value: n,
            label: `${n} star${n > 1 ? 's' : ''}`,
            cssClass: n <= Math.round(rating) ? 'star-btn star-filled' : 'star-btn star-empty'
        }));
    }

    get statusTextClass() {
        // Return appropriate CSS class based on status value
        if (!this.outletStatus) return '';
        const status = this.outletStatus.toLowerCase().trim();
        return status === 'active' ? 'status-text-active' : 'status-text-inactive';
    }

    get statusLine() {
        if (!this.hasRecordContext) {
            return 'Missing record context.';
        }
        return `Scanned ${this.scannedRelationships} of ${this.totalRelationships} relationships`;
    }

    get showViewAllOrders() {
        return (this.totalOrdersCount || 0) > 5;
    }

    get hasContacts() {
        return this.contacts.length > 0;
    }

    get contactsSectionLabel() {
        return `Contacts (${this.contacts.length})`;
    }

    loadData() {
        if (!this.hasRecordContext) {
            return;
        }

        const currentKey = `${this.recordId}:${this.objectApiName}`;
        if (this._lastLoadKey === currentKey && this.isLoading) {
            return;
        }

        this._lastLoadKey = currentKey;
        this.isLoading = true;
        this.loadError = null;

        getOutlet360Summary({
            recordId: this.recordId,
            objectApiName: this.resolvedObjectApiName
        })
            .then((result) => {
                // Normalize server response for template rendering.
                this.relatedLists = (result?.relatedLists || []).map((item) => ({
                    ...item,
                    rowKey: `${item.childObjectApiName}:${item.referenceFieldApiName}`
                }));
                this.outletName = result?.outletName;
                this.outletCode = result?.outletCode;
                this.outletStatus = result?.outletStatus;
                this.outletPhone = result?.outletPhone;
                this.outletAddress = result?.outletAddress;
                this.ownerName = result?.ownerName;
                this.ownerEmail = result?.ownerEmail;
                this.pastRevenue = result?.pastRevenue || 0;
                this.ordersCount = result?.ordersCount || 0;
                this.totalOrdersCount = result?.totalOrdersCount || this.ordersCount;
                this.invoicesCount = result?.invoicesCount || 0;
                this.ordersObjectApiName = result?.ordersObjectApiName;
                this.invoicesObjectApiName = result?.invoicesObjectApiName;
                this.recentOrders = (result?.recentOrders || []).map((item) => ({
                    ...item,
                    rowKey: `order-${item.recordId}`,
                    amountLabel: this.formatCurrency(item.amount),
                    dateLabel: this.formatDate(item.recordDate)
                }));
                this.recentInvoices = (result?.recentInvoices || []).map((item) => ({
                    ...item,
                    rowKey: `invoice-${item.recordId}`,
                    amountLabel: this.formatCurrency(item.amount),
                    dateLabel: this.formatDate(item.recordDate)
                }));
                this.allOrders = (result?.allOrders || []).map((item) => ({
                    ...item,
                    rowKey: `all-order-${item.recordId}`,
                    amountLabel: this.formatCurrency(item.amount),
                    dateLabel: this.formatDate(item.recordDate)
                }));
                this.orderProducts = (result?.orderProducts || []).map((item, index) => ({
                    ...item,
                    rowKey: `order-product-${item.orderItemId || index}`,
                    unitPriceLabel: this.formatCurrency(item.unitPrice),
                    totalPriceLabel: this.formatCurrency(item.totalPrice)
                }));
                this.scannedRelationships = result?.scannedRelationships || 0;
                this.totalRelationships = result?.totalRelationships || 0;
                this.isTruncated = !!result?.isTruncated;
                this.pendingAmount = result?.pendingAmount || 0;
                this.overdueCount = result?.overdueCount || 0;
                this.lastPaymentDate = result?.lastPaymentDate || null;
                // Retrieve payment rating (average of payment scores) from controller
                this.paymentRating = result?.paymentRating || 0;
                // Retrieve visit rating (average of visit ratings) from controller
                this.visitRating = result?.visitRating || 0;
            })
            .catch((error) => {
                this.relatedLists = [];
                this.outletName = null;
                this.outletCode = null;
                this.outletStatus = null;
                this.outletPhone = null;
                this.outletAddress = null;
                this.ownerName = null;
                this.ownerEmail = null;
                this.recentOrders = [];
                this.allOrders = [];
                this.orderProducts = [];
                this.recentInvoices = [];
                this.pastRevenue = 0;
                this.ordersCount = 0;
                this.totalOrdersCount = 0;
                this.invoicesCount = 0;
                this.scannedRelationships = 0;
                this.totalRelationships = 0;
                this.isTruncated = false;
                this.pendingAmount = 0;
                this.overdueCount = 0;
                this.lastPaymentDate = null;
                // Reset payment and visit ratings on error
                this.paymentRating = 0;
                this.visitRating = 0;
                this.loadError = error?.body?.message || 'Unable to load outlet 360 details.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleBack() {
        try {
            if (window.history.length > 1) {
                window.history.back();
                return;
            }
        } catch (error) {
            // Continue with fallback navigation.
        }

        // Navigate to the visit detail component using standard__component
        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: {
                componentName: 'c__visitDetailPage'
            }
        });
    }

    handleRefresh() {
        this.loadData();
    }

    handleOpenOrderModal() {
        this.isOrderModalOpen = true;
    }

    handleCloseOrderModal() {
        this.isOrderModalOpen = false;
    }

    formatCurrency(value) {
        const numeric = Number(value || 0);
        return new Intl.NumberFormat('en-IN', {
            style: 'currency',
            currency: 'INR',
            maximumFractionDigits: 2
        }).format(numeric);
    }

    formatDate(value) {
        if (!value) return '--';
        try {
            return new Date(value).toLocaleDateString('en-IN', {
                day: '2-digit',
                month: 'short',
                year: 'numeric'
            });
        } catch (error) {
            return '--';
        }
    }
}