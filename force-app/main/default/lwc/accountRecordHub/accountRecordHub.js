import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import ACCOUNT_OBJECT from '@salesforce/schema/Account';
import getAccountsByType from '@salesforce/apex/AccountRecordHubController.getAccountsByType';
import getAccountRecordTypeIds from '@salesforce/apex/AccountRecordHubController.getAccountRecordTypeIds';
import getAccountForEdit from '@salesforce/apex/NewRetailAccountController.getAccountForEdit';
import transitionStatus from '@salesforce/apex/AccountStatusService.transitionStatus';
import submitForApproval from '@salesforce/apex/AccountStatusService.submitForApproval';

const DEALER_DISTRIBUTOR = 'Dealer_Distributor';
const FRANCHISE          = 'Franchise';

const EDITABLE_STATUSES = new Set(['Draft']);
const NAVIGATE_STATUSES = new Set(['Active', 'Inactive', 'Abandoned', 'Submitted', 'Rejected', '']);

const ALL_STATUSES = ['Draft', 'Submitted', 'Active', 'Inactive', 'Rejected', 'Abandoned'];

const STATUS_ACCENT = {
    'Draft':     '#2f74c8',
    'Submitted': '#d4860a',
    'Active':    '#0e8a50',
    'Inactive':  '#7a8a9a',
    'Rejected':  '#c0392b',
    'Abandoned': '#6b4fad',
    '':          '#2f74c8'
};

export default class AccountRecordHub extends NavigationMixin(LightningElement) {
    @track records           = [];
    @track isLoading         = false;
    @track errorMessage      = '';
    @track selectedType      = DEALER_DISTRIBUTOR;
    @track searchText        = '';
    @track selectedStatus    = 'All';    // client-side status filter
    @track currentPage       = 1;
    @track modalAccountType  = '';
    @track modalRecordTypeId = '';
    @track modalEditData     = null;
    @track confirmAccountId  = null;  // set when awaiting submit-for-approval confirmation

    recordTypeIdByDeveloperName = {};
    searchDebounce;
    refreshToken = 0;
    pageSize     = 10;

    @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
    accountObjectInfo;

    connectedCallback() {
        this.loadAccountRecordTypeIds();
        this.hydrateFromCache();
        this.loadAccounts();
    }

    // ─── Getters ──────────────────────────────────────────────────────────────

    get dealerTabClass() {
        return `type-tab${this.selectedType === DEALER_DISTRIBUTOR ? ' active' : ''}`;
    }
    get retailerTabClass() {
        return `type-tab${this.selectedType === FRANCHISE ? ' active' : ''}`;
    }

    // Status filter pills — "All" + one per status, each with a live count
    get statusFilters() {
        const countMap = {};
        ALL_STATUSES.forEach(s => { countMap[s] = 0; });
        (this.records || []).forEach(r => {
            const s = r.outletStatusText || '';
            if (countMap[s] !== undefined) countMap[s]++;
        });
        const total = (this.records || []).length;

        const pills = [
            {
                label: 'All', value: 'All', count: total,
                cssClass: `status-pill${this.selectedStatus === 'All' ? ' active' : ''}`
            },
            ...ALL_STATUSES.map(s => ({
                label: s, value: s, count: countMap[s] || 0,
                cssClass: `status-pill status-pill-${s.toLowerCase()}${this.selectedStatus === s ? ' active' : ''}`
            }))
        ];
        return pills;
    }

    get filteredRecords() {
        let rows = this.records || [];
        if (this.searchText.trim()) {
            const q = this.searchText.trim().toLowerCase();
            rows = rows.filter(r =>
                (r.accountName || '').toLowerCase().includes(q) ||
                (r.phone       || '').toLowerCase().includes(q) ||
                (r.city        || '').toLowerCase().includes(q) ||
                (r.site        || '').toLowerCase().includes(q)
            );
        }
        if (this.selectedStatus !== 'All') {
            rows = rows.filter(r => r.outletStatusText === this.selectedStatus);
        }
        return rows;
    }

    get visibleRecords() {
        const start = (this.currentPage - 1) * this.pageSize;
        return this.filteredRecords.slice(start, start + this.pageSize);
    }

    get totalPages() {
        const n = this.filteredRecords.length;
        return n ? Math.ceil(n / this.pageSize) : 1;
    }

    get hasRecords()  { return this.visibleRecords.length > 0; }
    get pageInfo()    { return `Page ${this.currentPage} of ${this.totalPages}`; }
    get disablePrev() { return this.currentPage <= 1; }
    get disableNext() { return this.currentPage >= this.totalPages; }

    get recordsVisibleInfo() {
        const total  = this.filteredRecords.length;
        const start  = Math.min((this.currentPage - 1) * this.pageSize + 1, total);
        const end    = Math.min(this.currentPage * this.pageSize, total);
        if (total === 0) return '0 records';
        return `${start}–${end} of ${total}`;
    }

    get resultSummary() {
        const total    = (this.records || []).length;
        const filtered = this.filteredRecords.length;
        const typeName = this.selectedType === DEALER_DISTRIBUTOR ? 'Dealer/Distributor' : 'Retailer';
        if (this.selectedStatus === 'All' && !this.searchText.trim()) {
            return `${total} ${typeName} store${total !== 1 ? 's' : ''}`;
        }
        return `${filtered} of ${total} ${typeName} store${total !== 1 ? 's' : ''}`;
    }

    get showConfirmModal() { return !!this.confirmAccountId; }

    get emptyMessage() {
        if (this.searchText || this.selectedStatus !== 'All') {
            return 'No stores match the current filters.';
        }
        return this.selectedType === DEALER_DISTRIBUTOR
            ? 'No Dealer/Distributor stores yet.'
            : 'No Retailer stores yet.';
    }

    // ─── Tab / Search / Filter ────────────────────────────────────────────────

    handleTabSelect(event) {
        const selected = event.currentTarget.dataset.type;
        if (selected === this.selectedType) return;
        this.selectedType   = selected;
        this.selectedStatus = 'All';
        this.currentPage    = 1;
        this.hydrateFromCache();
        this.loadAccounts();
    }

    handleSearchChange(event) {
        this.searchText = event.target.value || '';
        this.currentPage = 1;
        window.clearTimeout(this.searchDebounce);
        this.searchDebounce = window.setTimeout(() => {
            this.currentPage = 1;
        }, 250);
    }

    handleStatusFilter(event) {
        this.selectedStatus = event.currentTarget.dataset.status;
        this.currentPage    = 1;
    }

    handlePrevPage() { if (this.currentPage > 1) this.currentPage -= 1; }
    handleNextPage() { if (this.currentPage < this.totalPages) this.currentPage += 1; }

    handleRefresh() {
        this.refreshToken = Date.now();
        this.currentPage  = 1;
        this.clearCacheForCurrentView();
        this.loadAccounts();
    }

    // ─── Create New ───────────────────────────────────────────────────────────

    handleCreateDealerDistributor() { this.openModal(DEALER_DISTRIBUTOR); }
    handleCreateRetailer()          { this.openModal(FRANCHISE); }

    async openModal(recordTypeDeveloperName, editData = null) {
        if (!this.recordTypeIdByDeveloperName?.[recordTypeDeveloperName]) {
            await this.loadAccountRecordTypeIds();
        }
        const recordTypeId     = this.getRecordTypeIdByDeveloperName(recordTypeDeveloperName);
        this.modalAccountType  = recordTypeDeveloperName;
        this.modalRecordTypeId = recordTypeId || '';
        this.modalEditData     = editData;

        const modal = this.template.querySelector('c-new-retail-account');
        if (modal) {
            if (editData) {
                modal.openForEdit(editData);
            } else {
                modal.open();
            }
        }
    }

    // ─── Card click — status-driven routing ──────────────────────────────────

    async handleOpenAccount(event) {
        const accountId = event.currentTarget.dataset.id;
        const status    = event.currentTarget.dataset.status;
        if (!accountId) return;

        if (EDITABLE_STATUSES.has(status)) {
            await this.openEditModal(accountId);
        } else if (NAVIGATE_STATUSES.has(status)) {
            this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: { componentName: 'c__outlet360Details' },
                state: { c__recordId: accountId, c__objectApiName: 'Account' }
            });
        }
    }

    async handleResubmit(event) {
        event.stopPropagation();
        const accountId = event.currentTarget.dataset.id;
        if (!accountId) return;
        await this.openEditModal(accountId);
    }

    async handleAbandon(event) {
        event.stopPropagation();
        const accountId = event.currentTarget.dataset.id;
        if (!accountId) return;
        try {
            await transitionStatus({ accountId, newStatus: 'Abandoned' });
            this.showToast('Abandoned', 'Account has been marked as Abandoned.', 'info');
            this.handleRefresh();
        } catch (e) {
            this.showToast('Error', e?.body?.message || 'Could not abandon account.', 'error');
        }
    }

    handleSubmitForApproval(event) {
        event.stopPropagation();
        const accountId = event.currentTarget.dataset.id;
        if (!accountId) return;
        // Show inline confirmation — actual call happens in handleConfirmSubmit
        this.confirmAccountId = accountId;
    }

    async handleConfirmSubmit() {
        const accountId = this.confirmAccountId;
        this.confirmAccountId = null;
        try {
            await submitForApproval({ accountId });
            this.showToast('Submitted', 'Account submitted for approval.', 'success');
            this.handleRefresh();
        } catch (e) {
            this.showToast('Error', e?.body?.message || 'Approval submission failed.', 'error');
        }
    }

    handleConfirmCancel() {
        this.confirmAccountId = null;
    }

    async openEditModal(accountId) {
        try {
            const editData = await getAccountForEdit({ accountId });
            await this.openModal(this.selectedType, editData);
        } catch (e) {
            this.showToast('Error', 'Could not load account for editing.', 'error');
        }
    }

    // ─── Modal events ─────────────────────────────────────────────────────────

    handleModalClose()    { /* no-op */ }
    handleAccountCreated() {
        this.modalEditData = null;
        this.handleRefresh();
    }

    // ─── Data loading ─────────────────────────────────────────────────────────

    getRecordTypeIdByDeveloperName(developerName) {
        if (this.recordTypeIdByDeveloperName?.[developerName]) {
            return this.recordTypeIdByDeveloperName[developerName];
        }
        const rtInfos = this.accountObjectInfo?.data?.recordTypeInfos || {};
        return Object.keys(rtInfos).find(id => rtInfos[id]?.developerName === developerName);
    }

    async loadAccountRecordTypeIds() {
        try {
            this.recordTypeIdByDeveloperName = await getAccountRecordTypeIds() || {};
        } catch (e) {
            this.recordTypeIdByDeveloperName = {};
        }
    }

    async loadAccounts() {
        const hasRows  = Array.isArray(this.records) && this.records.length > 0;
        this.isLoading = !hasRows;
        this.errorMessage = '';
        try {
            const response = await getAccountsByType({
                recordTypeDeveloperName: this.selectedType,
                searchText:   '',           // search is client-side now
                maxRows:      500,
                refreshToken: this.refreshToken
            });

            const rows = (response || []).map(row => {
                const status = row.outletStatus || '';
                return {
                    ...row,
                    avatarLetter:     row.accountName ? row.accountName[0].toUpperCase() : 'A',
                    locationText:     [row.city, row.state].filter(Boolean).join(', ') || 'Location not set',
                    phoneText:        row.phone || '—',
                    ownerLabel:       row.recordTypeDeveloperName === FRANCHISE ? 'Owner' : 'Owner',
                    ownerText:        row.recordTypeDeveloperName === FRANCHISE
                                          ? (row.outletOwnerName || '—')
                                          : (row.ownerName       || '—'),
                    recordTypeText:   row.recordTypeLabel || '-',
                    outletStatusText: status,
                    statusBadgeClass: this.statusBadgeClass(status),
                    accentColor:      STATUS_ACCENT[status] || STATUS_ACCENT[''],
                    accentStyle:      `background:${STATUS_ACCENT[status] || STATUS_ACCENT['']}`,
                    isRejected:       status === 'Rejected',
                    isDraft:          status === 'Draft',
                    isClickable:      EDITABLE_STATUSES.has(status) || NAVIGATE_STATUSES.has(status),
                    cardClass:        'record-card' + (EDITABLE_STATUSES.has(status) || NAVIGATE_STATUSES.has(status) ? ' clickable' : ' readonly'),
                    rejectionReason:  row.rejectionReason || ''
                };
            });

            this.records     = rows;
            this.currentPage = 1;
            this.writeCache(rows);
        } catch (e) {
            this.records      = [];
            this.errorMessage = 'Unable to load stores right now.';
        } finally {
            this.isLoading = false;
        }
    }

    statusBadgeClass(status) {
        const map = {
            'Draft':     'badge badge-draft',
            'Submitted': 'badge badge-submitted',
            'Active':    'badge badge-active',
            'Inactive':  'badge badge-inactive',
            'Rejected':  'badge badge-rejected',
            'Abandoned': 'badge badge-abandoned',
            '':          'badge badge-draft'
        };
        return map[status] || 'badge badge-draft';
    }

    // ─── Toast ────────────────────────────────────────────────────────────────

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // ─── Session cache ────────────────────────────────────────────────────────

    getCacheKey() {
        return `accountRecordHub:${this.selectedType}`;
    }
    hydrateFromCache() {
        try {
            const raw = window.sessionStorage.getItem(this.getCacheKey());
            if (!raw) return;
            const cached = JSON.parse(raw);
            if (Array.isArray(cached) && cached.length) this.records = cached;
        } catch (e) { /* silent */ }
    }
    writeCache(rows) {
        try {
            window.sessionStorage.setItem(this.getCacheKey(), JSON.stringify(rows || []));
        } catch (e) { /* silent */ }
    }
    clearCacheForCurrentView() {
        try {
            window.sessionStorage.removeItem(this.getCacheKey());
        } catch (e) { /* silent */ }
    }
}