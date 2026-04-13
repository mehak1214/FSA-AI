import { LightningElement, track, wire } from 'lwc';
import { refreshApex }           from '@salesforce/apex';
import getPendingApprovalReports from '@salesforce/apex/ManagerExpenseController.getPendingApprovalReports';

const STATUS_CLASSES = {
    'Draft'    : 'status-badge badge-draft',
    'Submitted': 'status-badge badge-submitted',
    'Approved' : 'status-badge badge-approved',
    'Rejected' : 'status-badge badge-rejected',
    'Paid'     : 'status-badge badge-paid'
};

export default class ManagerExpenseQueue extends LightningElement {

    @track selectedReportId = null;
    @track isLoading        = true;
    @track hasError         = false;
    @track errorMessage     = '';
    @track rawReports       = [];

    // Filter state
    @track filterRepId     = '';
    @track filterDate      = '';
    @track repSearchText   = '';
    @track showRepDropdown = false;

    // Group collapse state — Set of repIds that are currently expanded
    @track expandedGroups = new Set();

    // Toast
    @track showToast    = false;
    @track toastMessage = '';
    @track toastType    = 'success';

    _wiredResult;

    @wire(getPendingApprovalReports)
    wiredReports(result) {
        this._wiredResult = result;
        this.isLoading    = false;
        if (result.data) {
            this.rawReports   = result.data;
            this.hasError     = false;
            this.errorMessage = '';
            this._firePendingCount(result.data.length);

            // Seed expandedGroups: auto-expand all groups when fewer than 3 reps,
            // but only on the initial load (i.e. when expandedGroups is still empty).
            // This ensures the toggle handler remains the sole authority afterwards.
            if (this.expandedGroups.size === 0) {
                const repIds = [...new Set(result.data.map(r => r.salesRepId).filter(Boolean))];
                if (repIds.length < 3) {
                    this.expandedGroups = new Set(repIds);
                }
            }
        } else if (result.error) {
            this.hasError     = true;
            this.errorMessage = result.error?.body?.message || 'Failed to load approval queue.';
        }
    }

    // ── Fire badge count event ──────────────────────────
    _firePendingCount(count) {
        this.dispatchEvent(new CustomEvent('pendingcountchange', {
            detail  : { count },
            bubbles : true,
            composed: true
        }));
    }

    // ── Enriched report list ────────────────────────────
    get reports() {
        return this.rawReports.map(r => {
            // Avatar: initials from sales rep name
            const name   = r.salesRepName || '';
            const parts  = name.trim().split(' ').filter(Boolean);
            const letter = parts.length >= 2
                ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
                : name.substring(0, 2).toUpperCase() || '💰';

            return {
                ...r,
                avatarLetter: letter,
                formattedAmount: new Intl.NumberFormat('en-IN', {
                    style: 'currency', currency: 'INR', maximumFractionDigits: 2
                }).format(r.totalAmount || 0),
                formattedDate: r.reportDate
                    ? new Date(r.reportDate + 'T00:00:00').toLocaleDateString('en-IN', {
                        weekday: 'short', day: '2-digit', month: 'short', year: 'numeric'
                      })
                    : '—',
                statusClass: STATUS_CLASSES[r.status] || 'status-badge badge-draft',
                hasBreach  : (r.breachCount || 0) > 0,
                breachLabel: (r.breachCount || 0) === 1
                    ? '1 policy flag'
                    : (r.breachCount || 0) + ' policy flags'
            };
        });
    }

    // ── Rep options ─────────────────────────────────────
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

    get filteredRepOptions() {
        const q = this.repSearchText.toLowerCase();
        return this.repOptions.filter(r => r.name.toLowerCase().includes(q));
    }

    // ── Filtered reports ────────────────────────────────
    get filteredReports() {
        return this.reports.filter(r => {
            if (this.filterRepId && r.salesRepId !== this.filterRepId) return false;
            if (this.filterDate  && r.reportDate  !== this.filterDate)  return false;
            return true;
        });
    }

    get isFiltered()      { return !!this.filterRepId || !!this.filterDate; }
    get isFilteredEmpty() {
        return !this.isLoading && !this.hasError &&
               this.rawReports.length > 0 && this.filteredReports.length === 0;
    }

    // ── Grouped reports (by sales rep, sorted A-Z) ──────
    get groupedReports() {
        // Build a map: repId → { repId, repName, avatarLetter, reports[], totalAmount, totalPending }
        const map = new Map();
        for (const r of this.filteredReports) {
            const key = r.salesRepId || '__unknown__';
            if (!map.has(key)) {
                const name   = r.salesRepName || 'Unknown Rep';
                const parts  = name.trim().split(' ').filter(Boolean);
                const letter = parts.length >= 2
                    ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
                    : name.substring(0, 2).toUpperCase() || '?';
                map.set(key, {
                    groupKey      : key,
                    repId         : key,
                    repName       : name,
                    avatarLetter  : letter,
                    reports       : [],
                    totalAmount   : 0,
                    totalPending  : 0,
                    reportCount   : 0
                });
            }
            const g = map.get(key);
            g.reports.push(r);
            g.totalAmount  += r.totalAmount   || 0;
            g.totalPending += r.submittedCount || 0;
            g.reportCount  += 1;
        }

        // Sort groups A-Z by rep name, format group-level totals
        const sorted = Array.from(map.values())
            .sort((a, b) => a.repName.localeCompare(b.repName));

        return sorted.map(g => {
            const expanded = this.expandedGroups.has(g.repId);
            return {
                ...g,
                formattedTotal: new Intl.NumberFormat('en-IN', {
                    style: 'currency', currency: 'INR', maximumFractionDigits: 0
                }).format(g.totalAmount),
                reportLabel  : g.reportCount === 1 ? '1 report' : g.reportCount + ' reports',
                isExpanded   : expanded,
                chevron      : expanded ? '▲' : '▼',
                headerClass  : 'rep-group-header' + (expanded ? ' rep-group-header--open' : '')
            };
        });
    }

    // ── Smart bar chips ─────────────────────────────────
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

    get showRepSearch()  { return !this.filterRepId; }
    get showDatePicker() { return !this.filterDate; }

    get searchPlaceholder() {
        if (!this.filterRepId && !this.filterDate) return 'Filter by rep or date…';
        if (this.filterRepId  && !this.filterDate) return 'Add date filter…';
        if (!this.filterRepId &&  this.filterDate) return 'Add rep filter…';
        return 'Filters applied';
    }

    get showSuggestions() {
        return this.showRepDropdown && !this.filterRepId && this.filteredRepOptions.length > 0;
    }

    get resultCountLabel() {
        if (!this.isFiltered) return this.rawReports.length + ' report(s)';
        return this.filteredReports.length + ' of ' + this.rawReports.length;
    }

    // ── Summary stats ───────────────────────────────────
    get totalPending()  { return this.rawReports.length; }
    get totalExpenses() { return this.rawReports.reduce((s, r) => s + (r.expenseCount  || 0), 0); }
    get formattedTotalAmount() {
        const total = this.rawReports.reduce((s, r) => s + (r.totalAmount || 0), 0);
        // Compact format for the pill (e.g. ₹1.2L)
        if (total >= 100000) return '₹' + (total / 100000).toFixed(1) + 'L';
        if (total >= 1000)   return '₹' + (total / 1000).toFixed(1)   + 'K';
        return '₹' + total.toFixed(0);
    }

    get isEmpty() { return !this.isLoading && !this.hasError && this.rawReports.length === 0; }

    // ── Toast ───────────────────────────────────────────
    get toastClass() { return `toast-notification toast-${this.toastType}`; }

    _showToast(message, type = 'success') {
        this.toastMessage = message;
        this.toastType    = type;
        this.showToast    = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showToast = false; }, 3500);
    }

    // ── Filter handlers ─────────────────────────────────
    handleSearchInput(event) {
        this.repSearchText   = event.target.value;
        this.showRepDropdown = true;
    }

    handleSearchFocus() {
        if (!this.filterRepId) this.showRepDropdown = true;
    }

    handleSearchBlur() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => { this.showRepDropdown = false; }, 180);
    }

    handleRepSelect(event) {
        this.filterRepId     = event.currentTarget.dataset.id;
        this.repSearchText   = '';
        this.showRepDropdown = false;
        const inp = this.template.querySelector('.sb-input');
        if (inp) inp.value = '';
    }

    handleDateChange(event) {
        this.filterDate = event.target.value;
    }

    handleRemoveChip(event) {
        const key = event.currentTarget.dataset.key;
        if (key === 'rep')  { this.filterRepId = ''; this.repSearchText = ''; }
        if (key === 'date') { this.filterDate  = ''; }
    }

    handleClearAll() {
        this.filterRepId   = '';
        this.filterDate    = '';
        this.repSearchText = '';
        const inp  = this.template.querySelector('.sb-input');
        const date = this.template.querySelector('.sb-date');
        if (inp)  inp.value  = '';
        if (date) date.value = '';
    }

    // ── Group collapse toggle ──────────────────────────
    handleGroupToggle(event) {
        const repId = event.currentTarget.dataset.repid;
        const next  = new Set(this.expandedGroups);
        if (next.has(repId)) {
            next.delete(repId);
        } else {
            next.add(repId);
        }
        this.expandedGroups = next;
    }

    // ── Navigation ──────────────────────────────────────
    handleReportClick(event) {
        this.selectedReportId = event.currentTarget.dataset.id;
    }

    handleBack() {
        this.selectedReportId = null;
    }

    handleReportProcessed() {
        this.selectedReportId = null;
        this.isLoading        = true;
        this.expandedGroups   = new Set();
        refreshApex(this._wiredResult);
    }

    handleRefresh() {
        this.isLoading      = true;
        this.expandedGroups = new Set();
        refreshApex(this._wiredResult);
    }
}