import { LightningElement, track, wire }  from 'lwc';
import { ShowToastEvent }                 from 'lightning/platformShowToastEvent';
import { refreshApex }                    from '@salesforce/apex';
import { subscribe, publish, MessageContext } from 'lightning/messageService';
import EXPENSE_QUEUED_CHANNEL from '@salesforce/messageChannel/ExpenseQueued__c';
import FAB_CONTROL_CHANNEL    from '@salesforce/messageChannel/FabControl__c';
import getExpenses                        from '@salesforce/apex/ExpenseController.getExpenses';
import getTodaySummary                    from '@salesforce/apex/ExpenseController.getTodaySummary';
import deleteExpense                      from '@salesforce/apex/ExpenseController.deleteExpense';
import submitExpense                      from '@salesforce/apex/ExpenseController.submitExpense';
import resubmitExpense                   from '@salesforce/apex/ExpenseController.resubmitExpense';
import abandonExpense                    from '@salesforce/apex/ExpenseController.abandonExpense';
import updateExpense                      from '@salesforce/apex/ExpenseController.updateExpense';
import submitTodayReport                  from '@salesforce/apex/ExpenseController.submitTodayReport';
import getVisitsForDate                   from '@salesforce/apex/ExpenseController.getVisitsForDate';
import getLinkedVisitIds                  from '@salesforce/apex/ExpenseController.getLinkedVisitIds';
import getLinkedVisits                    from '@salesforce/apex/ExpenseController.getLinkedVisits';
import getFilesForExpense                 from '@salesforce/apex/ExpenseController.getFilesForExpense';
import attachFilesToExpense               from '@salesforce/apex/ExpenseController.attachFilesToExpense';
import removeFileFromExpense              from '@salesforce/apex/ExpenseController.removeFileFromExpense';
import { pendingCount, isOnline }         from 'c/offlineQueueForExpenses';

const STATUS_OPTIONS = ['All', 'Draft', 'Submitted', 'Approved', 'Rejected', 'Abandoned', 'Paid'];
const TYPE_OPTIONS   = [
    'All', 'Travel', 'Food & Beverages', 'Market Execution Expenses',
    'Communications Expenses', 'Miscellaneous Expenses', 'Other'
];
const EXPENSE_TYPES = TYPE_OPTIONS.slice(1);

const MAX_FILE_SIZE_MB = 5;
const ALLOWED_TYPES    = ['image/jpeg','image/png','image/gif','image/webp',
                          'application/pdf','image/heic','image/heif'];

function fileToBase64(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload  = () => resolve({
            fileName  : file.name,
            base64Data: reader.result.split(',')[1],
            mimeType  : file.type
        });
        reader.onerror = () => reject(new Error(`Failed to read ${file.name}`));
        reader.readAsDataURL(file);
    });
}

export default class ExpenseList extends LightningElement {

    @track currentView  = 'today';
    @track activeStatus = 'All';
    @track activeType   = 'All';
    @track isLoading    = false;
    @track hasError     = false;
    @track errorMessage = '';
    @track expenses     = [];
    @track todayTotal   = 0;
    @track todayCount   = 0;
    @track pendingCount = 0;
    @track isSubmitting = false;
    @track reportStatus = null;
    @track _collapsedGroups = new Set();  // date keys collapsed
    @track _collapsedMonths = new Set();  // 'YYYY-MM' keys collapsed
    @track _collapsedYears  = new Set();  // 'YYYY' keys collapsed

    // ── Delete confirm ──────────────────────────────
    @track showDeleteConfirm  = false;
    @track deleteTargetId     = null;
    @track isDeleting         = false;

    // ── Submit confirm ──────────────────────────────
    @track showSubmitConfirm  = false;
    @track submitTargetId     = null;
    @track isSubmittingExpense = false;

    // ── Abandon confirm ─────────────────────────────
    @track showAbandonConfirm = false;
    @track abandonTargetId    = null;
    @track isAbandoning       = false;

    get deleteModalStyle()  { return this.showDeleteConfirm  ? '' : 'display:none'; }
    get submitModalStyle()  { return this.showSubmitConfirm  ? '' : 'display:none'; }
    get abandonModalStyle() { return this.showAbandonConfirm ? '' : 'display:none'; }
    get editModalStyle()    { return this.showEditModal       ? '' : 'display:none'; }
    get viewModalStyle()    { return this.showViewModal       ? '' : 'display:none'; }

    // ── View modal (non-Draft expenses) ────────────
    @track showViewModal       = false;
    @track viewExpense         = null;
    @track viewLinkedVisits    = [];
    @track viewLinkedVisitsLoading = false;
    @track viewFiles           = [];
    @track viewFilesLoading    = false;

    // ── Edit modal ──────────────────────────────────
    @track showEditModal      = false;
    @track editExpense        = null;
    @track editForm           = {};
    @track editErrors         = {};
    @track isSavingEdit       = false;
    @track editVisits         = [];
    @track editVisitsLoading  = false;
    @track editVisitsError    = false;
    // Existing files (already in Salesforce)
    @track existingFiles      = [];   // [{ documentId, versionId, title, extension, fileType, size }]
    @track existingFilesLoading = false;
    // New files picked in this edit session (not yet uploaded)
    @track newFiles           = [];   // [{ id, name, size, mimeType, base64Data, previewUrl }]
    // documentIds queued for deletion on save
    _filesToDelete            = [];

    _wiredExpensesResult;
    _wiredSummaryResult;
    _lmsSubscription;
    _portalMoved = false;
    _portal      = null;
    _styleTag    = null;

    // Unscoped CSS injected into document.head so position:fixed works
    // correctly even when Lightning ancestors have CSS transforms.
    static _PORTAL_CSS = `
        .elc-portal-backdrop {
            position: fixed; inset: 0;
            background: rgba(0,0,0,.45);
            z-index: 99000;
            animation: elcFadeIn .2s ease;
        }
        @keyframes elcFadeIn { from { opacity:0; } to { opacity:1; } }
        .elc-portal-sheet {
            position: fixed; bottom: 0; left: 0; right: 0;
            background: #fff;
            border-radius: 20px 20px 0 0;
            z-index: 99100;
            max-height: 92vh;
            display: flex;
            flex-direction: column;
            box-shadow: 0 -4px 30px rgba(0,0,0,.18);
            animation: elcSlideUp .28s cubic-bezier(.32,1,.28,1);
        }
        @keyframes elcSlideUp { from { transform:translateY(100%); } to { transform:translateY(0); } }
        .elc-portal-dialog {
            position: fixed; top: 50%; left: 50%;
            transform: translate(-50%,-50%);
            width: min(88vw, 320px);
            background: #fff;
            border-radius: 16px;
            z-index: 99100;
            padding: 28px 24px 24px;
            text-align: center;
            box-shadow: 0 8px 40px rgba(0,0,0,.22);
            animation: elcPopIn .2s cubic-bezier(.32,1,.28,1);
        }
        @keyframes elcPopIn {
            from { transform: translate(-50%,-50%) scale(.92); opacity:0; }
            to   { transform: translate(-50%,-50%) scale(1);   opacity:1; }
        }
    `;

    @wire(MessageContext)
    messageContext;

    @wire(getExpenses, {
        todayOnly    : '$isTodayView',
        filterType   : '$activeType',
        filterStatus : '$activeStatus'
    })
    wiredExpenses(result) {
        this._wiredExpensesResult = result;
        this.isLoading = false;
        if (result.data) {
            this.expenses     = result.data;
            this.hasError     = false;
            this.errorMessage = '';
            this._initCollapsedGroups(result.data);
        } else if (result.error) {
            this.hasError     = true;
            this.errorMessage = result.error?.body?.message || 'Failed to load expenses.';
        }
    }

    // Initialize collapse state:
    // - Current month: expand latest 3 dates, collapse rest
    // - Previous months this year: all collapsed
    // - Previous years: all collapsed
    _initCollapsedGroups(expenses) {
        const now          = new Date();
        const currentYear  = now.getFullYear();
        const currentMonth = now.getMonth();

        const collapsedDates  = new Set();
        const collapsedMonths = new Set();
        const collapsedYears  = new Set();

        const dateKeys = [...new Set(
            expenses.map(e => e.expenseDate || 'Unknown Date')
        )].sort((a, b) => b.localeCompare(a));

        let currentMonthDateCount = 0;
        for (const key of dateKeys) {
            if (key === 'Unknown Date') continue;
            const d = new Date(key + 'T00:00:00');
            if (d.getFullYear() === currentYear && d.getMonth() === currentMonth) {
                currentMonthDateCount++;
                if (currentMonthDateCount > 3) collapsedDates.add(key);
            }
        }

        expenses
            .map(e => e.expenseDate).filter(d => {
                if (!d) return false;
                const dt = new Date(d + 'T00:00:00');
                return dt.getFullYear() === currentYear && dt.getMonth() !== currentMonth;
            })
            .forEach(d => collapsedMonths.add(d.substring(0, 7)));

        expenses
            .map(e => e.expenseDate).filter(d => d && new Date(d + 'T00:00:00').getFullYear() < currentYear)
            .forEach(d => {
                collapsedYears.add(d.substring(0, 4));   // collapse the year
                collapsedMonths.add(d.substring(0, 7));  // collapse every month inside it
                collapsedDates.add(d);                   // collapse every date inside it
            });

        this._collapsedGroups = collapsedDates;
        this._collapsedMonths = collapsedMonths;
        this._collapsedYears  = collapsedYears;
    }

    @wire(getTodaySummary)
    wiredSummary(result) {
        this._wiredSummaryResult = result;
        if (result.data) {
            this.todayTotal   = result.data.total        || 0;
            this.todayCount   = result.data.count        || 0;
            this.reportStatus = result.data.reportStatus || null;
        }
    }

    connectedCallback() {
        this.refreshPendingCount();
        this._lmsSubscription = subscribe(
            this.messageContext,
            EXPENSE_QUEUED_CHANNEL,
            () => this.handleExpenseQueuedMessage()
        );
        // Tell FAB it should be visible — we are on the expense tab
        this._fabControl('show');
        this._setupVisibilityObserver();
    }

    _setupVisibilityObserver() {
        if (this._visibilityObserver) return;

        const host = this.template.host;

        const checkVisibility = () => {
            // Walk up the DOM — if any ancestor has display:none we are hidden
            let el = host;
            while (el) {
                const style = window.getComputedStyle(el);
                if (style.display === 'none' || style.visibility === 'hidden') {
                    this._fabControl('hide');
                    return;
                }
                el = el.parentElement;
            }
            this._fabControl('show');
        };

        // MutationObserver watches for style/class/attribute changes on the
        // host and its ancestors — Salesforce sets display:none on the tab
        // container when switching tabs, which this catches reliably.
        this._visibilityObserver = new MutationObserver(checkVisibility);
        this._visibilityObserver.observe(document.body, {
            attributes      : true,
            attributeFilter : ['style', 'class'],
            subtree         : true
        });
    }

    renderedCallback() {
        if (this._portalMoved) return;
        const portal = this.template.querySelector('.elc-portal');
        if (!portal) return;
        // Inject unscoped positioning CSS into document.head
        if (!this._styleTag) {
            this._styleTag = document.createElement('style');
            this._styleTag.textContent = ExpenseList._PORTAL_CSS;
            document.head.appendChild(this._styleTag);
        }
        document.body.appendChild(portal);
        this._portal      = portal;
        this._portalMoved = true;
    }

    disconnectedCallback() {
        this._lmsSubscription = null;
        if (this._portal)   this._portal.remove();
        if (this._styleTag) this._styleTag.remove();
        if (this._visibilityObserver) {
            this._visibilityObserver.disconnect();
            this._visibilityObserver = null;
        }
        // Tell FAB to hide — user has left the expense tab
        this._fabControl('hide');
    }

    handleExpenseQueuedMessage() {
        this.refreshPendingCount();
        refreshApex(this._wiredExpensesResult);
        refreshApex(this._wiredSummaryResult);
    }

    refreshPendingCount() { this.pendingCount = pendingCount(); }

    // ── Getters ─────────────────────────────────────
    get isTodayView()        { return this.currentView === 'today'; }
    get todayTabClass()      { return 'toggle-btn' + (this.currentView === 'today' ? ' active' : ''); }
    get allTabClass()        { return 'toggle-btn' + (this.currentView === 'all'   ? ' active' : ''); }
    get hasPendingExpenses() { return this.pendingCount > 0; }
    get hasNoExpenses()      { return this.todayCount === 0; }
    get isReportSubmitted()  { return this.reportStatus != null && this.reportStatus !== 'Draft'; }
    get filteredExpenses()   { return this.expenses; }
    get isEmpty()            { return !this.isLoading && !this.hasError && this.filteredExpenses.length === 0; }
    get hasActiveFilters()   { return this.activeStatus !== 'All' || this.activeType !== 'All'; }

    // ── 3-level hierarchy: Year > Month > Date ───────────
    // Returns a flat array of row descriptors for the template to iterate.
    // type: 'year' | 'month' | 'date'
    get hierarchicalExpenses() {
        const expenses = this.filteredExpenses;
        if (!expenses || expenses.length === 0) return [];

        const now          = new Date();
        const currentYear  = now.getFullYear();
        const currentMonth = now.getMonth();

        const fmtDate = key => new Date(key + 'T00:00:00').toLocaleDateString('en-IN', {
            weekday: 'short', day: '2-digit', month: 'short', year: 'numeric'
        });
        const fmtMonth = ym => {
            const [y, m] = ym.split('-');
            return new Date(parseInt(y, 10), parseInt(m, 10) - 1, 1)
                .toLocaleDateString('en-IN', { month: 'long', year: 'numeric' });
        };

        // Bucket into three maps
        const curMonthMap = new Map();   // dateKey → []
        const thisYearMap = new Map();   // 'YYYY-MM' → Map(dateKey → [])
        const prevYearMap = new Map();   // 'YYYY' → Map('YYYY-MM' → Map(dateKey → []))

        for (const exp of expenses) {
            const key = exp.expenseDate || 'Unknown Date';
            let yr, mo;
            if (key !== 'Unknown Date') {
                const d = new Date(key + 'T00:00:00');
                yr = d.getFullYear(); mo = d.getMonth();
            }
            if (key === 'Unknown Date' || (yr === currentYear && mo === currentMonth)) {
                if (!curMonthMap.has(key)) curMonthMap.set(key, []);
                curMonthMap.get(key).push(exp);
            } else if (yr === currentYear) {
                const mk = key.substring(0, 7);
                if (!thisYearMap.has(mk)) thisYearMap.set(mk, new Map());
                if (!thisYearMap.get(mk).has(key)) thisYearMap.get(mk).set(key, []);
                thisYearMap.get(mk).get(key).push(exp);
            } else {
                const yk = String(yr), mk = key.substring(0, 7);
                if (!prevYearMap.has(yk)) prevYearMap.set(yk, new Map());
                if (!prevYearMap.get(yk).has(mk)) prevYearMap.get(yk).set(mk, new Map());
                if (!prevYearMap.get(yk).get(mk).has(key)) prevYearMap.get(yk).get(mk).set(key, []);
                prevYearMap.get(yk).get(mk).get(key).push(exp);
            }
        }

        const result = [];
        const dateRow = (dk, expArr, extraClass = '') => {
            const ic = this._collapsedGroups.has(dk);
            return { type: 'date', isYear: false, isMonth: false, hasExpenses: true, icon: 'utility:clock', key: dk,
                label: dk === 'Unknown Date' ? 'Unknown Date' : fmtDate(dk),
                count: expArr.length, expenses: expArr, isCollapsed: ic,
                headerClass: 'expense-date-header' + (extraClass ? ' ' + extraClass : '') + (ic ? ' is-collapsed' : ''),
                bodyStyle: ic ? 'display:none' : '',
                chevronClass: 'date-chevron' + (ic ? ' chevron-collapsed' : '') };
        };
        const monthRow = (mk, count, extraClass = '') => {
            const ic = this._collapsedMonths.has(mk);
            return { type: 'month', isYear: false, isMonth: true, hasExpenses: false, icon: 'utility:event', key: mk, label: fmtMonth(mk), count, isCollapsed: ic,
                headerClass: 'expense-month-header' + (extraClass ? ' ' + extraClass : '') + (ic ? ' is-collapsed' : ''),
                bodyStyle: ic ? 'display:none' : '',
                chevronClass: 'date-chevron' + (ic ? ' chevron-collapsed' : '') };
        };

        // Current month — flat date rows
        [...curMonthMap.keys()].sort((a, b) => b.localeCompare(a))
            .forEach(dk => result.push(dateRow(dk, curMonthMap.get(dk))));

        // Previous months of current year — month header + indented date rows
        [...thisYearMap.keys()].sort((a, b) => b.localeCompare(a)).forEach(mk => {
            const dm = thisYearMap.get(mk);
            const total = [...dm.values()].reduce((s, a) => s + a.length, 0);
            result.push(monthRow(mk, total));
            if (!this._collapsedMonths.has(mk)) {
                [...dm.keys()].sort((a, b) => b.localeCompare(a))
                    .forEach(dk => result.push(dateRow(dk, dm.get(dk), 'expense-date-header--indented')));
            }
        });

        // Previous years — year header > month header > indented date rows
        [...prevYearMap.keys()].sort((a, b) => b.localeCompare(a)).forEach(yk => {
            const ym   = prevYearMap.get(yk);
            const yic  = this._collapsedYears.has(yk);
            const ytot = [...ym.values()].reduce((s, mm) =>
                s + [...mm.values()].reduce((ss, a) => ss + a.length, 0), 0);
            result.push({ type: 'year', isYear: true, isMonth: false, hasExpenses: false, icon: 'utility:date_input', key: yk, label: yk, count: ytot, isCollapsed: yic,
                headerClass: 'expense-year-header' + (yic ? ' is-collapsed' : ''),
                bodyStyle: yic ? 'display:none' : '',
                chevronClass: 'date-chevron' + (yic ? ' chevron-collapsed' : '') });
            if (!yic) {
                [...ym.keys()].sort((a, b) => b.localeCompare(a)).forEach(mk => {
                    const dm     = ym.get(mk);
                    const mtot   = [...dm.values()].reduce((s, a) => s + a.length, 0);
                    result.push(monthRow(mk, mtot, 'expense-month-header--indented'));
                    if (!this._collapsedMonths.has(mk)) {
                        [...dm.keys()].sort((a, b) => b.localeCompare(a))
                            .forEach(dk => result.push(dateRow(dk, dm.get(dk), 'expense-date-header--indented2')));
                    }
                });
            }
        });

        return result;
    }

    handleToggleGroup(event) {
        const { key, type } = event.currentTarget.dataset;
        if (type === 'year') {
            const next = new Set(this._collapsedYears);
            next.has(key) ? next.delete(key) : next.add(key);
            this._collapsedYears = next;
        } else if (type === 'month') {
            const next = new Set(this._collapsedMonths);
            next.has(key) ? next.delete(key) : next.add(key);
            this._collapsedMonths = next;
        } else {
            const next = new Set(this._collapsedGroups);
            next.has(key) ? next.delete(key) : next.add(key);
            this._collapsedGroups = next;
        }
    }

    get formattedTodayTotal() {
        return new Intl.NumberFormat('en-IN', {
            style: 'currency', currency: 'INR', maximumFractionDigits: 2
        }).format(this.todayTotal);
    }

    get statusFilterOptions() {
        return STATUS_OPTIONS.map(s => ({
            label: s === 'All' ? 'All Statuses' : s, value: s,
            selected: this.activeStatus === s
        }));
    }

    get typeFilterOptions() {
        return TYPE_OPTIONS.map(t => ({
            label: t === 'All' ? 'All Types' : t, value: t,
            selected: this.activeType === t
        }));
    }

    get emptyTitle() {
        if (this.activeStatus !== 'All' || this.activeType !== 'All') return 'No matching expenses';
        return this.currentView === 'today' ? 'No expenses today' : 'No expenses found';
    }

    get emptySubtitle() {
        if (this.activeStatus !== 'All' || this.activeType !== 'All') return 'Try adjusting your filters.';
        return 'Tap the + button to log your first expense.';
    }

    // ── Edit form getters ───────────────────────────
    get editTypeOptions() {
        return EXPENSE_TYPES.map(t => ({
            label: t, value: t, selected: this.editForm.expenseType === t
        }));
    }

    get editHasVisits()       { return this.editVisits.length > 0; }
    get editNoVisitsForDate() { return !this.editVisitsLoading && !this.editVisitsError && this.editVisits.length === 0; }
    get editSelectedCount()   { return this.editVisits.filter(v => v.selected).length; }
    get editSelectedCountMsg(){ return this.editSelectedCount > 0 ? `${this.editSelectedCount} visit(s) selected` : ''; }

    // ── File getters ────────────────────────────────
    get hasExistingFiles() { return this.existingFiles.length > 0; }
    get hasNewFiles()      { return this.newFiles.length > 0; }
    get hasAnyFiles()      { return this.hasExistingFiles || this.hasNewFiles; }

    get enrichedExistingFiles() {
        return this.existingFiles.map(f => ({
            ...f,
            formattedSize: this._formatSize(parseInt(f.size, 10)),
            isImage      : ['jpg','jpeg','png','gif','webp','heic','heif'].includes(f.extension),
            downloadUrl  : `/sfc/servlet.shepherd/version/download/${f.versionId}`
        }));
    }

    get enrichedNewFiles() {
        return this.newFiles.map(f => ({
            ...f,
            formattedSize: this._formatSize(f.size)
        }));
    }

    _formatSize(bytes) {
        return bytes >= 1024 * 1024
            ? `${(bytes / 1024 / 1024).toFixed(1)} MB`
            : `${Math.round(bytes / 1024)} KB`;
    }

    // ── Filters & view ──────────────────────────────
    handleViewChange(event)    { this.currentView = event.currentTarget.dataset.view; this.isLoading = true; }
    handleStatusFilter(event)  { this.activeStatus = event.target.value; this.isLoading = true; }
    handleTypeFilter(event)    { this.activeType   = event.target.value; this.isLoading = true; }
    clearAllFilters()          { this.activeStatus = 'All'; this.activeType = 'All'; }

    // ── Submit report ───────────────────────────────
    async handleSubmitReport() {
        if (this.isSubmitting) return;
        this.isSubmitting = true;
        try {
            await submitTodayReport();
            this.reportStatus = 'Submitted';
            this.dispatchEvent(new ShowToastEvent({
                title: 'Report Submitted',
                message: 'Today\'s expense report has been submitted for approval.',
                variant: 'success'
            }));
            await refreshApex(this._wiredSummaryResult);
            await refreshApex(this._wiredExpensesResult);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Submission Failed',
                message: err?.body?.message || 'Could not submit the report. Please try again.',
                variant: 'error'
            }));
        } finally {
            this.isSubmitting = false;
        }
    }

    // ── Delete — show confirm ───────────────────────
    handleDeleteExpense(event) {
        this.deleteTargetId    = event.detail.expenseId;
        this.showDeleteConfirm = true;
    }

    cancelDelete() {
        this.showDeleteConfirm = false;
        this.deleteTargetId    = null;
    }

    async confirmDelete() {
        this.isDeleting = true;
        try {
            await deleteExpense({ expenseId: this.deleteTargetId });
            this.dispatchEvent(new ShowToastEvent({
                title: 'Deleted', message: 'Expense deleted successfully.', variant: 'success'
            }));
            refreshApex(this._wiredExpensesResult);
            refreshApex(this._wiredSummaryResult);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error', message: err?.body?.message || 'Could not delete expense.', variant: 'error'
            }));
        } finally {
            this.isDeleting        = false;
            this.showDeleteConfirm = false;
            this.deleteTargetId    = null;
        }
    }

    // ── Submit individual expense — show confirm ────
    handleSubmitExpense(event) {
        this.submitTargetId    = event.detail.expenseId;
        this.showSubmitConfirm = true;
    }

    cancelSubmit() {
        this.showSubmitConfirm = false;
        this.submitTargetId    = null;
    }

    async confirmSubmit() {
        this.isSubmittingExpense = true;
        try {
            await submitExpense({ expenseId: this.submitTargetId });
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Submitted',
                message: 'Expense submitted successfully.',
                variant: 'success'
            }));
            refreshApex(this._wiredExpensesResult);
            refreshApex(this._wiredSummaryResult);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Error',
                message: err?.body?.message || 'Could not submit expense.',
                variant: 'error'
            }));
        } finally {
            this.isSubmittingExpense = false;
            this.showSubmitConfirm   = false;
            this.submitTargetId      = null;
        }
    }

    // ── Resubmit (Rejected → Draft, opens edit modal) ──
    async handleResubmitExpense(event) {
        const expenseId = event.detail.expenseId;
        try {
            await resubmitExpense({ expenseId });
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Ready to Edit',
                message: 'Expense has been reset to Draft. Make your changes and resubmit.',
                variant: 'success'
            }));
            // Refresh so the card re-renders as Draft, then open the edit modal
            await refreshApex(this._wiredExpensesResult);
            await refreshApex(this._wiredSummaryResult);
            // Find the freshly-refreshed expense and open its edit modal
            const exp = this.expenses.find(e => e.id === expenseId);
            if (exp) this._openEditModal(exp);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Error',
                message: err?.body?.message || 'Could not resubmit expense.',
                variant: 'error'
            }));
        }
    }

    // ── Abandon — show confirm dialog ───────────────
    handleAbandonExpense(event) {
        this.abandonTargetId    = event.detail.expenseId;
        this.showAbandonConfirm = true;
    }

    cancelAbandon() {
        this.showAbandonConfirm = false;
        this.abandonTargetId    = null;
    }

    async confirmAbandon() {
        this.isAbandoning = true;
        try {
            await abandonExpense({ expenseId: this.abandonTargetId });
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Abandoned',
                message: 'Expense has been abandoned and kept for record.',
                variant: 'success'
            }));
            refreshApex(this._wiredExpensesResult);
            refreshApex(this._wiredSummaryResult);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Error',
                message: err?.body?.message || 'Could not abandon expense.',
                variant: 'error'
            }));
        } finally {
            this.isAbandoning       = false;
            this.showAbandonConfirm = false;
            this.abandonTargetId    = null;
        }
    }

    _fabControl(action) {
        publish(this.messageContext, FAB_CONTROL_CHANNEL, { action });
    }

    // ── Card click — edit (Draft) or view (all others) ──
    handleCardClick(event) {
        const expenseId = event.detail.expenseId;
        const exp = this.expenses.find(e => e.id === expenseId);
        if (!exp) return;

        if (exp.status === 'Draft') {
            this._openEditModal(exp);
        } else {
            this._openViewModal(exp);
        }
    }

    _openViewModal(exp) {
        this.viewExpense            = exp;
        this.viewLinkedVisits       = [];
        this.viewFiles              = [];
        this.viewLinkedVisitsLoading = false;
        this.viewFilesLoading       = false;
        this.showViewModal          = true;
        this._fabControl('hide');
        this._loadViewVisits(exp.id);
        this._loadViewFiles(exp.id);
    }

    closeViewModal() {
        this.showViewModal = false;
        this.viewExpense   = null;
        this._fabControl('show');
    }

    async _loadViewVisits(expenseId) {
        this.viewLinkedVisitsLoading = true;
        try {
            const raw = await getLinkedVisits({ expenseId });
            this.viewLinkedVisits = raw || [];
        } catch (e) {
            this.viewLinkedVisits = [];
        } finally {
            this.viewLinkedVisitsLoading = false;
        }
    }

    async _loadViewFiles(expenseId) {
        this.viewFilesLoading = true;
        try {
            const raw = await getFilesForExpense({ expenseId });
            this.viewFiles = (raw || []).map(f => ({
                ...f,
                formattedSize: this._formatSize(parseInt(f.size, 10)),
                downloadUrl  : `/sfc/servlet.shepherd/version/download/${f.versionId}`
            }));
        } catch (e) {
            this.viewFiles = [];
        } finally {
            this.viewFilesLoading = false;
        }
    }

    get viewHasVisits() { return this.viewLinkedVisits.length > 0; }
    get viewHasFiles()  { return this.viewFiles.length > 0; }

    get viewStatusClass() {
        if (!this.viewExpense) return 'status-badge';
        const s = this.viewExpense.status?.toLowerCase().replace(/\s+/g, '-');
        return `status-badge status-${s}`;
    }
    get viewStatus()      { return this.viewExpense?.status      || ''; }
    get viewName()        { return this.viewExpense?.name        || ''; }
    get viewExpenseType() { return this.viewExpense?.expenseType || ''; }
    get viewExpenseDate() { return this.viewExpense?.expenseDate || ''; }
    get viewDescription() { return this.viewExpense?.description || ''; }
    get viewHasDescription() { return !!this.viewExpense?.description; }
    get viewRejectionReason() { return this.viewExpense?.rejectionReason || ''; }
    get viewHasRejectionReason() { return this.viewExpense?.status === 'Rejected' && !!this.viewExpense?.rejectionReason; }

    get viewFormattedAmount() {
        if (!this.viewExpense?.amount) return '—';
        return new Intl.NumberFormat('en-IN', {
            style: 'currency', currency: 'INR', maximumFractionDigits: 2
        }).format(this.viewExpense.amount);
    }

    _openEditModal(exp) {

        this.editExpense  = exp;
        this.editForm     = {
            amount     : exp.amount != null ? String(exp.amount) : '',
            expenseType: exp.expenseType || '',
            expenseDate: exp.expenseDate || '',
            description: exp.description || ''
        };
        this.editErrors         = {};
        this.isSavingEdit       = false;
        this.editVisits         = [];
        this.editVisitsError    = false;
        this.existingFiles      = [];
        this.newFiles           = [];
        this._filesToDelete     = [];
        this.existingFilesLoading = false;
        this.showEditModal      = true;
        this._fabControl('hide');

        this._loadEditVisits(exp.expenseDate, exp.id);
        this._loadExistingFiles(exp.id);
    }

    async _loadEditVisits(dateStr, expenseId) {
        if (!dateStr) return;
        this.editVisitsLoading = true;
        this.editVisitsError   = false;
        try {
            // Fetch available visits for the date AND already-linked visit IDs in parallel
            const [raw, linkedIds] = await Promise.all([
                getVisitsForDate({ expenseDate: dateStr }),
                expenseId ? getLinkedVisitIds({ expenseId }) : Promise.resolve([])
            ]);
            const linked = new Set(linkedIds || []);
            this.editVisits = (raw || []).map(v => {
                const selected = linked.has(v.id);
                return {
                    id        : v.id,
                    name      : v.name,
                    outletName: v.outletName || '—',
                    selected,
                    checkClass: selected ? 'visit-check visit-check--on' : 'visit-check'
                };
            });
        } catch (err) {
            this.editVisitsError = true;
            this.editVisits      = [];
        } finally {
            this.editVisitsLoading = false;
        }
    }

    async _loadExistingFiles(expenseId) {
        this.existingFilesLoading = true;
        try {
            const raw = await getFilesForExpense({ expenseId });
            this.existingFiles = raw || [];
        } catch (err) {
            console.error('[expenseList] getFilesForExpense failed:', err);
            this.existingFiles = [];
        } finally {
            this.existingFilesLoading = false;
        }
    }

    // Mark an existing file for deletion on save (optimistic UI removal)
    handleRemoveExistingFile(event) {
        const documentId = event.currentTarget.dataset.id;
        this._filesToDelete = [...this._filesToDelete, documentId];
        this.existingFiles  = this.existingFiles.filter(f => f.documentId !== documentId);
    }

    // Trigger hidden file input
    handleTriggerFilePicker() {
        if (!isOnline()) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'You\'re Offline',
                message: 'File uploads require an internet connection.',
                variant: 'warning', mode: 'sticky'
            }));
            return;
        }
        const input = (this._portal || this.template).querySelector('.edit-file-input');
        if (input) input.click();
    }

    async handleEditFileChange(event) {
        const files = Array.from(event.target.files);
        if (!files.length) return;

        const tooBig  = files.filter(f => f.size > MAX_FILE_SIZE_MB * 1024 * 1024);
        const badType = files.filter(f => !ALLOWED_TYPES.includes(f.type));
        const valid   = files.filter(f =>
            f.size <= MAX_FILE_SIZE_MB * 1024 * 1024 && ALLOWED_TYPES.includes(f.type)
        );

        if (tooBig.length) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'File Too Large',
                message: `${tooBig.map(f => f.name).join(', ')} exceed${tooBig.length > 1 ? '' : 's'} the ${MAX_FILE_SIZE_MB}MB limit.`,
                variant: 'warning'
            }));
        }
        if (badType.length) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Unsupported File Type',
                message: `Only images and PDFs are allowed.`,
                variant: 'warning'
            }));
        }

        for (const file of valid) {
            try {
                const { fileName, base64Data, mimeType } = await fileToBase64(file);
                const previewUrl = mimeType.startsWith('image/')
                    ? `data:${mimeType};base64,${base64Data}` : null;
                this.newFiles = [...this.newFiles, {
                    id: `nf_${Date.now()}_${Math.random()}`,
                    name: fileName, size: file.size, mimeType, base64Data, previewUrl
                }];
            } catch (err) {
                console.error('[expenseList] file read error:', err);
            }
        }
        event.target.value = '';
    }

    handleRemoveNewFile(event) {
        const id = event.currentTarget.dataset.id;
        this.newFiles = this.newFiles.filter(f => f.id !== id);
    }

    closeEditModal() {
        this.showEditModal      = false;
        this.editExpense        = null;
        this.existingFiles      = [];
        this.newFiles           = [];
        this._filesToDelete     = [];
        this._fabControl('show');
    }

    handleEditInput(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.editForm = { ...this.editForm, [field]: value };
        if (this.editErrors[field]) {
            const e = { ...this.editErrors };
            delete e[field];
            this.editErrors = e;
        }
        if (field === 'expenseDate') {
            this.editVisits = [];
            this._loadEditVisits(value, null);   // no pre-selection for a new date
        }
    }

    handleEditVisitToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.editVisits = this.editVisits.map(v => {
            const selected = v.id === id ? !v.selected : v.selected;
            return { ...v, selected, checkClass: selected ? 'visit-check visit-check--on' : 'visit-check' };
        });
    }

    validateEdit() {
        const e = {};
        if (!this.editForm.amount || Number(this.editForm.amount) <= 0)
            e.amount = 'Please enter a valid amount greater than 0.';
        if (!this.editForm.expenseType)
            e.expenseType = 'Please select an expense type.';
        if (!this.editForm.expenseDate)
            e.expenseDate = 'Please select a date.';
        this.editErrors = e;
        return Object.keys(e).length === 0;
    }

    async handleSaveEdit() {
        if (!this.validateEdit()) return;
        this.isSavingEdit = true;
        try {
            // 1. Update expense fields + visit links
            const saveResult = await updateExpense({
                expenseId  : this.editExpense.id,
                amount     : parseFloat(this.editForm.amount),
                expenseType: this.editForm.expenseType,
                expenseDate: this.editForm.expenseDate,
                description: this.editForm.description,
                visitIds   : this.editVisits.filter(v => v.selected).map(v => v.id)
            });

            // 2. Delete removed files (parallel)
            if (this._filesToDelete.length > 0) {
                await Promise.all(
                    this._filesToDelete.map(documentId =>
                        removeFileFromExpense({ documentId })
                    )
                );
            }

            // 3. Upload new files (if any and online)
            if (this.newFiles.length > 0) {
                if (isOnline()) {
                    await attachFilesToExpense({
                        expenseId: this.editExpense.id,
                        files: this.newFiles.map(f => ({
                            fileName  : f.name,
                            base64Data: f.base64Data,
                            mimeType  : f.mimeType
                        }))
                    });
                } else {
                    this.dispatchEvent(new ShowToastEvent({
                        title  : 'Files Not Uploaded',
                        message: 'Expense saved but new files could not be uploaded while offline.',
                        variant: 'warning'
                    }));
                }
            }

            // Show policy warning if breach occurred (sticky so rep reads it)
            if (saveResult && saveResult.hasPolicyWarning) {
                this.dispatchEvent(new ShowToastEvent({
                    title  : '⚠ Policy Limit Exceeded',
                    message: saveResult.warningMessage,
                    variant: 'warning',
                    mode   : 'sticky'
                }));
            }

            this.dispatchEvent(new ShowToastEvent({
                title: 'Saved', message: 'Expense updated successfully.', variant: 'success'
            }));
            this.closeEditModal();   // also publishes 'show' to FAB
            refreshApex(this._wiredExpensesResult);
            refreshApex(this._wiredSummaryResult);
        } catch (err) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Save Failed',
                message: err?.body?.message || 'Could not update expense.',
                variant: 'error'
            }));
        } finally {
            this.isSavingEdit = false;
        }
    }
}