import { api, LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getOutlet360Summary from '@salesforce/apex/Outlet360Controller.getOutlet360Summary';
import createContact from '@salesforce/apex/Outlet360Controller.createContact';
import { getRelatedListRecords, refresh } from 'lightning/uiRelatedListApi';

export default class Outlet360Details extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    relatedLists = [];
    recentOrders = [];
    allOrders = [];
    orderProducts = [];
    allOrderProducts = [];
    cases = [];
    allCases = [];
    assets = [];
    allAssets = [];
    recentInvoices = [];
    isLoading = false;
    loadError;
    scannedRelationships = 0;
    totalRelationships = 0;
    isTruncated = false;
    pastRevenue = 0;
    ordersCount = 0;
    totalOrdersCount = 0;
    orderProductsCount = 0;
    totalOrderProductsCount = 0;
    casesCount = 0;
    totalCasesCount = 0;
    assetsCount = 0;
    totalAssetsCount = 0;
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
    isOrderModalOpen = false;   // kept for backward compat — dialogs use showModal() now
    isProductModalOpen = false;
    isCaseModalOpen = false;
    isAssetModalOpen = false;
    // Custom tab state (replaces lightning-tabset)
    activeTab = 'assets';
    sourceVisitId;
    // Add Contact state
    isSavingContact = false;
    contactSaveError;
    newContact = { salutation: '', firstName: '', lastName: '', phone: '', email: '' };
    salutationError;
    lastNameError;
    _lastLoadKey;

    contacts = [];
    contactsError;
    _wiredContactsResult;

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Contacts',
        fields: ['Contact.Id', 'Contact.Name', 'Contact.Title', 'Contact.Phone', 'Contact.Email', 'Contact.Primary_Contact__c']
    })
    wiredContacts(result) {
        this._wiredContactsResult = result;
        const { data, error } = result;
        if (data) {
            const mapped = data.records.map(r => {
                const f = r.fields;
                const phone = f.Phone?.value;
                const email = f.Email?.value;
                const name  = f.Name?.value || '--';
                const initials = name.split(' ').filter(Boolean).slice(0, 2)
                    .map(w => w[0].toUpperCase()).join('');
                return {
                    rowKey    : f.Id?.value || r.id,
                    name, initials,
                    title     : f.Title?.value || null,
                    isPrimary : !!f.Primary_Contact__c?.value,
                    phone     : phone || null,
                    email     : email || null,
                    phoneHref : phone ? `tel:${phone}`    : null,
                    emailHref : email ? `mailto:${email}` : null
                };
            });
            // Primary contacts first, then the rest
            this.contacts = [
                ...mapped.filter(c =>  c.isPrimary),
                ...mapped.filter(c => !c.isPrimary)
            ];
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
        const stateVisitId = state.c__visitId;

        let didChange = false;
        if (stateRecordId && stateRecordId !== this.recordId) {
            this.recordId = stateRecordId;
            didChange = true;
        }
        if (stateObjectApiName && stateObjectApiName !== this.objectApiName) {
            this.objectApiName = stateObjectApiName;
            didChange = true;
        }
        if (stateVisitId && stateVisitId !== this.sourceVisitId) {
            this.sourceVisitId = stateVisitId;
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
            const urlVisitId = params.get('c__visitId');

            if (urlRecordId && !this.recordId) {
                this.recordId = urlRecordId;
            }
            if (urlObjectApiName && !this.objectApiName) {
                this.objectApiName = urlObjectApiName;
            }
            if (urlVisitId && !this.sourceVisitId) {
                this.sourceVisitId = urlVisitId;
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
        return this.outletName || 'Store';
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

    get hasCases() {
        return this.cases.length > 0;
    }

    get hasAssets() {
        return this.assets.length > 0;
    }

    get hasAllAssets() {
        return this.allAssets.length > 0;
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

    get casesSectionLabel() {
        return `Cases (${this.totalCasesCount || this.casesCount})`;
    }

    get assetsSectionLabel() {
        return `Assets (${this.totalAssetsCount || this.assetsCount || 0})`;
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

    get showViewAllOrderProducts() {
        return (this.totalOrderProductsCount || 0) > 5;
    }

    get showViewAllCases() {
        return (this.totalCasesCount || 0) > 5;
    }

    get showViewAllAssets() {
        return (this.totalAssetsCount || 0) > 5;
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

                // Placeholder — remove once real invoice functionality is built
                if (this.recentInvoices.length === 0) {
                    const today = new Date();
                    const invoiceDate = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 3);
                    this.recentInvoices = [{
                        rowKey:      'invoice-demo-001',
                        name:        'INV-2025-00142',
                        amountLabel: this.formatCurrency(1450),
                        dateLabel:   this.formatDate(invoiceDate.toISOString()),
                        status:      'Paid'
                    }];
                    this.invoicesCount = 1;
                }
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
                this.assets = (result?.assets || []).map((item, index) => ({
                    ...item,
                    rowKey: `asset-${item.assetId || index}`,
                    lastAuditDateLabel: this.formatDate(item.lastAuditDate),
                    outletName: item.outletName || '--'
                }));
                this.allAssets = (result?.allAssets || []).map((item, index) => ({
                    ...item,
                    rowKey: `all-asset-${item.assetId || index}`,
                    lastAuditDateLabel: this.formatDate(item.lastAuditDate),
                    outletName: item.outletName || '--'
                }));
                this.assetsCount = result?.assetsCount || this.assets.length;
                this.totalAssetsCount = result?.totalAssetsCount || this.assetsCount;
                this.allOrderProducts = (result?.allOrderProducts || []).map((item, index) => ({
                    ...item,
                    rowKey: `all-order-product-${item.orderItemId || index}`,
                    unitPriceLabel: this.formatCurrency(item.unitPrice),
                    totalPriceLabel: this.formatCurrency(item.totalPrice)
                }));
                this.orderProductsCount = result?.orderProductsCount || 0;
                this.totalOrderProductsCount = result?.totalOrderProductsCount || this.orderProductsCount;
                this.cases = (result?.cases || []).map((item, index) => ({
                    ...item,
                    rowKey: `case-${item.caseId || index}`,
                    totalPriceLabel: this.formatCurrency(item.totalPrice)
                }));
                this.allCases = (result?.allCases || []).map((item, index) => ({
                    ...item,
                    rowKey: `all-case-${item.caseId || index}`,
                    totalPriceLabel: this.formatCurrency(item.totalPrice)
                }));
                this.casesCount = result?.casesCount || 0;
                this.totalCasesCount = result?.totalCasesCount || this.casesCount;
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
                this.allOrderProducts = [];
                this.assets = [];
                this.allAssets = [];
                this.assetsCount = 0;
                this.totalAssetsCount = 0;
                this.orderProductsCount = 0;
                this.totalOrderProductsCount = 0;
                this.cases = [];
                this.allCases = [];
                this.recentInvoices = [];
                this.pastRevenue = 0;
                this.ordersCount = 0;
                this.totalOrdersCount = 0;
                this.casesCount = 0;
                this.totalCasesCount = 0;
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
                this.loadError = error?.body?.message || 'Unable to load store 360 details.';
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ── Custom tab getters ────────────────────────────────────────────
    get isTabAssets()   { return this.activeTab === 'assets';   }
    get isTabOrders()   { return this.activeTab === 'orders';   }
    get isTabProducts() { return this.activeTab === 'products'; }
    get isTabCases()    { return this.activeTab === 'cases';    }
    get tabClassAssets()   { return `tab-pill${this.activeTab === 'assets'   ? ' active' : ''}`; }
    get tabClassOrders()   { return `tab-pill${this.activeTab === 'orders'   ? ' active' : ''}`; }
    get tabClassProducts() { return `tab-pill${this.activeTab === 'products' ? ' active' : ''}`; }
    get tabClassCases()    { return `tab-pill${this.activeTab === 'cases'    ? ' active' : ''}`; }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    // ── Contacts: visible slice + view-all gate ───────────────────────
    get visibleContacts() {
        return this.contacts.slice(0, 2);
    }

    get showViewAllContacts() {
        return this.contacts.length > 2;
    }

    // ── All Contacts dialog ───────────────────────────────────────────
    _openContactsDialog() {
        const dlg = this.template.querySelector('dialog.contacts-dialog');
        if (dlg && !dlg.open) dlg.showModal();
    }
    _closeContactsDialog() {
        const dlg = this.template.querySelector('dialog.contacts-dialog');
        if (dlg && dlg.open) dlg.close();
    }
    handleContactsDialogClose() { /* Esc key — dialog already closed */ }
    handleContactsBackdropClick(event) {
        if (event.target === event.currentTarget) this._closeContactsDialog();
    }
    handleOpenContactsModal()  { this._openContactsDialog();  }
    handleCloseContactsModal() { this._closeContactsDialog(); }

    _openAssetsDialog() {
        const dlg = this.template.querySelector('dialog.assets-dialog');
        if (dlg && !dlg.open) dlg.showModal();
    }
    _closeAssetsDialog() {
        const dlg = this.template.querySelector('dialog.assets-dialog');
        if (dlg && dlg.open) dlg.close();
    }
    handleAssetsDialogClose() { /* Esc key — dialog already closed */ }
    handleAssetsBackdropClick(event) {
        if (event.target === event.currentTarget) this._closeAssetsDialog();
    }
    handleOpenAssetModal()  { this._openAssetsDialog();  }
    handleCloseAssetModal() { this._closeAssetsDialog(); }

    // ── Add Contact dialog ────────────────────────────────────────────
    _openAddContactDialog() {
        const dlg = this.template.querySelector('dialog.add-contact-dialog');
        if (dlg && !dlg.open) dlg.showModal();
    }
    _closeAddContactDialog() {
        const dlg = this.template.querySelector('dialog.add-contact-dialog');
        if (dlg && dlg.open) dlg.close();
    }
    handleAddContactDialogClose() { /* Esc key — dialog already closed */ }
    handleAddContactBackdropClick(event) {
        if (event.target === event.currentTarget) this._closeAddContactDialog();
    }

    // ── Add Contact: CSS class getters ────────────────────────────────
    get salutationSelectClass() {
        return this.salutationError ? 'form-select has-error' : 'form-select';
    }
    get lastNameInputClass() {
        return this.lastNameError ? 'form-input has-error' : 'form-input';
    }

    // ── Add Contact: open / close / field / save ──────────────────────
    handleOpenAddContactModal() {
        this._closeContactsDialog();
        this.newContact       = { salutation: '', firstName: '', lastName: '', phone: '', email: '' };
        this.salutationError  = null;
        this.lastNameError    = null;
        this.contactSaveError = null;
        this._openAddContactDialog();
    }
    handleCloseAddContactModal() {
        this._closeAddContactDialog();
    }
    handleContactFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.newContact = { ...this.newContact, [field]: value };
        if (field === 'salutation') this.salutationError = null;
        if (field === 'lastName')   this.lastNameError   = null;
    }
    handleSaveContact() {
        let valid = true;
        if (!this.newContact.salutation) {
            this.salutationError = 'Salutation is required.';
            valid = false;
        }
        if (!this.newContact.lastName || !this.newContact.lastName.trim()) {
            this.lastNameError = 'Last Name is required.';
            valid = false;
        }
        if (!valid) return;

        this.isSavingContact  = true;
        this.contactSaveError = null;

        createContact({
            accountId  : this.recordId,
            salutation : this.newContact.salutation,
            firstName  : this.newContact.firstName  || null,
            lastName   : this.newContact.lastName.trim(),
            phone      : this.newContact.phone       || null,
            email      : this.newContact.email       || null
        })
            .then(() => {
                this._closeAddContactDialog();
                if (this._wiredContactsResult) refresh(this._wiredContactsResult);
            })
            .catch(err => {
                this.contactSaveError = err?.body?.message || 'Unable to save contact. Please try again.';
            })
            .finally(() => {
                this.isSavingContact = false;
            });
    }

    // ── Orders dialog ─────────────────────────────────────────────────
    _openOrdersDialog() {
        const dlg = this.template.querySelector('dialog.orders-dialog');
        if (dlg && !dlg.open) dlg.showModal();
    }
    _closeOrdersDialog() {
        const dlg = this.template.querySelector('dialog.orders-dialog');
        if (dlg && dlg.open) dlg.close();
    }
    handleOrdersDialogClose()   { /* Esc — already closed */ }
    handleOrdersBackdropClick(event) {
        if (event.target === event.currentTarget) this._closeOrdersDialog();
    }
    handleOpenOrderModal()  { this._openOrdersDialog();  }
    handleCloseOrderModal() { this._closeOrdersDialog(); }

    // ── Order Products dialog ──────────────────────────────────────────
    _openProductsDialog() {
        const dlg = this.template.querySelector('dialog.products-dialog');
        if (dlg && !dlg.open) dlg.showModal();
    }
    _closeProductsDialog() {
        const dlg = this.template.querySelector('dialog.products-dialog');
        if (dlg && dlg.open) dlg.close();
    }
    handleProductsDialogClose()   { /* Esc — already closed */ }
    handleProductsBackdropClick(event) {
        if (event.target === event.currentTarget) this._closeProductsDialog();
    }
    handleOpenProductModal()  { this._openProductsDialog();  }
    handleCloseProductModal() { this._closeProductsDialog(); }

    // ── Cases dialog ───────────────────────────────────────────────────
    _openCasesDialog() {
        const dlg = this.template.querySelector('dialog.cases-dialog');
        if (dlg && !dlg.open) dlg.showModal();
    }
    _closeCasesDialog() {
        const dlg = this.template.querySelector('dialog.cases-dialog');
        if (dlg && dlg.open) dlg.close();
    }
    handleCasesDialogClose()   { /* Esc — already closed */ }
    handleCasesBackdropClick(event) {
        if (event.target === event.currentTarget) this._closeCasesDialog();
    }
    handleOpenCaseModal()  { this._openCasesDialog();  }
    handleCloseCaseModal() { this._closeCasesDialog(); }

    // ── Order Detail ──────────────────────────────────────────────────
    handleOrderClick(event) {
        const orderId = event.currentTarget.dataset.id;
        if (!orderId) return;
        // Close the All Orders dialog if it was open, then open detail
        this._closeOrdersDialog();
        const orderDetail = this.template.querySelector('c-order-detail');
        if (orderDetail) orderDetail.openForOrder(orderId);
    }

    handleOrderDetailClose() {
        // No-op — child closes itself; hook available for future use
    }

    handleCaseClick(event) {
        const caseId = event.currentTarget.dataset.id;
        if (!caseId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: caseId,
                actionName: 'view'
            }
        });
    }

    handleAssetClick(event) {
        const assetId = event.currentTarget.dataset.id;
        if (!assetId) return;
        this._closeAssetsDialog();
        const assetDetail = this.template.querySelector('c-asset-detail');
        if (assetDetail) {
            assetDetail.openForAsset(assetId);
        }
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