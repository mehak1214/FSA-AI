import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getVisitsForManager from '@salesforce/apex/ManagerVisitApprovalView.getVisitsForManager';
import approveVisit from '@salesforce/apex/ManagerVisitApprovalView.approveVisit';
import rejectVisit from '@salesforce/apex/ManagerVisitApprovalView.rejectVisit';

export default class ManagerVisitView extends NavigationMixin(LightningElement) {

    @track activeTab = 'pending';
    @track isLoading = false;
    @track hasError = false;
    @track errorMessage = '';
    @track showToast = false;
    @track toastMessage = '';
    @track toastType = 'success';
    @track showRejectModal = false;
    @track rejectComment = '';
    @track rejectVisitId = null;

    wiredVisitsResult;
    _allVisits = [];

    connectedCallback() {
        this.isLoading = true;
    }

    @wire(getVisitsForManager)
    wiredVisits(result) {
        this.wiredVisitsResult = result;
        if (result.data) {
            this._allVisits = result.data.map((visit) => this._formatVisit(visit));
            this.hasError = false;
            this.errorMessage = '';
            this.isLoading = false;
        } else if (result.error) {
            this.hasError = true;
            this.errorMessage = result.error.body?.message || 'Failed to load visits.';
            this.isLoading = false;
        }
    }

    _formatVisit(visit) {
        const repRef = this._getField(visit, 'Sales_Rep__r');
        const repName = repRef?.Name || this._getField(visit, 'Sales_Rep__c') || '';
        const parts = repName.trim().split(' ');
        const initials = parts.length >= 2
            ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
            : repName.substring(0, 2).toUpperCase() || '??';

        const visitDate = this._getField(visit, 'Visit_Date__c');
        const formattedDate = visitDate
            ? new Date(visitDate).toLocaleDateString('en-US', {
                weekday: 'short', year: 'numeric', month: 'short', day: 'numeric'
              })
            : '--';

        const formattedStartTime = this._formatTime(this._getField(visit, 'Planned_Start_Time__c'));
        const formattedEndTime = this._formatTime(this._getField(visit, 'Planned_End_Time__c'));

        return {
            ...visit,
            salesRepName: repName || 'Unknown Rep',
            initials,
            formattedDate,
            formattedStartTime,
            formattedEndTime
        };
    }

    _formatTime(datetimeValue) {
        if (!datetimeValue) return '--';
        return new Date(datetimeValue).toLocaleTimeString('en-US', {
            hour: '2-digit', minute: '2-digit', hour12: true
        });
    }

    get pendingVisits() {
        return this._allVisits.filter((visit) => {
            const approvalStatus = this._normalizeStatus(this._getField(visit, 'Approval_Status__c'));
            const visitStatus = this._normalizeStatus(this._getField(visit, 'Visit_Status__c'));
            return approvalStatus === 'Submitted' || (!approvalStatus && visitStatus === 'Submitted');
        });
    }

    get approvedVisits() {
        return this._allVisits.filter((visit) => {
            const approvalStatus = this._normalizeStatus(this._getField(visit, 'Approval_Status__c'));
            const visitStatus = this._normalizeStatus(this._getField(visit, 'Visit_Status__c'));
            return approvalStatus === 'Approved' || (!approvalStatus && visitStatus === 'Approved');
        });
    }

    get rejectedVisits() {
        return this._allVisits.filter(
            (visit) => this._normalizeStatus(this._getField(visit, 'Approval_Status__c')) === 'Rejected'
        );
    }

    get pendingCount()      { return this.pendingVisits.length; }
    get approvedCount()     { return this.approvedVisits.length; }
    get rejectedCount()     { return this.rejectedVisits.length; }
    get hasPendingVisits()  { return this.pendingVisits.length > 0; }
    get hasApprovedVisits() { return this.approvedVisits.length > 0; }
    get hasRejectedVisits() { return this.rejectedVisits.length > 0; }
    get showPendingTab()    { return this.activeTab === 'pending'; }
    get showApprovedTab()   { return this.activeTab === 'approved'; }
    get showRejectedTab()   { return this.activeTab === 'rejected'; }

    get pendingTabClass() {
        return this.activeTab === 'pending' ? 'tab-btn tab-active' : 'tab-btn';
    }

    get approvedTabClass() {
        return this.activeTab === 'approved' ? 'tab-btn tab-active' : 'tab-btn';
    }

    get rejectedTabClass() {
        return this.activeTab === 'rejected' ? 'tab-btn tab-active' : 'tab-btn';
    }

    get toastClass() {
        return `toast-notification toast-${this.toastType}`;
    }

    showPending() { this.activeTab = 'pending'; }
    showApproved() { this.activeTab = 'approved'; }
    showRejected() { this.activeTab = 'rejected'; }

    async handleApprove(event) {
        event.stopPropagation();
        const visitId = event.currentTarget.dataset.id;
        if (!visitId) return;

        this.isLoading = true;
        try {
            await approveVisit({ visitId });
            this._showToast('Visit approved successfully.', 'success');
            await refreshApex(this.wiredVisitsResult);
        } catch (error) {
            this._showToast(error?.body?.message || 'Failed to approve visit.', 'error');
            this.isLoading = false;
        }
    }

    async handleReject(event) {
        event.stopPropagation();
        const visitId = event.currentTarget.dataset.id;
        if (!visitId) return;
        this.rejectVisitId = visitId;
        this.rejectComment = '';
        this.showRejectModal = true;
    }

    handleRejectCommentChange(event) {
        this.rejectComment = event.target.value || '';
    }

    closeRejectModal() {
        this.showRejectModal = false;
        this.rejectComment = '';
        this.rejectVisitId = null;
    }

    async confirmReject() {
        if (!this.rejectVisitId) return;
        if (!this.rejectComment || !this.rejectComment.trim()) {
            this._showToast('Rejection comment is mandatory.', 'error');
            return;
        }

        this.isLoading = true;
        try {
            await rejectVisit({ visitId: this.rejectVisitId, comments: this.rejectComment });
            this._showToast('Visit rejected successfully.', 'success');
            this.closeRejectModal();
            await refreshApex(this.wiredVisitsResult);
        } catch (error) {
            this._showToast(error?.body?.message || 'Failed to reject visit.', 'error');
            this.isLoading = false;
        }
    }

    navigateToRecord(event) {
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                actionName: 'view'
            }
        });
    }

    _showToast(message, type = 'success') {
        this.toastMessage = message;
        this.toastType = type;
        this.showToast = true;
        setTimeout(() => { this.showToast = false; }, 3000);
    }

    _normalizeStatus(value) {
        return (value || '')
            .toString()
            .trim()
            .replace(/_/g, ' ');
    }

    _getField(record, apiName) {
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
}