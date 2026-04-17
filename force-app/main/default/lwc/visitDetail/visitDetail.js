import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import checkInVisit from '@salesforce/apex/VisitController.checkInVisit';
import checkOutVisit from '@salesforce/apex/VisitController.checkOutVisit';
import getVisitDetail from '@salesforce/apex/VisitController.getVisitDetail';
import getTodayAttendance from '@salesforce/apex/VisitController.getTodayAttendance';
import uploadVisitPhoto from '@salesforce/apex/VisitController.uploadVisitPhoto';
import deleteVisitPhoto from '@salesforce/apex/VisitController.deleteVisitPhoto';
import getVisitPhoto from '@salesforce/apex/VisitController.getVisitPhoto';
import getOutletPhoto from '@salesforce/apex/VisitController.getOutletPhoto';
import saveMeetingNotes from '@salesforce/apex/VisitController.saveMeetingNotes';
import deleteAttachment from '@salesforce/apex/VisitController.deleteAttachment';
import renameAttachment from '@salesforce/apex/VisitController.renameAttachment';
import saveRatingAndFeedback from '@salesforce/apex/VisitController.saveRatingAndFeedback';
import getVisitTasks from '@salesforce/apex/VisitTaskController.getVisitTasks';
import updateTaskStatus from '@salesforce/apex/VisitTaskController.updateTaskStatus';
import getOutlet360Summary from '@salesforce/apex/Outlet360Controller.getOutlet360Summary';

export default class VisitDetail extends NavigationMixin(LightningElement) {
    _visit;
    _visitId;
    recordId;
    isLoading = false;
    _hasVisitPhoto;
    imageUrl;
    selectedPhotoId;
    outletPhotoUrl;
    actionInFlight = false;
    showOrderPanel = false;
    assetRequestSuccessMessage = '';
    // UI state for photo modal
    isPhotoModalOpen = false;
    isSchemesModalOpen = false;
    isOrdersModalOpen = false;
    recentUploadFiles = [];  // [{name, documentId}]
    meetingNotes = '';
    meetingNotesSaving = false;
    lastNoteAction = null;     // Track action: 'add', 'edit', 'delete'
    // Notes tile state
    savedNotesList = [];       // [{id, text, dateLabel}]
    showNotesInput = false;
    editingNoteId = null;      // null = new note, string id = editing existing
    wiredVisitResult;
    // Rating & Feedback
    selectedRating = 0;
    visitFeedback = '';
    ratingFeedbackSaving = false;
    ratingFeedbackSaved = false;
    // Tasks
    tasks = [];
    isLoadingTasks = false;
    expandedTaskId = null;
    blockingTask = null;
    blockReason = '';
    isActingOnTask = false;
    isLoadingRelated = false;
    isRefreshingRelated = false;
    activeRelatedTab = 'assets';
    assets = [];
    allAssets = [];
    recentOrders = [];
    allOrders = [];
    orderProducts = [];
    allOrderProducts = [];
    cases = [];
    allCases = [];
    assetRequests = [];
    allAssetRequests = [];
    assetsCount = 0;
    totalAssetsCount = 0;
    ordersCount = 0;
    totalOrdersCount = 0;
    orderProductsCount = 0;
    totalOrderProductsCount = 0;
    casesCount = 0;
    totalCasesCount = 0;
    assetRequestsCount = 0;
    totalAssetRequestsCount = 0;

    @api
    get visit() {
        return this._visit;
    }
    set visit(value) {
        const prevId = this.recordId;
        this._visit = value;
        this.recordId = value?.Id || this.recordId;
        // If this is the first time we get a real ID, load tasks immediately.
        // wiredVisit may return cached data without re-running loadVisitTasks.
        if (!prevId && this.recordId) {
            this.loadVisitTasks();
        }
    }

    @api
    get visitId() {
        return this._visitId;
    }
    set visitId(value) {
        const prevId = this.recordId;
        this._visitId = value;
        this.recordId = value || this.recordId;
        if (!prevId && this.recordId) {
            this.loadVisitTasks();
        }
    }
    @api dayStarted;
    @api dayEnded;
    @api isToday;
    pageVisitId;

    connectedCallback() {
        setTimeout(() => {
        this.loadAttendance();
        }, 300)
        // Safety net: if the visit ID is already available when the component
        // connects (e.g. passed as @api before connectedCallback), kick off
        // the task load immediately without waiting for wiredVisit to re-fire.
        if (this.currentVisitId) {
            this.loadVisitTasks();
        }
    }

    get currentVisitId() {
        // Single source for actions that can use either explicit visitId or loaded record.
        return this.recordId || this.visit?.Id;
    }

    get outletAccount() {
        return this._getField('Outlet1__r');
    }

    static DEFAULT_LAT = 18.54944;
    static DEFAULT_LON = 73.79127;

    get outletCoordinates() {
        // Supports namespaced and unpackaged location field variants.
        // Falls back to default coordinates when fields are empty.
        const account = this.outletAccount;
        const rawLat = account?.ibfsa__Outlet_Location__Latitude__s ?? account?.Outlet_Location__Latitude__s;
        const rawLon = account?.ibfsa__Outlet_Location__Longitude__s ?? account?.Outlet_Location__Longitude__s;
        const lat = (rawLat === null || rawLat === undefined) ? VisitDetail.DEFAULT_LAT : rawLat;
        const lon = (rawLon === null || rawLon === undefined) ? VisitDetail.DEFAULT_LON : rawLon;
        return { lat, lon };
    }

    loadAttendance() {
        getTodayAttendance()
            .then(att => {
                this.dayStarted = !!att;
                this.dayEnded = !!(att?.End_Time__c || att?.ibfsa__End_Time__c);
            })
            .catch(() => {
                this.dayStarted = false;
                this.dayEnded = false;
            });
    }

    handleOrderCreated(event) {
        // The placeOrder component navigates to its success page (stepFour)
        // BEFORE dispatching this event — the dialog is still open showing
        // the success screen.  We only do background data refresh here.
        // The toast is shown in handleOrderDialogClose so it fires AFTER
        // the user dismisses the dialog and the success screen is gone.
        this._orderWasCreated = true;

        // Background data refresh — non-blocking
        Promise.all([
            this.refreshVisitData({ showErrorToast: false }),
            Promise.resolve().then(() => this.loadOutletRelatedData())
        ]).catch(() => {});
    }

    handleOpenAssetRequest() {
        if (!this.currentVisitId) {
            this.showToast('Visit not found', 'Missing visit id.', 'error');
            return;
        }
        if (!this.outletRecordId) {
            this.showToast('Store unavailable', 'Store record is not available for this visit.', 'warning');
            return;
        }

        this.assetRequestSuccessMessage = '';

        const modal = this.template.querySelector('c-asset-request-form');
        if (modal) {
            modal.openModal();
        }
    }

    handleAssetRequestSubmitted(event) {
        this.assetRequestSuccessMessage = event.detail?.message || 'Request submitted — your manager will review it shortly.';
        this.showToast('Request submitted', this.assetRequestSuccessMessage, 'success');
    }



    refreshVisitData({ showErrorToast = true } = {}) {
        const visitId = this.currentVisitId;
        if (!visitId) {
            this.loadAttendance();
            return Promise.resolve();
        }

        const visitRefreshPromise = this.wiredVisitResult
            ? refreshApex(this.wiredVisitResult)
            : getVisitDetail({ visitId }).then(visitData => {
                if (!visitData) return;
                this.visit = visitData;
                this.meetingNotes = this._getFieldFromRecord(visitData, 'Meeting_Notes__c') || '';
                this._parseMeetingNotesIntoTiles(this.meetingNotes);
                this.selectedRating = Number(this._getFieldFromRecord(visitData, 'Rating__c')) || 0;
                this.visitFeedback = this._getFieldFromRecord(visitData, 'Feedback__c') || '';
                this.ratingFeedbackSaved = !!(this.selectedRating && this.visitFeedback);
                this.setIsTodayFromVisit(visitData);
                this.checkForVisitPhoto();
                this.loadOutletPhoto();
                this.loadOutletRelatedData();
            });

        return Promise.all([
            visitRefreshPromise,
            getTodayAttendance()
        ])
            .then(([, att]) => {
                this.dayStarted = !!att;
                this.dayEnded = !!(att?.End_Time__c || att?.ibfsa__End_Time__c);
                this.loadVisitTasks();
                this.dispatchEvent(new CustomEvent('refresh'));
            })
            .catch(err => {
                if (showErrorToast) {
                    this.showToast(
                        'Unable to refresh visit',
                        err?.body?.message || 'Please try again.',
                        'error'
                    );
                }
            });
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        const id = pageRef?.state?.c__visitId;
        if (id) {
            this.pageVisitId = id;
            this.visitId = id;
        }
    }

    @wire(getVisitDetail, { visitId: '$recordId' })
    wiredVisit(result) {
        this.wiredVisitResult = result;
        const { data, error } = result;
        if (data) {
            this.visit = data;
            // Force refresh attendance state
            this.loadAttendance();
            this.meetingNotes = this._getFieldFromRecord(data, 'Meeting_Notes__c') || '';
            this._parseMeetingNotesIntoTiles(this.meetingNotes);
            this.selectedRating = Number(this._getFieldFromRecord(data, 'Rating__c')) || 0;
            this.visitFeedback = this._getFieldFromRecord(data, 'Feedback__c') || '';
            this.ratingFeedbackSaved = !!(this.selectedRating && this.visitFeedback);
            this.setIsTodayFromVisit(data);
            // Check if there's a photo for this visit
            this.checkForVisitPhoto();
            // Load account/outlet photo
            this.loadOutletPhoto();
            this.loadOutletRelatedData();
            // Load tasks for this visit
            this.loadVisitTasks();
            return;
        }

        if (error) {
            this.showToast(
                'Unable to load visit',
                error?.body?.message || 'Please try again.',
                'error'
            );
        }
    }

    loadOutletRelatedData(options = {}) {
        const { preserveVisible = false } = options;
        const outletId = this.outletRecordId;
        if (!outletId) {
            this.assets = [];
            this.allAssets = [];
            this.assetsCount = 0;
            this.totalAssetsCount = 0;
            this.recentOrders = [];
            this.allOrders = [];
            this.ordersCount = 0;
            this.totalOrdersCount = 0;
            this.orderProducts = [];
            this.allOrderProducts = [];
            this.orderProductsCount = 0;
            this.totalOrderProductsCount = 0;
            this.cases = [];
            this.allCases = [];
            this.casesCount = 0;
            this.totalCasesCount = 0;
            this.assetRequests = [];
            this.allAssetRequests = [];
            this.assetRequestsCount = 0;
            this.totalAssetRequestsCount = 0;
            this.isRefreshingRelated = false;
            return;
        }

        if (preserveVisible) {
            this.isRefreshingRelated = true;
        } else {
            this.isLoadingRelated = true;
        }
        getOutlet360Summary({ recordId: outletId, objectApiName: 'Account' })
            .then((result) => {
                this.assets = (result?.assets || []).map((item, index) => ({
                    ...item,
                    rowKey: `visit-asset-${item.assetId || index}`,
                    lastAuditDateLabel: this.formatDate(item.lastAuditDate),
                    serialNumber: item.serialNumber || '--',
                    lastCondition: item.lastCondition || '--'
                }));
                this.allAssets = (result?.allAssets || []).map((item, index) => ({
                    ...item,
                    rowKey: `visit-all-asset-${item.assetId || index}`,
                    lastAuditDateLabel: this.formatDate(item.lastAuditDate),
                    serialNumber: item.serialNumber || '--',
                    lastCondition: item.lastCondition || '--'
                }));
                this.assetsCount = result?.assetsCount || this.assets.length;
                this.totalAssetsCount = result?.totalAssetsCount || this.assetsCount;

                this.recentOrders = (result?.recentOrders || []).map((item) => ({
                    ...item,
                    rowKey: `visit-order-${item.recordId}`,
                    amountLabel: this.formatCurrency(item.amount),
                    dateLabel: this.formatDate(item.recordDate)
                }));
                this.allOrders = (result?.allOrders || []).map((item) => ({
                    ...item,
                    rowKey: `visit-all-order-${item.recordId}`,
                    amountLabel: this.formatCurrency(item.amount),
                    dateLabel: this.formatDate(item.recordDate)
                }));
                this.ordersCount = result?.ordersCount || this.recentOrders.length;
                this.totalOrdersCount = result?.totalOrdersCount || this.ordersCount;

                this.orderProducts = (result?.orderProducts || []).map((item, index) => ({
                    ...item,
                    rowKey: `visit-product-${item.orderItemId || index}`,
                    unitPriceLabel: this.formatCurrency(item.unitPrice),
                    totalPriceLabel: this.formatCurrency(item.totalPrice)
                }));
                this.allOrderProducts = (result?.allOrderProducts || []).map((item, index) => ({
                    ...item,
                    rowKey: `visit-all-product-${item.orderItemId || index}`,
                    unitPriceLabel: this.formatCurrency(item.unitPrice),
                    totalPriceLabel: this.formatCurrency(item.totalPrice)
                }));
                this.orderProductsCount = result?.orderProductsCount || this.orderProducts.length;
                this.totalOrderProductsCount = result?.totalOrderProductsCount || this.orderProductsCount;

                this.cases = (result?.cases || []).map((item, index) => ({
                    ...item,
                    rowKey: `visit-case-${item.caseId || index}`,
                    totalPriceLabel: this.formatCurrency(item.totalPrice)
                }));
                this.allCases = (result?.allCases || []).map((item, index) => ({
                    ...item,
                    rowKey: `visit-all-case-${item.caseId || index}`,
                    totalPriceLabel: this.formatCurrency(item.totalPrice)
                }));
                this.casesCount = result?.casesCount || this.cases.length;
                this.totalCasesCount = result?.totalCasesCount || this.casesCount;

                this.assetRequests = (result?.assetRequests || []).map((item, index) => ({
                    ...item,
                    rowKey: `visit-asset-request-${item.requestId || index}`,
                    createdDateLabel: this.formatDate(item.createdDate),
                    requestedInstallationDateLabel: this.formatDate(item.requestedInstallationDate),
                    productName: item.productName || '--',
                    requestType: item.requestType || '--',
                    status: item.status || '--'
                }));
                this.allAssetRequests = (result?.allAssetRequests || []).map((item, index) => ({
                    ...item,
                    rowKey: `visit-all-asset-request-${item.requestId || index}`,
                    createdDateLabel: this.formatDate(item.createdDate),
                    requestedInstallationDateLabel: this.formatDate(item.requestedInstallationDate),
                    productName: item.productName || '--',
                    requestType: item.requestType || '--',
                    status: item.status || '--'
                }));
                this.assetRequestsCount = result?.assetRequestsCount || this.assetRequests.length;
                this.totalAssetRequestsCount = result?.totalAssetRequestsCount || this.assetRequestsCount;
            })
            .catch((error) => {
                this.showToast(
                    'Unable to load related outlet data',
                    error?.body?.message || 'Please try again.',
                    'error'
                );
            })
            .finally(() => {
                this.isLoadingRelated = false;
                this.isRefreshingRelated = false;
            });
    }

    // Method to check if there's a photo for this visit
    checkForVisitPhoto() {
        if (this.recordId) {
            getVisitPhoto({ visitId: this.recordId })
                .then(result => {
                    this.hasVisitPhoto = result !== null;
                    if (result) {
                        this.selectedPhotoId = result.Id;
                        // Store the photo data for later use
                        this.imageUrl = '/sfc/servlet.shepherd/version/download/' + this.selectedPhotoId;
                    }
                    
                    this.dispatchEvent(new CustomEvent('refresh'));
                })
                .catch(() => {
                    this.hasVisitPhoto = false;
                });
        }
    }

    // Fetch the latest photo attached to the outlet (Account) record
    loadOutletPhoto() {
        const accountId = this._getField('Outlet1__c');
        if (!accountId) {
            this.outletPhotoUrl = null;
            return;
        }

        getOutletPhoto({ accountId })
            .then(result => {
                this.outletPhotoUrl = result
                    ? `/sfc/servlet.shepherd/version/download/${result.Id}`
                    : null;
            })
            .catch(() => {
                this.outletPhotoUrl = null;
            });
    }

    setIsTodayFromVisit(visitRecord) {
        const visitDate = this._getFieldFromRecord(visitRecord, 'Visit_Date__c');
        if (!visitDate) {
            this.isToday = this.isToday ?? true;
            return;
        }

        const today = new Date();
        const todayVal = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
        const visitVal = new Date(visitDate).setHours(0, 0, 0, 0);
        this.isToday = todayVal === visitVal;
    }

    get outletName() {
        const account = this.outletAccount;
        return account?.Name || 'Unknown Store';
    }

    get outletRecordId() {
        return this._getField('Outlet1__c') || null;
    }

    get outletObjectApiName() {
        return this.outletAccount?.attributes?.type;
    }

    get outletLinkDisabled() {
        return !this.outletRecordId;
    }

    get visitFranchiseId() {
        return this._getField('Outlet1__c') || null;
    }

    get visitName() {
        return this.visit?.Name || 'Visit';
    }

    get outletAddress() {
        const account = this.outletAccount;
        if (!account) return null;

        // When returned from Apex @AuraEnabled, related-record fields come back
        // as flat properties (ShippingStreet, ShippingCity…), NOT as a compound
        // ShippingAddress object. Try both namespaced and unnamespaced variants.
        const street  = account.ShippingStreet     ?? account.ibfsa__ShippingStreet     ?? '';
        const city    = account.ShippingCity       ?? account.ibfsa__ShippingCity       ?? '';
        const state   = account.ShippingState      ?? account.ibfsa__ShippingState      ?? '';
        const postal  = account.ShippingPostalCode ?? account.ibfsa__ShippingPostalCode ?? '';
        const country = account.ShippingCountry    ?? account.ibfsa__ShippingCountry    ?? '';

        const parts = [street, city, state, postal, country].filter(v => v && v.trim());
        return parts.length ? parts.join(', ') : null;
    }

    get hasAddress() {
        const address = this.outletAddress;
        return !!address;
    }

    get outletPhone() {
        return this.outletAccount?.Phone || null;
    }

    get visitStatus() {
        return this._getField('Visit_Status__c') || 'Unknown';
    }

    get normalizedStatus() {
        return this._normalizeStatus(this._getField('Visit_Status__c'));
    }

    get hasOutletPhoto() {
        return !!this.outletPhotoUrl;
    }

    get statusKey() {
        const cleaned = this.normalizedStatus.replace(/[^a-z]+/g, '-').replace(/(^-|-$)/g, '');
        return cleaned || 'unknown';
    }

    get statusBadgeClass() {
        return `status-badge ${this.statusKey}`;
    }

    get checkInTime() {
        return this.formatTime(this._getField('Check_In_Time__c'));
    }

    get checkOutTime() {
        return this.formatTime(this._getField('Check_Out_Time__c'));
    }

    get duration() {
        return this._getField('Actual_Duration__c');
    }

    get plannedStart() {
        return this.formatTime(this._getField('Planned_Start_Time__c'));
    }

    get plannedEnd() {
        return this.formatTime(this._getField('Planned_End_Time__c'));
    }

    get visitDateLabel() {
        const value = this._getField('Visit_Date__c');
        if (!value) return '--';
        try {
            return new Date(value).toLocaleDateString([], { year: 'numeric', month: 'short', day: '2-digit' });
        } catch {
            return '--';
        }
    }

    get sequenceLabel() {
        const seq = this._getField('Sequence__c');
        return seq;
    }

    get hasVisitPhoto() {
        return this._hasVisitPhoto || false;
    }

    set hasVisitPhoto(value) {
        this._hasVisitPhoto = value;
    }

    get showCheckIn() {
        const status = this.normalizedStatus;
        return this.dayStarted &&
            !this.dayEnded &&
            (status === 'draft' || status === 'approved');
    }

    get showCheckOut() {
        const status = this.normalizedStatus;
        return this.dayStarted &&
            !this.dayEnded &&
            status === 'in progress';
    }

    get showDayCompletedMessage() {
        return this.dayEnded;
    }

    get showStartDayMessage() {
        return !this.dayStarted;
    }

    get hasAssetRequestSuccessMessage() {
        return !!this.assetRequestSuccessMessage;
    }

    get showRatingFeedback() {
        const status = this.normalizedStatus;
        return this.dayStarted && (status === 'in progress' || status === 'completed');
    }

    get hasRelatedAssets() { return this.assets.length > 0; }
    get hasAllRelatedAssets() { return this.allAssets.length > 0; }
    get hasRelatedOrders() { return this.recentOrders.length > 0; }
    get hasAllRelatedOrders() { return this.allOrders.length > 0; }
    get hasRelatedProducts() { return this.orderProducts.length > 0; }
    get hasAllRelatedProducts() { return this.allOrderProducts.length > 0; }
    get hasRelatedCases() { return this.cases.length > 0; }
    get hasAllRelatedCases() { return this.allCases.length > 0; }
    get hasRelatedAssetRequests() { return this.assetRequests.length > 0; }
    get hasAllRelatedAssetRequests() { return this.allAssetRequests.length > 0; }
    get showRelatedLists() { return !!this.outletRecordId; }

    get relatedAssetsLabel() { return `Assets (${this.totalAssetsCount || this.assetsCount || 0})`; }
    get relatedOrdersLabel() { return `Orders (${this.totalOrdersCount || this.ordersCount || 0})`; }
    get relatedCasesLabel() { return `Cases (${this.totalCasesCount || this.casesCount || 0})`; }
    get relatedAssetRequestsLabel() { return `Asset Requests (${this.totalAssetRequestsCount || this.assetRequestsCount || 0})`; }
    get isRelatedRefreshDisabled() { return this.isLoadingRelated || this.isRefreshingRelated; }
    get relatedRefreshButtonClass() {
        return this.isRefreshingRelated
            ? 'related-refresh-btn related-refresh-btn--spinning'
            : 'related-refresh-btn';
    }

    get showViewAllRelatedAssets() { return (this.totalAssetsCount || 0) > 5; }
    get showViewAllRelatedOrders() { return (this.totalOrdersCount || 0) > 5; }
    get showViewAllRelatedProducts() { return (this.totalOrderProductsCount || 0) > 5; }
    get showViewAllRelatedCases() { return (this.totalCasesCount || 0) > 5; }
    get showViewAllRelatedAssetRequests() { return (this.totalAssetRequestsCount || 0) > 5; }

    get isRelatedTabAssets() { return this.activeRelatedTab === 'assets'; }
    get isRelatedTabOrders() { return this.activeRelatedTab === 'orders'; }
    get isRelatedTabProducts() { return this.activeRelatedTab === 'products'; }
    get isRelatedTabCases() { return this.activeRelatedTab === 'cases'; }
    get isRelatedTabAssetRequests() { return this.activeRelatedTab === 'assetRequests'; }
    get relatedTabClassAssets() { return `tab-pill${this.activeRelatedTab === 'assets' ? ' active' : ''}`; }
    get relatedTabClassOrders() { return `tab-pill${this.activeRelatedTab === 'orders' ? ' active' : ''}`; }
    get relatedTabClassProducts() { return `tab-pill${this.activeRelatedTab === 'products' ? ' active' : ''}`; }
    get relatedTabClassCases() { return `tab-pill${this.activeRelatedTab === 'cases' ? ' active' : ''}`; }
    get relatedTabClassAssetRequests() { return `tab-pill${this.activeRelatedTab === 'assetRequests' ? ' active' : ''}`; }

    get mapDisabled() {
        return false; // Always enabled — falls back to default coordinates if outlet has none
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', { bubbles: true, composed: true }));

        try {
            if (window.history.length > 1) {
                const currentUrl = window.location.href;
                window.history.back();
                window.setTimeout(() => {
                    if (window.location.href === currentUrl) {
                        this.navigateToHomeFallback();
                    }
                }, 300);
                return;
            }
        } catch (error) {
            this.navigateToHomeFallback();
            return;
        }
        this.navigateToHomeFallback();
    }

    navigateToHomeFallback() {
        try {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: {
                    apiName: 'Sales_Rep',
                    
                }
            });
            return;
        } catch (error) {
            // continue with fallback
        }

        try {
            this[NavigationMixin.Navigate]({
                type: 'standard__navItemPage',
                attributes: {
                    apiName: 'ibfsa__Sales_Rep'
                }
            });
            return;
        } catch (error) {
            // continue with fallback
        }

        try {
            this[NavigationMixin.Navigate]({
                type: 'standard__webPage',
                attributes: {
                    url: '/one/one.app'
                }
            });
        } catch (error) {
            // no-op
        }
    }

    navigateToMap(event) {
        event?.stopPropagation();
        const { lat, lon } = this.outletCoordinates;
        const mapUrl = `https://www.google.com/maps/search/?api=1&query=${lat},${lon}`;
        window.open(mapUrl, '_blank');
    }

    handleOpenOutlet360(event) {
        event?.preventDefault();
        event?.stopPropagation();

        if (!this.outletRecordId) {
            this.showToast('Store unavailable', 'Store record is not available for this visit.', 'warning');
            return;
        }

        const state = {
            c__recordId: String(this.outletRecordId),
            c__objectApiName: this.outletObjectApiName ? String(this.outletObjectApiName) : 'Account'
        };
        if (this.currentVisitId) {
            state.c__visitId = String(this.currentVisitId);
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: {
                componentName: 'c__outlet360Page'
            },
            state
        });
    }

    handleCheckIn(event) {
        event?.stopPropagation();
        this.performGeoAction(checkInVisit);
    }

    handleCheckOut(event) {
        event?.stopPropagation();

        if (this.hasPendingMandatoryTasks) {
            this.showToast(
                'Mandatory task pending',
                'Please complete all mandatory tasks before checking out.',
                'warning'
            );
            return;
        }
        
        // Check if meeting notes are provided
        if (!this.savedNotesList || this.savedNotesList.length === 0) {
            this.showToast(
                'Notes required',
                'Please add meeting notes before checking out.',
                'warning'
            );
            return;
        }
        
        if (!this.ratingFeedbackSaved) {
            this.showToast(
                'Feedback required',
                'Please save your rating and feedback before checking out.',
                'warning'
            );
            return;
        }
        this.performGeoAction(checkOutVisit);
    }

    handleToggleOrderPanel() {
        const dlg = this.template.querySelector('dialog.order-dialog');
        if (!dlg) return;
        if (dlg.open) {
            dlg.close();
            this._unlockScroll();
            // If an order was placed and user closes via ✕, show toast now
            if (this._orderWasCreated) {
                this._orderWasCreated = false;
               // this.showToast('Order Created', 'Order created successfully.', 'success');
            }
        } else {
            // Reset placeOrder to step 1 before opening so a fresh form
            // is always shown, even after a previously completed order.
            const placeOrder = this.template.querySelector('c-place-order');
            if (placeOrder) placeOrder.reset();
            dlg.showModal();
            this._lockScroll();
        }
    }

    // Esc key fires native 'close' event — just sync scroll lock, don't re-toggle
    handleOrderDialogClose() {
        this._unlockScroll();
        // If an order was placed, show the toast now — after the dialog has
        // closed and the success screen is gone, so it appears on visitDetail.
        if (this._orderWasCreated) {
            this._orderWasCreated = false;
            this.showToast('Order Created', 'Order created successfully.', 'success');
        }
    }

    handleOpenSchemesModal() {
        const dlg = this.template.querySelector('dialog.schemes-dialog');
        if (dlg && !dlg.open) {
            dlg.showModal();
            this._lockScroll();
        }
    }

    handleCloseSchemesModal() {
        const dlg = this.template.querySelector('dialog.schemes-dialog');
        if (dlg && dlg.open) {
            dlg.close();
            this._unlockScroll();
        }
    }

    // Esc key sync handler for schemes dialog
    handleSchemesDialogClose() {
        this._unlockScroll();
    }

    handleOpenOrdersModal() {
        const dlg = this.template.querySelector('dialog.orders-dialog');
        if (dlg && !dlg.open) {
            dlg.showModal();
            this._lockScroll();
        }
    }

    handleCloseOrdersModal() {
        const dlg = this.template.querySelector('dialog.orders-dialog');
        if (dlg && dlg.open) {
            dlg.close();
            this._unlockScroll();
        }
    }

    // Esc key sync — don't re-invoke close logic
    handleOrdersDialogClose() {
        this._unlockScroll();
    }

    handleOrderSelected(event) {
        const order = event.detail?.order || null;
        // Open orderDetail popup when a card is tapped
        if (order?.orderId) {
            const orderDetail = this.template.querySelector('c-order-detail');
            if (orderDetail) orderDetail.openForOrder(order.orderId);
        }
    }

    handleOrderDetailClose() {
        // no-op — orderDetail manages its own close
    }

    get orderToggleLabel() {
        return 'Create Order';
    }

    handleVisitFileUploadFinished(event) {
        const files = event.detail?.files || [];
        const newFiles = files.map(f => ({ name: f.name, documentId: f.documentId }));
        this.recentUploadFiles = [...this.recentUploadFiles, ...newFiles];
        const count = files.length;
        this.showToast('Upload complete', `${count} file(s) attached to this visit.`, 'success');
        this._renameNoteAttachments(newFiles);
    }

    _renameNoteAttachments(files) {
        if (!files || files.length === 0) return;
        const outlet = (this.outletName || 'Outlet').replace(/[^a-zA-Z0-9]/g, '_');
        const visit  = (this.visitName  || 'Visit').replace(/[^a-zA-Z0-9]/g, '_');
        const now    = new Date();
        const date   = now.toISOString().slice(0, 10).replace(/-/g, '');
        const time   = now.toISOString().slice(11, 19).replace(/:/g, '');
        
        files.forEach((file, idx) => {
            // Extract file extension and original name
            const lastDotIndex = file.name.lastIndexOf('.');
            const ext = lastDotIndex !== -1 ? file.name.substring(lastDotIndex + 1).toLowerCase() : '';
            const originalName = lastDotIndex !== -1 ? file.name.substring(0, lastDotIndex) : file.name;
            const cleanOriginalName = originalName.replace(/[^a-zA-Z0-9]/g, '_').substring(0, 30);
            
            // Create meaningful filename with sequence
            const sequence = (idx + 1).toString().padStart(2, '0');
            const newTitle = `${outlet}_${visit}_${date}_${time}_${sequence}_${cleanOriginalName}${ext ? '.' + ext : ''}`;
            
            renameAttachment({ contentDocumentId: file.documentId, newTitle })
                .then(() => {
                    // Update the UI with the new meaningful name
                    this.recentUploadFiles = this.recentUploadFiles.map(f =>
                        f.documentId === file.documentId
                            ? { ...f, name: newTitle }
                            : f
                    );
                })
                .catch(() => {});
        });
    }

    handleRemoveAttachment(event) {
        const documentId = event.currentTarget.dataset.id;
        const file = this.recentUploadFiles.find(f => f.documentId === documentId);
        if (!file) return;

        deleteAttachment({ contentDocumentId: documentId })
            .then(() => {
                this.recentUploadFiles = this.recentUploadFiles.filter(f => f.documentId !== documentId);
                this.showToast('Removed', `"${file.name}" has been deleted.`, 'success');
            })
            .catch(err => {
                this.showToast('Delete failed', err?.body?.message || 'Unable to remove attachment.', 'error');
            });
    }

    // ─── Meeting Notes tile helpers ───────────────────────────────────────────

    /**
     * Parse the Meeting_Notes__c field (JSON array stored as string) into
     * the savedNotesList array. Falls back gracefully for plain-text legacy data.
     */
    _parseMeetingNotesIntoTiles(raw) {
        if (!raw || !raw.trim()) {
            this.savedNotesList = [];
            return;
        }
        try {
            const parsed = JSON.parse(raw);
            if (Array.isArray(parsed)) {
                this.savedNotesList = parsed;
                return;
            }
        } catch (e) {
            // Legacy plain-text: treat whole value as a single tile
        }
        // Legacy fallback: single tile with the raw text
        this.savedNotesList = [{
            id: 'legacy-1',
            text: raw,
            dateLabel: ''
        }];
    }

    /** Serialize savedNotesList back to JSON for storage in Meeting_Notes__c */
    _serializeNotesToField() {
        return JSON.stringify(this.savedNotesList);
    }

    _nowDateLabel() {
        return new Date().toLocaleString('en-IN', {
            day: '2-digit', month: 'short', year: 'numeric',
            hour: '2-digit', minute: '2-digit'
        });
    }

    // ─── Note UI handlers ─────────────────────────────────────────────────────

    handleAddNote() {
        this.meetingNotes = '';
        this.editingNoteId = null;
        this.recentUploadFiles = [];  // Clear previous attachments
        this.showNotesInput = true;
    }

    handleEditNote(event) {
        const noteId = event.currentTarget.dataset.id;
        const note = this.savedNotesList.find(n => n.id === noteId);
        if (!note) return;
        this.meetingNotes = note.text;
        this.editingNoteId = noteId;
        // Restore attachments associated with this note
        this.recentUploadFiles = note.attachments || [];
        this.showNotesInput = true;
    }

    handleDeleteNote(event) {
        const noteId = event.currentTarget.dataset.id;
        const noteToDelete = this.savedNotesList.find(n => n.id === noteId);

        if (noteToDelete && noteToDelete.attachments && noteToDelete.attachments.length > 0) {
            // Delete all attachments associated with this note
            const deletePromises = noteToDelete.attachments.map(attachment =>
                deleteAttachment({ contentDocumentId: attachment.documentId })
            );

            Promise.all(deletePromises)
                .then(() => {
                    // After attachments are deleted, remove the note
                    this.savedNotesList = this.savedNotesList.filter(n => n.id !== noteId);
                    this.lastNoteAction = 'delete';
                    this._persistNotes();
                })
                .catch(err => {
                    this.showToast('Delete failed', err?.body?.message || 'Unable to delete note attachments.', 'error');
                });
        } else {
            // No attachments, just remove the note
            this.savedNotesList = this.savedNotesList.filter(n => n.id !== noteId);
            this.lastNoteAction = 'delete';
            this._persistNotes();
        }
    }

    handleCancelNote() {
        this.showNotesInput = false;
        this.editingNoteId = null;
        this.meetingNotes = '';
        this.recentUploadFiles = [];  // Clear attachments when canceling
    }

    handleMeetingNotesChange(event) {
        this.meetingNotes = event?.target?.value || '';
    }

    handleSaveMeetingNotes() {
        const visitId = this.currentVisitId;
        if (!visitId) {
            this.showToast('Visit not found', 'Missing visit id.', 'error');
            return;
        }
        const text = this.meetingNotes.trim();
        if (!text) {
            this.showToast('Empty note', 'Please enter some text before saving.', 'warning');
            return;
        }

        if (this.editingNoteId) {
            // Update existing tile
            this.savedNotesList = this.savedNotesList.map(n =>
                n.id === this.editingNoteId
                    ? { ...n, text, dateLabel: this._nowDateLabel(), attachments: this.recentUploadFiles }
                    : n
            );
            this.lastNoteAction = 'edit';
        } else {
            // Add new tile
            const newNote = {
                id: `note-${Date.now()}`,
                text,
                dateLabel: this._nowDateLabel(),
                attachments: this.recentUploadFiles
            };
            this.savedNotesList = [...this.savedNotesList, newNote];
            this.lastNoteAction = 'add';
        }

        this.showNotesInput = false;
        this.editingNoteId = null;
        this.meetingNotes = '';
        this.recentUploadFiles = [];  // Clear attachments after saving note
        this._persistNotes();
    }

    /** Save the current savedNotesList to Meeting_Notes__c via Apex */
    _persistNotes() {
        const visitId = this.currentVisitId;
        if (!visitId) return;

        this.meetingNotesSaving = true;
        const notes = this._serializeNotesToField();

        saveMeetingNotes({ visitId, notes })
            .then(() => {
                let toastTitle = 'Saved';
                let toastMessage = 'Meeting notes saved successfully.';

                if (this.lastNoteAction === 'delete') {
                    toastTitle = 'Deleted';
                    toastMessage = this.savedNotesList.length === 0 
                        ? 'Note and all attachments deleted successfully.' 
                        : 'Note and all attachments deleted successfully.';
                } else if (this.lastNoteAction === 'add') {
                    toastTitle = 'Added';
                    toastMessage = 'Note added successfully.';
                } else if (this.lastNoteAction === 'edit') {
                    toastTitle = 'Updated';
                    toastMessage = 'Note updated successfully.';
                }

                this.showToast(toastTitle, toastMessage, 'success');
                this.lastNoteAction = null;  // Reset action
            })
            .catch((error) => {
                this.showToast(
                    'Save failed',
                    error?.body?.message || 'Unable to save meeting notes.',
                    'error'
                );
                this.lastNoteAction = null;  // Reset action on error
            })
            .finally(() => {
                this.meetingNotesSaving = false;
            });
    }

    // ─── Getters for template ─────────────────────────────────────────────────

    get hasSavedNotes() {
        return this.savedNotesList && this.savedNotesList.length > 0;
    }

    get hasRecentUploads() {
        return this.recentUploadFiles && this.recentUploadFiles.length > 0;
    }

    get notesInputLabel() {
        return this.editingNoteId ? 'Edit Note' : 'New Note';
    }

    performGeoAction(apexMethod) {
        if (!navigator?.geolocation) {
            this.showToast('Location unavailable', 'Geolocation is not supported.', 'error');
            return;
        }

        const visitId = this.currentVisitId;
        if (!visitId) {
            this.showToast('Visit not found', 'Missing visit id.', 'error');
            return;
        }

        this.actionInFlight = true;

        navigator.geolocation.getCurrentPosition(
            pos => {
                apexMethod({
                    visitId,
                    lat: pos.coords.latitude.toString(),
                    lon: pos.coords.longitude.toString()
                })
                .then(() => {
                    // Optimistic local update so action buttons switch immediately.
                    if (apexMethod === checkInVisit) {
                        this._setVisitStatus('In Progress');
                    } else if (apexMethod === checkOutVisit) {
                        this._setVisitStatus('Completed');
                    }
                })
                .then(() => this.refreshVisitData({ showErrorToast: false }))
                .then(() => {
                    this.showToast('Success', 'Visit updated successfully.', 'success');
                })
                .catch(err => {
                    this.showToast('Action failed', err?.body?.message || 'Please try again.', 'error');
                })
                .finally(() => {
                    this.actionInFlight = false;
                });
            },
            () => {
                this.actionInFlight = false;
                this.showToast('Location required', 'Please enable location permission.', 'error');
            },
            { enableHighAccuracy: true }
        );
    }

    formatTime(value) {
        if (!value) return '--';
        try {
            const date = new Date(value);
            return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
        } catch {
            return '--';
        }
    }

    formatDate(value) {
        if (!value) return '--';
        try {
            return new Date(value).toLocaleDateString('en-IN', {
                day: '2-digit',
                month: 'short',
                year: 'numeric'
            });
        } catch {
            return '--';
        }
    }

    formatCurrency(value) {
        const numeric = Number(value || 0);
        return new Intl.NumberFormat('en-IN', {
            style: 'currency',
            currency: 'INR',
            maximumFractionDigits: 2
        }).format(numeric);
    }

    get starList() {
        return [1, 2, 3, 4, 5].map(n => ({
            value: n,
            label: `${n} star${n > 1 ? 's' : ''}`,
            cssClass: n <= this.selectedRating ? 'star-btn star-filled' : 'star-btn star-empty'
        }));
    }

    get feedbackNotSaved() {
        return !this.ratingFeedbackSaved;
    }

    handleStarClick(event) {
        const val = parseInt(event.currentTarget.dataset.value, 10);
        this.selectedRating = val;
        this.ratingFeedbackSaved = false;
    }

    handleFeedbackChange(event) {
        this.visitFeedback = event?.target?.value || '';
        this.ratingFeedbackSaved = false;
    }

    handleSaveRatingFeedback() {
        const visitId = this.currentVisitId;
        if (!visitId) {
            this.showToast('Visit not found', 'Missing visit id.', 'error');
            return;
        }
        if (!this.selectedRating) {
            this.showToast('Rating required', 'Please select a star rating.', 'warning');
            return;
        }
        if (!this.visitFeedback?.trim()) {
            this.showToast('Feedback required', 'Please enter feedback before saving.', 'warning');
            return;
        }

        this.ratingFeedbackSaving = true;
        saveRatingAndFeedback({
            visitId,
            rating: this.selectedRating,
            feedback: this.visitFeedback
        })
            .then(() => {
                this.ratingFeedbackSaved = true;
                this.showToast('Saved', 'Rating and feedback saved successfully.', 'success');
            })
            .catch(err => {
                this.showToast('Save failed', err?.body?.message || 'Unable to save rating and feedback.', 'error');
            })
            .finally(() => {
                this.ratingFeedbackSaving = false;
            });
    }

    // ─── Tasks ────────────────────────────────────────────────────────────────

    loadVisitTasks() {
        const visitId = this.currentVisitId;
        if (!visitId) return;
        this.isLoadingTasks = true;
        getVisitTasks({ visitId })
            .then(data => {
                this.tasks = data || [];
                this.isLoadingTasks = false;
            })
            .catch(err => {
                this.isLoadingTasks = false;
                this.showToast(
                    'Could not load tasks',
                    err?.body?.message || 'Please refresh and try again.',
                    'error'
                );
            });
    }

    get decoratedTasks() {
        return this.tasks.map(t => ({
            ...t,
            assetName        : t.Related_Asset__r ? t.Related_Asset__r.Name : '—',
            hasInstructions  : !!t.Manager_Instructions__c,
            isPending        : t.Status__c === 'Pending',
            isCompleted      : t.Status__c === 'Completed',
            isBlocked        : t.Status__c === 'Blocked/Retailer Refused',
            isExpanded       : this.expandedTaskId === t.Id,
            chevron          : this.expandedTaskId === t.Id ? '▲' : '▼',
            statusBadgeClass : this._taskStatusClass(t.Status__c),
            itemClass        : t.Is_Mandatory__c ? 'task-item task-item--mandatory' : 'task-item',
        }));
    }

    _taskStatusClass(status) {
        const map = {
            'Pending'                 : 'task-status task-status--pending',
            'Completed'               : 'task-status task-status--completed',
            'Blocked/Retailer Refused': 'task-status task-status--blocked',
        };
        return map[status] || 'task-status';
    }

    get hasTasks()       { return this.tasks.length > 0; }
    get hasPendingMandatoryTasks() {
        return this.tasks.some(t =>
            t.Is_Mandatory__c === true && t.Status__c === 'Pending'
        );
    }
    get showTasksCard()  { return !!this.currentVisitId; }
    get taskCountLabel() {
        const pending = this.tasks.filter(t => t.Status__c === 'Pending').length;
        const total   = this.tasks.length;
        return pending > 0 ? `${pending} of ${total} pending` : `${total} done`;
    }

    handleTaskToggle(event) {
        const taskId = event.currentTarget.dataset.id;
        this.expandedTaskId = this.expandedTaskId === taskId ? null : taskId;
    }

    handleCompleteTask(event) {
        const taskId = event.currentTarget.dataset.id;
        this.isActingOnTask = true;
        updateTaskStatus({ taskId, status: 'Completed', exceptionReason: '' })
            .then(() => {
                this.isActingOnTask = false;
                this.expandedTaskId = null;
                this.showToast('Task completed', 'Task marked as complete.', 'success');
                this.loadVisitTasks();
            })
            .catch(err => {
                this.isActingOnTask = false;
                this.showToast('Error', err?.body?.message || 'Could not complete task.', 'error');
            });
    }

    handleOpenBlockDialog(event) {
        const taskId = event.currentTarget.dataset.id;
        this.blockingTask = this.tasks.find(t => t.Id === taskId) || null;
        this.blockReason  = '';
        const dlg = this.template.querySelector('dialog.block-task-dialog');
        if (dlg && !dlg.open) {
            dlg.showModal();
            this._lockScroll();
        }
    }

    handleCloseBlockDialog() {
        const dlg = this.template.querySelector('dialog.block-task-dialog');
        if (dlg && dlg.open) {
            dlg.close();
            this._unlockScroll();
        }
        this.blockingTask = null;
        this.blockReason  = '';
    }

    handleBlockDialogClose() {
        this._unlockScroll();
    }

    handleBlockReasonChange(event) {
        this.blockReason = event?.target?.value || '';
    }

    handleConfirmBlock() {
        if (!this.blockingTask) return;
        if (!this.blockReason?.trim()) {
            this.showToast('Reason required', 'Please enter a reason for blocking this task.', 'warning');
            return;
        }
        const taskId = this.blockingTask.Id;
        this.isActingOnTask = true;
        updateTaskStatus({
            taskId,
            status          : 'Blocked/Retailer Refused',
            exceptionReason : this.blockReason.trim(),
        })
            .then(() => {
                this.isActingOnTask = false;
                this.handleCloseBlockDialog();
                this.expandedTaskId = null;
                this.showToast('Task blocked', 'Task marked as blocked.', 'info');
                this.loadVisitTasks();
            })
            .catch(err => {
                this.isActingOnTask = false;
                this.showToast('Error', err?.body?.message || 'Could not block task.', 'error');
            });
    }

    // ─────────────────────────────────────────────────────────────────────────

    handleRelatedTabClick(event) {
        this.activeRelatedTab = event.currentTarget.dataset.tab;
    }

    handleRefreshRelatedData() {
        this.loadOutletRelatedData({ preserveVisible: true });
    }

    handleOpenRelatedAssetsModal() {
        const dlg = this.template.querySelector('dialog.related-assets-dialog');
        if (dlg && !dlg.open) {
            dlg.showModal();
            this._lockScroll();
        }
    }

    handleCloseRelatedAssetsModal() {
        const dlg = this.template.querySelector('dialog.related-assets-dialog');
        if (dlg && dlg.open) {
            dlg.close();
            this._unlockScroll();
        }
    }

    handleOpenRelatedOrdersModal() {
        const dlg = this.template.querySelector('dialog.related-orders-dialog');
        if (dlg && !dlg.open) {
            dlg.showModal();
            this._lockScroll();
        }
    }

    handleCloseRelatedOrdersModal() {
        const dlg = this.template.querySelector('dialog.related-orders-dialog');
        if (dlg && dlg.open) {
            dlg.close();
            this._unlockScroll();
        }
    }

    handleOpenRelatedProductsModal() {
        const dlg = this.template.querySelector('dialog.related-products-dialog');
        if (dlg && !dlg.open) {
            dlg.showModal();
            this._lockScroll();
        }
    }

    handleCloseRelatedProductsModal() {
        const dlg = this.template.querySelector('dialog.related-products-dialog');
        if (dlg && dlg.open) {
            dlg.close();
            this._unlockScroll();
        }
    }

    handleOpenRelatedCasesModal() {
        const dlg = this.template.querySelector('dialog.related-cases-dialog');
        if (dlg && !dlg.open) {
            dlg.showModal();
            this._lockScroll();
        }
    }

    handleOpenRelatedAssetRequestsModal() {
        const dlg = this.template.querySelector('dialog.related-asset-requests-dialog');
        if (dlg && !dlg.open) {
            dlg.showModal();
            this._lockScroll();
        }
    }

    handleCloseRelatedCasesModal() {
        const dlg = this.template.querySelector('dialog.related-cases-dialog');
        if (dlg && dlg.open) {
            dlg.close();
            this._unlockScroll();
        }
    }

    handleCloseRelatedAssetRequestsModal() {
        const dlg = this.template.querySelector('dialog.related-asset-requests-dialog');
        if (dlg && dlg.open) {
            dlg.close();
            this._unlockScroll();
        }
    }

    handleRelatedDialogClose() {
        this._unlockScroll();
    }

    handleRelatedOrderClick(event) {
        const orderId = event.currentTarget.dataset.id;
        if (!orderId) return;
        this.handleCloseRelatedOrdersModal();
        const orderDetail = this.template.querySelector('c-order-detail');
        if (orderDetail) {
            orderDetail.openForOrder(orderId);
        }
    }

    handleRelatedCaseClick(event) {
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

    handleRelatedAssetClick(event) {
        const assetId = event.currentTarget.dataset.id;
        if (!assetId) return;
        this.handleCloseRelatedAssetsModal();
        const assetDetail = this.template.querySelector('c-asset-detail');
        if (assetDetail) {
            assetDetail.openForAsset(assetId);
        }
    }

    handleAssetAuditCreated() {
        this.loadOutletRelatedData();
    }

    handleRelatedAssetRequestClick(event) {
        const requestId = event.currentTarget.dataset.id;
        if (!requestId) return;
        this.handleCloseRelatedAssetRequestsModal();
        const requestDetail = this.template.querySelector('c-asset-request-detail');
        if (requestDetail) {
            requestDetail.openForRequest(requestId);
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    _setVisitStatus(nextStatus) {
        this.visit = {
            ...(this.visit || {}),
            Visit_Status__c: nextStatus,
            ibfsa__Visit_Status__c: nextStatus
        };
    }

    _getField(apiName) {
        return this._getFieldFromRecord(this.visit, apiName);
    }

    _getFieldFromRecord(record, apiName) {
        if (!record) return undefined;
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
// ─── Scroll-lock helpers ──────────────────────────────────────────────────
    // On mobile the Salesforce webview scrolls a container *inside* the LWC host,
    // not <body>. We freeze whichever element is actually scrolling so the fixed
    // modal overlay truly covers the full viewport without the page behind it
    // jumping around.
    _scrollLockTarget = null;
    _scrollLockY = 0;

    _lockScroll() {
        // Walk up from the host to find the nearest scrolling ancestor
        let el = this.template.host || document.body;
        while (el && el !== document.documentElement) {
            const style = window.getComputedStyle(el);
            const overflow = style.overflowY || style.overflow;
            if ((overflow === 'auto' || overflow === 'scroll') && el.scrollHeight > el.clientHeight) {
                break;
            }
            el = el.parentElement;
        }
        // Fall back to body if nothing found
        if (!el || el === document.documentElement) el = document.body;

        this._scrollLockTarget = el;
        this._scrollLockY = el.scrollTop;
        el.style.overflow = 'hidden';
        // Also lock body as a safety net for browsers that scroll <body>
        if (el !== document.body) {
            document.body.style.overflow = 'hidden';
        }
    }

    _unlockScroll() {
        if (this._scrollLockTarget) {
            this._scrollLockTarget.style.overflow = '';
            this._scrollLockTarget.scrollTop = this._scrollLockY;
            this._scrollLockTarget = null;
        }
        document.body.style.overflow = '';
    }
    // ─────────────────────────────────────────────────────────────────────────

    // Modal handlers
    handleOpenPhotoModal = () => {
        if (this.hasVisitPhoto && this.imageUrl) {
            const dlg = this.template.querySelector('dialog.photo-dialog');
            if (dlg && !dlg.open) {
                dlg.showModal();
                this._lockScroll();
            }
        } else {
            this.showToast('No photo', 'No visit photo available to view.', 'info');
        }
    };

    handleClosePhotoModal = () => {
        const dlg = this.template.querySelector('dialog.photo-dialog');
        if (dlg && dlg.open) {
            dlg.close();
            this._unlockScroll();
        }
    };

    // Delete the visit photo
    handleDeletePhoto = () => {
        // Use the selectedPhotoId that was already retrieved
        if (this.selectedPhotoId) {
            this.isLoading = true;
            deleteVisitPhoto({ contentVersionId: this.selectedPhotoId })
                .then(() => {
                    this.showToast('Success', 'Photo deleted successfully.', 'success');
                    this.hasVisitPhoto = false;
                    this.imageUrl = undefined;
                    this.handleClosePhotoModal();
                    this.isLoading = false;
                    // Refresh the page to show updated state
                    this.dispatchEvent(new CustomEvent('refresh'));
                })
                .catch(() => {
                    this.showToast('Error', 'Failed to delete photo.', 'error');
                    this.isLoading = false;
                });
        } else {
            this.showToast('Error', 'No photo found to delete.', 'error');
        }
    };

    // Prompt for image capture and upload to Salesforce as ContentVersion linked to Visit__c
    handleTakePhoto = () => {
        try {
            // Create a hidden file input on the fly to trigger camera on mobile
            const input = document.createElement('input');
            input.type = 'file';
            input.accept = 'image/*';
            // capture attribute hints using back-facing camera on supported devices
            input.setAttribute('capture', 'environment');

            input.onchange = async () => {
                const file = input.files && input.files[0];
                if (!file) return;
 
                const visitId = this.currentVisitId;
                if (!visitId) {
                    this.showToast('Visit not found', 'Missing visit id.', 'error');
                    return;
                }

                try {
                    // Resize image if needed to be under 3MB
                    const resizedFile = await this.resizeImageIfNeeded(file);
                    
                    // Read file as base64 (strip data URL prefix afterwards)
                    const base64 = await this.readFileAsBase64(resizedFile);
                    const base64Data = base64.substring(base64.indexOf(',') + 1);

                    this.isLoading = true;

                const result = await uploadVisitPhoto({
                    visitId,
                    base64Data,
                    contentType: resizedFile.type || file.type || 'image/jpeg'
                });

                if (result) {
                    this.selectedPhotoId = result;
                    this.hasVisitPhoto = true;
                    // Update the image URL to reflect the newly uploaded photo
                    const timestamp = new Date().getTime();
                    this.imageUrl = `/sfc/servlet.shepherd/version/download/${this.selectedPhotoId}?v=${timestamp}`;
                    // Ensure modal is closed after upload
                    const photoDlg = this.template.querySelector('dialog.photo-dialog');
                    if (photoDlg && photoDlg.open) { photoDlg.close(); this._unlockScroll(); }
                }

                this.showToast('Photo uploaded', 'Image attached to visit.', 'success');
                this.isLoading = false;
                // Let parent refresh data if needed
                this.dispatchEvent(new CustomEvent('refresh'));
                //this.checkForVisitPhoto();
                } catch (err) {
                    const msg = err?.body?.message || err?.message || 'Upload failed. Please try again.';
                    const fileSize = file.size / 1024 / 1024;
                    // this.showToast('Upload error', msg, 'error');
                    this.dispatchEvent(new ShowToastEvent({ title: 'Upload error (File size: ' + fileSize.toFixed(2) + 'MB)',
                                                    message: msg,
                                                    variant: 'error',
                                                    mode: 'sticky' }));
                    this.isLoading = false;
                }
            };

            // Trigger the chooser/camera
            input.click();
        } catch {
            this.showToast('Camera error', 'Unable to start camera prompt.', 'error');
        }
    };

    // Resize image to be less than 3MB if needed
    resizeImageIfNeeded = (file) => {
        return new Promise((resolve, reject) => {
            if (file.size <= 3 * 1024 * 1024) {
                resolve(file);
                return;
            }

            const canvas = document.createElement('canvas');
            const ctx = canvas.getContext('2d');
            const img = new Image();
            const objectUrl = URL.createObjectURL(file);

            img.onerror = () => {
                URL.revokeObjectURL(objectUrl);
                reject(new Error('Failed to load image for resizing'));
            };

            img.onload = () => {
                URL.revokeObjectURL(objectUrl);
                let width = img.width;
                let height = img.height;
                let quality = 0.9;

                const resize = () => {
                    canvas.width = width;
                    canvas.height = height;
                    ctx.drawImage(img, 0, 0, width, height);

                    canvas.toBlob((blob) => {
                        if (!blob) {
                            reject(new Error('Failed to resize image'));
                            return;
                        }

                        if (blob.size <= 3 * 1024 * 1024) {
                            const resizedFile = new File([blob], file.name, { type: file.type });
                            resolve(resizedFile);
                            return;
                        }

                        quality -= 0.05;
                        if (quality <= 0.1) {
                            resolve(file);
                            return;
                        }

                        width = Math.floor(width * 0.9);
                        height = Math.floor(height * 0.9);
                        resize();
                    }, file.type, quality);
                };

                resize();
            };

            img.src = objectUrl;
        });
    };

    // Utility: read a File as data URL (base64)
    readFileAsBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(new Error('Failed to read file'));
            reader.readAsDataURL(file);
        });
    }

}