import { LightningElement, api } from 'lwc';

export default class RFieldOperationsPanel extends LightningElement {
    @api visits = [];
    @api activeTab = 'upcoming';
    @api dayStarted;
    @api dayEnded;
    @api isToday;
    @api hasBeatSelected;
    @api stayOnFieldNoBeat;

    get upcomingTabClass() {
        return `task-tab${this.activeTab === 'upcoming' ? ' active' : ''}`;
    }

    get ongoingTabClass() {
        return `task-tab${this.activeTab === 'ongoing' ? ' active' : ''}`;
    }

    get completedTabClass() {
        return `task-tab${this.activeTab === 'completed' ? ' active' : ''}`;
    }

    get filteredVisits() {
        // Keep tab filtering local so parent stays focused on data loading/state.
        const items = this.visits || [];
        if (this.activeTab === 'ongoing') {
            return items.filter((visit) => this.normalizeStatus(this.getVisitStatus(visit)) === 'in progress');
        }
        if (this.activeTab === 'completed') {
            return items.filter((visit) => this.normalizeStatus(this.getVisitStatus(visit)) === 'completed');
        }
        return items.filter((visit) => {
            const status = this.normalizeStatus(this.getVisitStatus(visit));
            return status !== 'in progress' && status !== 'completed';
        });
    }

    get emptyVisitTitle() {
        if (!this.hasBeatSelected || this.stayOnFieldNoBeat || this.visits.length === 0) {
            return 'Select another beat';
        }
        return 'No visits found';
    }

    get emptyVisitSubtitle() {
        if (!this.hasBeatSelected || this.stayOnFieldNoBeat || this.visits.length === 0) {
            return 'No visits are available for this date. Please select another beat.';
        }
        return 'Select another tab or date to view visits.';
    }

    handleTabClick(event) {
        const tab = event?.currentTarget?.dataset?.tab;
        if (!tab || tab === this.activeTab) {
            return;
        }

        this.dispatchEvent(
            new CustomEvent('visittabchange', {
                detail: { tab }
            })
        );
    }

    handleTileRefresh() {
        this.dispatchEvent(new CustomEvent('refresh'));
    }

    getVisitStatus(visit) {
        return visit?.ibfsa__Visit_Status__c || visit?.Visit_Status__c || '';
    }

    normalizeStatus(value) {
        return (value || '')
            .toString()
            .trim()
            .toLowerCase()
            .replace(/[_-]+/g, ' ')
            .replace(/\s+/g, ' ');
    }
}