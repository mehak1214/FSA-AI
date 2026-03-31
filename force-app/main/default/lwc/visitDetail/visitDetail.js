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
import saveRatingAndFeedback from '@salesforce/apex/VisitController.saveRatingAndFeedback';
import getVisitTasks from '@salesforce/apex/VisitTaskController.getVisitTasks';
import updateTaskStatus from '@salesforce/apex/VisitTaskController.updateTaskStatus';

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
    // UI state for photo modal
    isPhotoModalOpen = false;
    isSchemesModalOpen = false;
    isOrdersModalOpen = false;
    recentUploadNames = [];
    meetingNotes = '';
    meetingNotesSaving = false;
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

    @api
    get visit() {
        return this._visit;
    }
    set visit(value) {
        this._visit = value;
        this.recordId = value?.Id || this.recordId;
    }

    @api
    get visitId() {
        return this._visitId;
    }
    set visitId(value) {
        this._visitId = value;
        this.recordId = value || this.recordId;
    }
    @api dayStarted;
    @api dayEnded;
    @api isToday;
    pageVisitId;

    connectedCallback() {
        setTimeout(() => {
        this.loadAttendance();
        }, 300)
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
        const orderId = event.detail?.orderId;

        this.showToast(
            'Order Created',
            'Order created successfully.',
            'success'
        );

        // Close modal
        const orderDlg = this.template.querySelector('dialog.order-dialog');
        if (orderDlg && orderDlg.open) { orderDlg.close(); this._unlockScroll(); }

        // Optional: refresh parent visit
        this.refreshVisitData({ showErrorToast: false });
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
                this.selectedRating = Number(this._getFieldFromRecord(visitData, 'Rating__c')) || 0;
                this.visitFeedback = this._getFieldFromRecord(visitData, 'Feedback__c') || '';
                this.ratingFeedbackSaved = !!(this.selectedRating && this.visitFeedback);
                this.setIsTodayFromVisit(visitData);
                this.checkForVisitPhoto();
                this.loadOutletPhoto();
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
            this.selectedRating = Number(this._getFieldFromRecord(data, 'Rating__c')) || 0;
            this.visitFeedback = this._getFieldFromRecord(data, 'Feedback__c') || '';
            this.ratingFeedbackSaved = !!(this.selectedRating && this.visitFeedback);
            this.setIsTodayFromVisit(data);
            // Check if there's a photo for this visit
            this.checkForVisitPhoto();
            // Load account/outlet photo
            this.loadOutletPhoto();
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
        return account?.Name || 'Unknown Outlet';
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

    get showRatingFeedback() {
        const status = this.normalizedStatus;
        return this.dayStarted && (status === 'in progress' || status === 'completed');
    }

    get mapDisabled() {
        return false; // Always enabled — falls back to default coordinates if outlet has none
    }

    get hasRecentUploads() {
        return this.recentUploadNames.length > 0;
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
            this.showToast('Outlet unavailable', 'Outlet record is not available for this visit.', 'warning');
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: {
                componentName: 'c__outlet360Page'
            },
            state: {
                c__recordId: String(this.outletRecordId),
                c__objectApiName: this.outletObjectApiName ? String(this.outletObjectApiName) : 'Account'
            }
        });
    }

    handleCheckIn(event) {
        event?.stopPropagation();
        this.performGeoAction(checkInVisit);
    }

    handleCheckOut(event) {
        event?.stopPropagation();
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
        this.recentUploadNames = files.map(file => file.name);
        const count = files.length;
        this.showToast('Upload complete', `${count} file(s) attached to this visit.`, 'success');
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

        this.meetingNotesSaving = true;
        saveMeetingNotes({
            visitId,
            notes: this.meetingNotes
        })
            .then(() => {
                this.showToast('Saved', 'Meeting notes saved.', 'success');
                this.refreshVisitData({ showErrorToast: false });
            })
            .catch((error) => {
                this.showToast(
                    'Save failed',
                    error?.body?.message || 'Unable to save meeting notes.',
                    'error'
                );
            })
            .finally(() => {
                this.meetingNotesSaving = false;
            });
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
            .catch(() => {
                this.isLoadingTasks = false;
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
    get showTasksCard()  { return this.isLoadingTasks || this.tasks.length > 0; }
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