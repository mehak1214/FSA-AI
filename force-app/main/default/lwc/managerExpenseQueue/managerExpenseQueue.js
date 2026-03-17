import { LightningElement, track, wire } from 'lwc';
import { refreshApex }             from '@salesforce/apex';
import getPendingApprovalReports   from '@salesforce/apex/ManagerExpenseController.getPendingApprovalReports';

const STATUS_CLASSES = {
    'Draft'    : 'rc-status badge-draft',
    'Submitted': 'rc-status badge-submitted',
    'Approved' : 'rc-status badge-approved',
    'Rejected' : 'rc-status badge-rejected',
    'Paid'     : 'rc-status badge-paid'
};

export default class ManagerExpenseQueue extends LightningElement {

    @track selectedReportId = null;
    @track isLoading        = true;
    @track hasError         = false;
    @track errorMessage     = '';
    @track rawReports       = [];

    // ── Filter state ────────────────────────────────────
    @track filterRepId     = '';
    @track filterDate      = '';
    @track repSearchText   = '';
    @track showRepDropdown = false;

    _wiredResult;

    @wire(getPendingApprovalReports)
    wiredReports(result) {
        this._wiredResult = result;
        this.isLoading    = false;
        if (result.data) {
            this.rawReports   = result.data;
            this.hasError     = false;
            this.errorMessage = '';
        } else if (result.error) {
            this.hasError     = true;
            this.errorMessage = result.error?.body?.message || 'Failed to load approval queue.';
        }
    }

    // ── Computed: enriched report list ──────────────────
    get reports() {
        return this.rawReports.map(r => ({
            ...r,
            formattedAmount: new Intl.NumberFormat('en-IN', {
                style: 'currency', currency: 'INR', maximumFractionDigits: 2
            }).format(r.totalAmount || 0),
            formattedDate: r.reportDate
                ? new Date(r.reportDate + 'T00:00:00').toLocaleDateString('en-IN', {
                    weekday: 'short', day: '2-digit', month: 'short', year: 'numeric'
                  })
                : '—',
            statusClass: STATUS_CLASSES[r.status] || 'rc-status badge-draft',
            hasBreach  : (r.breachCount || 0) > 0,
            breachLabel: (r.breachCount || 0) === 1
                ? '1 policy flag'
                : (r.breachCount || 0) + ' policy flags'
        }));
    }

    // ── Computed: unique rep options from loaded data ───
    get repOptions() {
        const seen = new Set();
        return this.rawReports
            .filter(r => {
                if (!r.salesRepId || seen.has(r.salesRepId)) return false;
                seen.add(r.salesRepId);
                return true;
            })
            .map(r => ({ id: r.salesRepId, name: r.salesRepName || r.salesRepId }))
            .sort((a, b) => a.name.localeCompare(b.name));
    }

    // Rep dropdown options filtered by what user typed
    get filteredRepOptions() {
        const q = this.repSearchText.toLowerCase();
        return this.repOptions.filter(r => r.name.toLowerCase().includes(q));
    }

    // ── Computed: filtered report list ──────────────────
    get filteredReports() {
        return this.reports.filter(r => {
            if (this.filterRepId && r.salesRepId !== this.filterRepId) return false;
            if (this.filterDate  && r.reportDate  !== this.filterDate)  return false;
            return true;
        });
    }

    get isFiltered()      { return !!this.filterRepId || !!this.filterDate; }
    get isFilteredEmpty() { return !this.isLoading && !this.hasError && this.rawReports.length > 0 && this.filteredReports.length === 0; }

    // ── Chips inside the smart bar ──────────────────────
    get activeChips() {
        const chips = [];
        if (this.filterRepId) {
            const rep = this.repOptions.find(r => r.id === this.filterRepId);
            chips.push({ key: 'rep', icon: 'utility:person_account', label: rep ? rep.name : this.filterRepId });
        }
        if (this.filterDate) {
            const d = new Date(this.filterDate + 'T00:00:00').toLocaleDateString('en-IN', {
                day: '2-digit', month: 'short', year: 'numeric'
            });
            chips.push({ key: 'date', icon: 'utility:event', label: d });
        }
        return chips;
    }

    get hasChips() { return this.activeChips.length > 0; }

    // Hide rep input once a rep is locked in
    get showRepSearch()  { return !this.filterRepId; }
    // Hide date picker once a date is locked in
    get showDatePicker() { return !this.filterDate; }

    // Smart bar placeholder — changes based on what's already filtered
    get searchPlaceholder() {
        if (!this.filterRepId && !this.filterDate) return 'Filter by rep or date…';
        if (this.filterRepId && !this.filterDate)  return 'Add date filter…';
        if (!this.filterRepId && this.filterDate)  return 'Add rep filter…';
        return 'Filters applied';
    }

    // Whether to show the rep dropdown suggestion list
    get showSuggestions() {
        return this.showRepDropdown && !this.filterRepId && this.filteredRepOptions.length > 0;
    }

    // Result count label shown at right end of bar
    get resultCountLabel() {
        if (!this.isFiltered) return this.rawReports.length + ' report(s)';
        return this.filteredReports.length + ' of ' + this.rawReports.length;
    }

    // ── Summary stats (full set) ─────────────────────────
    get totalPending()  { return this.rawReports.length; }
    get totalExpenses() { return this.rawReports.reduce((s, r) => s + (r.expenseCount  || 0), 0); }
    get totalSubmitted(){ return this.rawReports.reduce((s, r) => s + (r.submittedCount|| 0), 0); }
    get formattedTotalAmount() {
        return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 })
            .format(this.rawReports.reduce((s, r) => s + (r.totalAmount || 0), 0));
    }

    // ── Filtered stats ───────────────────────────────────
    get filteredPending()  { return this.filteredReports.length; }
    get filteredExpenses() { return this.filteredReports.reduce((s, r) => s + (r.expenseCount   || 0), 0); }
    get filteredSubmitted(){ return this.filteredReports.reduce((s, r) => s + (r.submittedCount || 0), 0); }
    get formattedFilteredAmount() {
        return new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 2 })
            .format(this.filteredReports.reduce((s, r) => s + (r.totalAmount || 0), 0));
    }

    // Card class — adds glow border when any filter is active
    get statCardClass() {
        return 'stat-card' + (this.isFiltered ? ' stat-card--filtered' : '');
    }

    // "of N total" sub-lines
    get totalPendingLabel()   { return 'of ' + this.totalPending   + ' total'; }
    get totalExpensesLabel()  { return 'of ' + this.totalExpenses  + ' total'; }
    get totalSubmittedLabel() { return 'of ' + this.totalSubmitted + ' total'; }
    get totalAmountLabel()    { return 'of ' + this.formattedTotalAmount + ' total'; }

    get isEmpty() { return !this.isLoading && !this.hasError && this.rawReports.length === 0; }

    // ── Smart filter bar handlers ────────────────────────

    // Text input in the bar — drives rep dropdown suggestions
    handleSearchInput(event) {
        this.repSearchText   = event.target.value;
        this.showRepDropdown = true;
    }

    handleSearchFocus() {
        if (!this.filterRepId) this.showRepDropdown = true;
    }

    handleSearchBlur() {
        // Delay so click on suggestion registers first
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showRepDropdown = false; }, 180);
    }

    handleRepSelect(event) {
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this.filterRepId     = id;
        this.repSearchText   = '';
        this.showRepDropdown = false;
        // Clear the text input
        const inp = this.template.querySelector('.sb-input');
        if (inp) inp.value = '';
    }

    handleDateChange(event) {
        this.filterDate = event.target.value;
    }

    handleRemoveChip(event) {
        const key = event.currentTarget.dataset.key;
        if (key === 'rep')  { this.filterRepId = ''; this.repSearchText = ''; }
        if (key === 'date') { this.filterDate = ''; }
    }

    handleClearAll() {
        this.filterRepId   = '';
        this.filterDate    = '';
        this.repSearchText = '';
        const inp = this.template.querySelector('.sb-input');
        if (inp) inp.value = '';
        const datePicker = this.template.querySelector('.sb-date');
        if (datePicker) datePicker.value = '';
    }

    // ── Navigation handlers ──────────────────────────────
    handleReportClick(event) {
        this.selectedReportId = event.currentTarget.dataset.id;
    }

    handleBack() {
        this.selectedReportId = null;
    }

    handleReportProcessed() {
        this.selectedReportId = null;
        this.isLoading = true;
        refreshApex(this._wiredResult);
    }

    handleRefresh() {
        this.isLoading = true;
        refreshApex(this._wiredResult);
    }
}