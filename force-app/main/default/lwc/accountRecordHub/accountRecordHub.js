import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import ACCOUNT_OBJECT from '@salesforce/schema/Account';
import getAccountsByType from '@salesforce/apex/AccountRecordHubController.getAccountsByType';
import getAccountRecordTypeIds from '@salesforce/apex/AccountRecordHubController.getAccountRecordTypeIds';

const DEALER_DISTRIBUTOR = 'Dealer_Distributor';
const FRANCHISE = 'Franchise';

export default class AccountRecordHub extends NavigationMixin(LightningElement) {
    @track records = [];
    @track isLoading = false;
    @track errorMessage = '';
    @track selectedType = DEALER_DISTRIBUTOR;
    @track searchText = '';
    @track sortBy = 'NAME';
    @track sortDirection = 'ASC';
    @track currentPage = 1;
    recordTypeIdByDeveloperName = {};
    searchDebounce;
    refreshToken = 0;
    pageSize = 8;

    @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
    accountObjectInfo;

    connectedCallback() {
        this.loadAccountRecordTypeIds();
        this.hydrateFromCache();
        this.loadAccounts();
    }

    get dealerTabClass() {
        return `hub-tab${this.selectedType === DEALER_DISTRIBUTOR ? ' active' : ''}`;
    }

    get franchiseTabClass() {
        return `hub-tab${this.selectedType === FRANCHISE ? ' active' : ''}`;
    }

    get panelTitle() {
        return this.selectedType === DEALER_DISTRIBUTOR
            ? 'Dealer/Distributor Accounts'
            : 'Franchise Accounts';
    }

    get hasRecords() {
        return this.records && this.records.length > 0;
    }

    get sortOptions() {
        return [
            { label: 'Name', value: 'NAME' },
            { label: 'Last Modified', value: 'LAST_MODIFIED' }
        ];
    }

    get sortDirectionLabel() {
        return this.sortDirection === 'ASC' ? 'Asc' : 'Desc';
    }

    get sortedRecords() {
        const rows = [...(this.records || [])];
        if (!rows.length) {
            return rows;
        }

        rows.sort((a, b) => {
            let left;
            let right;

            if (this.sortBy === 'LAST_MODIFIED') {
                left = a.lastModifiedEpoch || 0;
                right = b.lastModifiedEpoch || 0;
            } else {
                left = (a.accountName || '').toLowerCase();
                right = (b.accountName || '').toLowerCase();
            }

            if (left === right) {
                return 0;
            }

            const base = left > right ? 1 : -1;
            return this.sortDirection === 'ASC' ? base : -base;
        });

        return rows;
    }

    get totalPages() {
        const totalRows = this.sortedRecords.length;
        return totalRows ? Math.ceil(totalRows / this.pageSize) : 1;
    }

    get visibleRecords() {
        const rows = this.sortedRecords;
        const startIndex = (this.currentPage - 1) * this.pageSize;
        const endIndex = startIndex + this.pageSize;
        return rows.slice(startIndex, endIndex);
    }

    get pageInfo() {
        return `Page ${this.currentPage} of ${this.totalPages}`;
    }

    get disablePrev() {
        return this.currentPage <= 1;
    }

    get disableNext() {
        return this.currentPage >= this.totalPages;
    }

    get emptyMessage() {
        return this.searchText
            ? `No ${this.panelTitle.toLowerCase()} found for "${this.searchText}".`
            : `No ${this.panelTitle.toLowerCase()} available.`;
    }

    handleTabSelect(event) {
        const selected = event.currentTarget.dataset.type;
        if (selected === this.selectedType) {
            return;
        }
        this.selectedType = selected;
        this.currentPage = 1;
        this.hydrateFromCache();
        this.loadAccounts();
    }

    handleSearchChange(event) {
        this.searchText = event.target.value || '';
        window.clearTimeout(this.searchDebounce);
        this.searchDebounce = window.setTimeout(() => {
            this.currentPage = 1;
            this.hydrateFromCache();
            this.loadAccounts();
        }, 300);
    }

    handleSortChange(event) {
        this.sortBy = event.detail.value;
        this.currentPage = 1;
    }

    handleToggleSortDirection() {
        this.sortDirection = this.sortDirection === 'ASC' ? 'DESC' : 'ASC';
        this.currentPage = 1;
    }

    handlePrevPage() {
        if (this.currentPage > 1) {
            this.currentPage -= 1;
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage += 1;
        }
    }

    handleRefresh() {
        this.refreshToken = Date.now();
        this.currentPage = 1;
        this.clearCacheForCurrentView();
        this.loadAccounts();
    }

    handleCreateDealerDistributor() {
        this.navigateToNewAccount(DEALER_DISTRIBUTOR);
    }

    handleCreateFranchise() {
        this.navigateToNewAccount(FRANCHISE);
    }

    handleOpenAccount(event) {
        const accountId = event.currentTarget.dataset.id;
        if (!accountId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: accountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    async navigateToNewAccount(recordTypeDeveloperName) {
        if (!this.recordTypeIdByDeveloperName || !this.recordTypeIdByDeveloperName[recordTypeDeveloperName]) {
            await this.loadAccountRecordTypeIds();
        }

        const recordTypeId = this.getRecordTypeIdByDeveloperName(recordTypeDeveloperName);
        if (!recordTypeId) {
            this.showToast('Error', `Record type ${recordTypeDeveloperName} not found for Account.`, 'error');
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: `/lightning/o/Account/new?nooverride=1&useRecordTypeCheck=1&recordTypeId=${recordTypeId}`
            }
        });
    }

    getRecordTypeIdByDeveloperName(developerName) {
        if (this.recordTypeIdByDeveloperName && this.recordTypeIdByDeveloperName[developerName]) {
            return this.recordTypeIdByDeveloperName[developerName];
        }

        const recordTypeInfos = this.accountObjectInfo?.data?.recordTypeInfos || {};
        return Object.keys(recordTypeInfos).find((recordTypeId) => {
            const rtInfo = recordTypeInfos[recordTypeId];
            return rtInfo?.developerName === developerName;
        });
    }

    async loadAccountRecordTypeIds() {
        try {
            const response = await getAccountRecordTypeIds();
            this.recordTypeIdByDeveloperName = response || {};
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Record type ID load error', error);
            this.recordTypeIdByDeveloperName = {};
        }
    }

    async loadAccounts() {
        const hasVisibleRows = Array.isArray(this.records) && this.records.length > 0;
        this.isLoading = !hasVisibleRows;
        this.errorMessage = '';
        try {
            const response = await getAccountsByType({
                recordTypeDeveloperName: this.selectedType,
                searchText: this.searchText,
                maxRows: 200,
                refreshToken: this.refreshToken
            });

            const normalizedRows = (response || []).map((row) => ({
                ...row,
                avatarLetter: row.accountName ? row.accountName.charAt(0).toUpperCase() : 'A',
                lastModifiedEpoch: row.lastModifiedDate ? new Date(row.lastModifiedDate).getTime() : 0,
                locationText: [row.city, row.state].filter(Boolean).join(', ') || 'Location not available',
                phoneText: row.phone || 'Phone not available',
                ownerLabel: row.recordTypeDeveloperName === FRANCHISE ? 'Outlet Owner Name' : 'Owner',
                ownerText: row.recordTypeDeveloperName === FRANCHISE
                    ? (row.outletOwnerName || 'Outlet owner not available')
                    : (row.ownerName || 'Owner not assigned'),
                recordTypeText: row.recordTypeLabel || '-',
                outletStatusText: row.outletStatus || '-',
                showOutletFields: row.recordTypeDeveloperName !== DEALER_DISTRIBUTOR
            }));
            this.records = normalizedRows;
            this.currentPage = 1;
            this.writeCache(normalizedRows);
        } catch (error) {
            this.records = [];
            this.errorMessage = 'Unable to load accounts right now.';
            // eslint-disable-next-line no-console
            console.error('Account load error', error);
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    getCacheKey() {
        const safeSearch = (this.searchText || '').trim().toLowerCase();
        return `accountRecordHub:${this.selectedType}:${safeSearch}`;
    }

    hydrateFromCache() {
        try {
            const raw = window.sessionStorage.getItem(this.getCacheKey());
            if (!raw) {
                return;
            }
            const cached = JSON.parse(raw);
            if (Array.isArray(cached) && cached.length) {
                this.records = cached;
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Account hub cache read failed', e);
        }
    }

    writeCache(rows) {
        try {
            window.sessionStorage.setItem(this.getCacheKey(), JSON.stringify(rows || []));
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Account hub cache write failed', e);
        }
    }

    clearCacheForCurrentView() {
        try {
            window.sessionStorage.removeItem(this.getCacheKey());
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('Account hub cache clear failed', e);
        }
    }
}