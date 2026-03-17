import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin }        from 'lightning/navigation';
import { ShowToastEvent }       from 'lightning/platformShowToastEvent';
import { refreshApex }          from '@salesforce/apex';
import getReportDetail          from '@salesforce/apex/ManagerExpenseController.getReportDetail';
import processReportApproval    from '@salesforce/apex/ManagerExpenseController.processReportApproval';
import bulkUpdateExpenseStatus  from '@salesforce/apex/ManagerExpenseController.bulkUpdateExpenseStatus';
import updateExpenseStatus      from '@salesforce/apex/ManagerExpenseController.updateExpenseStatus';

const STATUS_CLASSES = {
    'Draft'    : 'report-status-badge badge-draft',
    'Submitted': 'report-status-badge badge-submitted',
    'Approved' : 'report-status-badge badge-approved',
    'Rejected' : 'report-status-badge badge-rejected',
    'Paid'     : 'report-status-badge badge-paid'
};

const EXPENSE_STATUS_CLASSES = {
    'Draft'    : 'status-pill pill-draft',
    'Submitted': 'status-pill pill-submitted',
    'Approved' : 'status-pill pill-approved',
    'Rejected' : 'status-pill pill-rejected',
    'Paid'     : 'status-pill pill-paid'
};

const POPUP_STATUS_CLASSES = {
    'Draft'    : 'med-status-badge med-badge-draft',
    'Submitted': 'med-status-badge med-badge-submitted',
    'Approved' : 'med-status-badge med-badge-approved',
    'Rejected' : 'med-status-badge med-badge-rejected',
    'Paid'     : 'med-status-badge med-badge-paid'
};

const ACTIONABLE_STATUSES = new Set(['Submitted']);

const fmt = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 });

function formatDate(d) {
    if (!d) return '—';
    return new Date(d + 'T00:00:00').toLocaleDateString('en-IN', {
        day: '2-digit', month: 'short', year: 'numeric'
    });
}

function formatFileSize(bytes) {
    if (!bytes) return '';
    if (bytes < 1024)       return bytes + ' B';
    if (bytes < 1024*1024)  return (bytes/1024).toFixed(1) + ' KB';
    return (bytes/(1024*1024)).toFixed(1) + ' MB';
}

// Unscoped CSS for the expense detail popup — injected into document.head
// so position:fixed works outside the LWC shadow root
const POPUP_CSS = `
    .med-backdrop {
        position: fixed; inset: 0;
        background: rgba(0,0,0,.5);
        z-index: 8500;
        animation: medFadeIn .18s ease;
    }
    @keyframes medFadeIn { from{opacity:0} to{opacity:1} }
    .med-popup {
        position: fixed;
        top: 50%; left: 50%;
        transform: translate(-50%, -50%);
        width: min(780px, 92vw);
        max-height: 90vh;
        background: #fff;
        border-radius: 14px;
        z-index: 8600;
        display: flex;
        flex-direction: column;
        box-shadow: 0 12px 48px rgba(0,0,0,.22);
        animation: medPopIn .2s cubic-bezier(.32,1,.28,1);
    }
    @keyframes medPopIn {
        from { transform: translate(-50%,-50%) scale(.94); opacity:0; }
        to   { transform: translate(-50%,-50%) scale(1);   opacity:1; }
    }
`;

export default class ManagerExpenseDetail extends NavigationMixin(LightningElement) {

    @api reportId;

    @track detail          = { report: {}, expenses: [] };
    @track isLoading       = true;
    @track isProcessing    = false;
    @track showRejectModal = false;
    @track rejectComment   = '';

    // Expense detail popup
    @track showExpensePopup = false;
    @track popupExpense     = {};

    _pendingRejectAction = null;
    _wiredDetailResult;
    _portalMoved = false;
    _portal      = null;
    _styleTag    = null;

    @wire(getReportDetail, { reportId: '$reportId' })
    wiredDetail(result) {
        this._wiredDetailResult = result;
        this.isLoading = false;
        if (result.data) {
            this.detail = result.data;
        } else if (result.error) {
            this.showToast('Error', result.error?.body?.message || 'Failed to load report.', 'error');
        }
    }

    renderedCallback() {
        if (this._portalMoved) return;
        const portal = this.template.querySelector('.med-portal');
        if (!portal) return;
        if (!this._styleTag) {
            this._styleTag = document.createElement('style');
            this._styleTag.textContent = POPUP_CSS;
            document.head.appendChild(this._styleTag);
        }
        document.body.appendChild(portal);
        this._portal      = portal;
        this._portalMoved = true;
    }

    disconnectedCallback() {
        if (this._portal)   this._portal.remove();
        if (this._styleTag) this._styleTag.remove();
    }

    // ── Popup visibility style (permanent div toggled by display) ──
    get expensePopupStyle() { return this.showExpensePopup ? '' : 'display:none'; }
    get rejectModalStyle()  { return this.showRejectModal  ? '' : 'display:none'; }

    // ── Popup computed properties ────────────────────────
    get popupStatusClass()    { return POPUP_STATUS_CLASSES[this.popupExpense?.status] || 'med-status-badge med-badge-draft'; }
    get popupFormattedAmount(){ return this.popupExpense?.amount != null ? fmt.format(this.popupExpense.amount) : '—'; }
    get popupFormattedDate()  { return formatDate(this.popupExpense?.expenseDate); }
    get popupDescription()    { return this.popupExpense?.description || 'No description provided.'; }
    get popupIsActionable()   { return this.popupExpense?.status === 'Submitted'; }
    get popupHasVisits()      { return (this.popupExpense?.linkedVisits?.length || 0) > 0; }
    get popupHasFiles()       { return (this.popupExpense?.files?.length || 0) > 0; }
    get popupHasRejectionReason() { return this.popupExpense?.status === 'Rejected' && !!this.popupExpense?.rejectionReason; }

    get popupHasPolicyBreach()    { return !!this.popupExpense?.policyBreach; }
    get popupBreachHasTypeCap()   {
        const t = this.popupExpense?.policyBreachType;
        return t === 'Type Cap' || t === 'Both';
    }
    get popupBreachHasAllowance() {
        const t = this.popupExpense?.policyBreachType;
        return t === 'Monthly Allowance' || t === 'Both';
    }
    get popupCapAtTime() {
        return this._fmtCurrency(this.popupExpense?.policyCapAtTime);
    }
    get popupBreachAmount() {
        return this._fmtCurrency(this.popupExpense?.policyBreachAmount);
    }
    get popupAllowanceAtTime() {
        return this._fmtCurrency(this.popupExpense?.allowanceAtTime);
    }
    get popupAllowanceUsed() {
        return this._fmtCurrency(this.popupExpense?.allowanceUsedAtTime);
    }
    _fmtCurrency(val) {
        if (val == null) return '—';
        return new Intl.NumberFormat('en-IN', {
            style: 'currency', currency: 'INR', maximumFractionDigits: 2
        }).format(val);
    }

    // ── Popup approve / reject ───────────────────────────
    async handlePopupApprove() {
        const expenseId = this.popupExpense?.id;
        if (!expenseId) return;
        await this.updateSingle(expenseId, 'Approved');
        // Refresh popup status from updated wire data
        const updated = (this.detail?.expenses || []).find(e => e.id === expenseId);
        if (updated) this.popupExpense = { ...this.popupExpense, status: updated.status };
        else this.closeExpensePopup();
    }

    handlePopupReject() {
        const expenseId = this.popupExpense?.id;
        if (!expenseId) return;
        this._pendingRejectAction = { type: 'single', expenseId };
        this.rejectComment   = '';
        this.showRejectModal = true;
    }

    // ── Expense row click → open popup ──────────────────
    handleExpenseRowClick(event) {
        const expId = event.currentTarget.dataset.id;
        const raw   = (this.detail?.expenses || []).find(e => e.id === expId);
        if (!raw) return;

        // Enrich visits with record URLs and files with formatted size
        const linkedVisits = (raw.linkedVisits || []).map(v => ({
            ...v,
            recordUrl: '/lightning/r/Visit__c/' + v.id + '/view'
        }));
        const files = (raw.files || []).map(f => ({
            ...f,
            formattedSize: formatFileSize(f.fileSize)
        }));

        this.popupExpense     = { ...raw, linkedVisits, files };
        this.showExpensePopup = true;
    }

    closeExpensePopup() {
        this.showExpensePopup = false;
        this.popupExpense     = {};
    }

    handleFilePreview(event) {
        event.preventDefault();
        event.stopPropagation();
        const documentId      = event.currentTarget.dataset.documentId;
        // Snapshot the current expense so we can restore the popup after preview closes
        const savedExpense    = this.popupExpense;

        // Temporarily hide our portal so it doesn't block the SF file preview overlay
        if (this._portal) this._portal.style.display = 'none';

        // Watch for Lightning's file preview modal to appear then disappear
        const observer = new MutationObserver(() => {
            // Lightning file preview adds a div.modal-container or similar to body
            const sfPreview = document.querySelector('.slds-file-preview-container, .forceFilePreview, [data-file-preview]');
            if (sfPreview) {
                // Preview is open — watch for it to be removed
                const closeObserver = new MutationObserver(() => {
                    if (!document.body.contains(sfPreview)) {
                        closeObserver.disconnect();
                        // Restore our popup
                        if (this._portal) this._portal.style.display = '';
                        this.popupExpense     = savedExpense;
                        this.showExpensePopup = true;
                    }
                });
                closeObserver.observe(document.body, { childList: true, subtree: true });
                observer.disconnect();
            }
        });
        observer.observe(document.body, { childList: true, subtree: true });

        // Safety fallback: if SF preview never detected, restore after 10s
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            observer.disconnect();
            if (this._portal && this._portal.style.display === 'none') {
                this._portal.style.display = '';
                this.popupExpense     = savedExpense;
                this.showExpensePopup = true;
            }
        }, 10000);

        this[NavigationMixin.Navigate]({
            type       : 'standard__namedPage',
            attributes : { pageName: 'filePreview' },
            state      : { recordIds: documentId }
        });
    }

    stopRowPropagation(event) { event.stopPropagation(); }

    // ── Computed ────────────────────────────────────────
    get formattedReportDate() {
        const d = this.detail?.report?.reportDate;
        if (!d) return '—';
        return new Date(d + 'T00:00:00').toLocaleDateString('en-IN', {
            weekday: 'short', day: '2-digit', month: 'short', year: 'numeric'
        });
    }

    get formattedTotal() {
        const amt = this.detail?.report?.totalAmount || 0;
        return new Intl.NumberFormat('en-IN', {
            style: 'currency', currency: 'INR', maximumFractionDigits: 2
        }).format(amt);
    }

    get reportStatusClass() {
        return STATUS_CLASSES[this.detail?.report?.status] || 'report-status-badge badge-draft';
    }

    get hasExpenses()  { return this.detail?.expenses?.length > 0; }

    get enrichedExpenses() {
        return (this.detail?.expenses || []).map(e => ({
            ...e,
            formattedDate  : formatDate(e.expenseDate),
            formattedAmount: fmt.format(e.amount || 0),
            truncatedDesc  : e.description && e.description.length > 55
                                ? e.description.substring(0, 55) + '…'
                                : (e.description || '—'),
            statusClass    : EXPENSE_STATUS_CLASSES[e.status] || 'status-pill pill-draft',
            rowClass       : 'expense-row status-row-' + (e.status || '').toLowerCase(),
            isActionable   : ACTIONABLE_STATUSES.has(e.status),
            visitDisplay   : e.visitName || '—'
        }));
    }

    // ── Navigation ───────────────────────────────────────
    handleBack() {
        this.dispatchEvent(new CustomEvent('back', { bubbles: true, composed: true }));
    }

    // ── Report-level approval ────────────────────────────
    async handleApproveReport() {
        await this.processReport('Approve', '');
    }

    handleRejectReport() {
        this._pendingRejectAction = { type: 'report' };
        this.rejectComment = '';
        this.showRejectModal = true;
    }

    async processReport(action, comments) {
        const workitemId = this.detail?.report?.workitemId;
        if (!workitemId) {
            this.showToast('Info', 'No pending approval workitem found for this report.', 'warning');
            return;
        }
        this.isProcessing = true;
        try {
            await processReportApproval({ workitemId, action, comments });
            this.showToast('Success',
                `Expense Report ${action === 'Approve' ? 'approved' : 'rejected'} successfully.`,
                'success');
            await refreshApex(this._wiredDetailResult);
            this.dispatchEvent(new CustomEvent('reportprocessed', { bubbles: true, composed: true }));
        } catch (err) {
            this.showToast('Error', err?.body?.message || 'Action failed.', 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    // ── Bulk expense updates ─────────────────────────────
    async handleApprovePending() {
        await this.bulkUpdate('Submitted', 'Approved');
    }

    handleRejectPending() {
        this._pendingRejectAction = { type: 'bulk', scope: 'Submitted' };
        this.rejectComment = '';
        this.showRejectModal = true;
    }

    async bulkUpdate(scope, newStatus, rejectionReason) {
        this.isProcessing = true;
        try {
            await bulkUpdateExpenseStatus({ reportId: this.reportId, scope, newStatus, rejectionReason: rejectionReason || '' });
            const label = scope === 'All' ? 'All expenses' : 'Pending expenses';
            this.showToast('Success', `${label} ${newStatus.toLowerCase()} successfully.`, 'success');
            await refreshApex(this._wiredDetailResult);
        } catch (err) {
            this.showToast('Error', err?.body?.message || 'Bulk update failed.', 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    // ── Individual expense updates ───────────────────────
    async handleApproveExpense(event) {
        await this.updateSingle(event.currentTarget.dataset.id, 'Approved', '');
    }

    handleRejectExpense(event) {
        this._pendingRejectAction = { type: 'single', expenseId: event.currentTarget.dataset.id };
        this.rejectComment = '';
        this.showRejectModal = true;
    }

    async updateSingle(expenseId, newStatus, rejectionReason) {
        this.isProcessing = true;
        try {
            await updateExpenseStatus({ expenseId, newStatus, rejectionReason: rejectionReason || '' });
            this.showToast('Success', `Expense ${newStatus.toLowerCase()} successfully.`, 'success');
            await refreshApex(this._wiredDetailResult);
        } catch (err) {
            this.showToast('Error', err?.body?.message || 'Update failed.', 'error');
        } finally {
            this.isProcessing = false;
        }
    }

    // ── Reject comment modal ─────────────────────────────
    handleCommentInput(event) { this.rejectComment = event.target.value; }

    cancelReject() {
        this.showRejectModal      = false;
        this._pendingRejectAction = null;
        this.rejectComment        = '';
    }

    async confirmReject() {
        this.showRejectModal = false;
        const action  = this._pendingRejectAction;
        const comment = this.rejectComment;
        this._pendingRejectAction = null;
        if (!action) return;
        if (action.type === 'report')      await this.processReport('Reject', comment);
        else if (action.type === 'bulk')   await this.bulkUpdate(action.scope, 'Rejected', comment);
        else if (action.type === 'single') {
            await this.updateSingle(action.expenseId, 'Rejected', comment);
            // If rejection was triggered from the popup, sync popup status
            if (this.showExpensePopup && this.popupExpense?.id === action.expenseId) {
                const updated = (this.detail?.expenses || []).find(e => e.id === action.expenseId);
                if (updated) this.popupExpense = { ...this.popupExpense, status: updated.status };
            }
        }
        this.rejectComment = '';
    }

    // ── Utility ──────────────────────────────────────────
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}