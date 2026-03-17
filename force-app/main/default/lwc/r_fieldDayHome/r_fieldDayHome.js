import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';
import { getRecord } from 'lightning/uiRecordApi';

import getTodayAttendance from '@salesforce/apex/VisitController.getTodayAttendance';
import getTodayBeats from '@salesforce/apex/VisitController.getTodayBeats';
import getVisitsByBeat from '@salesforce/apex/VisitController.getVisitsByBeat';
import getDayTimeline from '@salesforce/apex/VisitController.getDayTimeline';
import startDay from '@salesforce/apex/VisitController.startDay';
import endDay from '@salesforce/apex/VisitController.endDay';
import getDashboardSnapshot from '@salesforce/apex/VisitController.getDashboardSnapshot';

const USER_FIELDS = ['User.Name'];
const DATE_WINDOW_SIZE = 5;
const DEFAULT_DATE_WINDOW_OFFSET = -2;
const formatDateValue = (date) => {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
};

export default class r_fieldDayHome extends NavigationMixin(LightningElement) {

    /* =====================
       STATE
    ====================== */
    @track userName;
    @track visits = [];
    @track beats = [];

    @track selectedBeatId = null;
    @track selectedBeatName = null;
    @track showBeatDropdown = false;

    selectedDate = formatDateValue(new Date());

    viewMode = null; // null | 'BEAT' | 'DAY'
    dayStarted = false;
    dayEnded = false;
    isToday = true;
    summaryPulse = false;
    _summaryPulseTimeout;
    _lastSummary = { completed: 0, inProgress: 0, pending: 0 };
    dateWindowOffset = DEFAULT_DATE_WINDOW_OFFSET;
    dateWindowSize = DATE_WINDOW_SIZE;
    timelineOpen = false;
    timelineVisits = [];
    timelineLoading = false;

    showSchemesModal = false;
    showNewProductsModal = false;
    showBeatPlanWeeklyModal = false;

    dashboardSnapshot = {};
    activeVisitTab = 'upcoming';
    dailyVisits = [];
    activeMainScreen = 'dashboard'; // dashboard | field
    stayOnFieldNoBeat = false;
    activeProductSchemeTab = 'products'; // products | schemes

    /* =====================
       USER
    ====================== */
    @wire(getRecord, { recordId: USER_ID, fields: USER_FIELDS })
    wiredUser({ data }) {
        if (data) {
            this.userName = data.fields.Name.value;
        }
    }

    /* =====================
       INIT
    ====================== */
    connectedCallback() {

        Promise.all([
            getTodayAttendance(),
            getTodayBeats({ visitDate: this.selectedDate }),
            getDashboardSnapshot({ visitDate: this.selectedDate }),
            getDayTimeline({ visitDate: this.selectedDate })
        ])
        .then(([attendance, beats, snapshot, timeline]) => {

            /* Attendance */
            if (attendance) {
                this.dayStarted = true;
                this.dayEnded = !!attendance.End_Time__c;
            }

            /* Beats */
            this.beats = (beats || []).map(beat => {
                const startDay = beat.ibfsa__Start_Date__c || beat.Start_Date__c;
                const endDay = beat.ibfsa__End_Date__c || beat.End_Date__c;

                return {
                    ...beat,
                    startDay,
                    endDay,
                    rangeLabel: startDay && endDay
                        ? `${startDay} - ${endDay}`
                        : startDay
                            ? `Start ${startDay}`
                            : endDay
                                ? `End ${endDay}`
                                : null
                };
            });

            /* Dashboard */
            this.dashboardSnapshot = snapshot || {};

            /* Timeline */
            const records = timeline || [];
            this.timelineVisits = records;
            this.dailyVisits = records;

        })
        .catch(error => {
            this.showToast(
                'Loading Error',
                error?.body?.message || 'Failed to load dashboard data.',
                'error'
            );
        });
    }

    refreshDayViews() {
        // Full refresh used after start/end day actions.
        // Defer attendance refresh slightly to avoid racing with server/LDS cache.
        setTimeout(() => {
        this.loadAttendance();
        }, 500);

        this.loadDashboardSnapshot();
        this.fetchDayTimelineData();
        this.loadBeats().then(() => {
            if (this.viewMode === 'BEAT' && this.selectedBeatId) {
                this.loadVisits();
            }
        });
    }

    refreshDateScopedData() {
        // Date-driven refresh used by date picker and Today jump.
        this.loadAttendance();
        this.loadBeats();
        this.loadDashboardSnapshot();
        this.fetchDayTimelineData();

        if (this.timelineOpen) {
            this.loadTimelinePopup();
        }
    }

    /* =====================
       LOADERS
    ====================== */
    loadAttendance() {
        getTodayAttendance()
            .then(att => {
                const serverStarted = !!att;
                const serverEnded = !!(att?.End_Time__c || att?.ibfsa__End_Time__c);

                // Only advance state; never regress due to stale reads.
                if (serverStarted && !this.dayStarted) {
                    this.dayStarted = true;
                }
                if (serverEnded && !this.dayEnded) {
                    this.dayEnded = true;
                }
            })
            .catch(() => {
                // Keep optimistic UI on error
            });
    }

    loadBeats() {
        return getTodayBeats({ visitDate: this.selectedDate })
            .then(r => {
                this.beats = (r || []).map(beat => {
                    const startDay = beat.ibfsa__Start_Date__c || beat.Start_Date__c;
                    const endDay = beat.ibfsa__End_Date__c || beat.End_Date__c;
                    return {
                        ...beat,
                        startDay,
                        endDay,
                        rangeLabel: startDay && endDay
                            ? `${startDay} - ${endDay}`
                            : startDay
                                ? `Start ${startDay}`
                                : endDay
                                    ? `End ${endDay}`
                                    : null
                    };
                });

                const stillValid = this.beats.some(beat => beat.Id === this.selectedBeatId);
                if (!stillValid) {
                    this.selectedBeatId = null;
                    this.selectedBeatName = null;
                    this.viewMode = null;
                    this.stayOnFieldNoBeat = this.activeMainScreen === 'field';
                    this.applyVisits([], false);
                } else if (this.viewMode === 'BEAT') {
                    this.stayOnFieldNoBeat = false;
                    this.loadVisits();
                }
            })
            .catch(() => {
                this.beats = [];
            });
    }

    loadDashboardSnapshot() {
        return getDashboardSnapshot({ visitDate: this.selectedDate })
            .then(result => {
                this.dashboardSnapshot = result || {};
            })
            .catch(() => {
                this.dashboardSnapshot = {};
            });
    }

    loadTimelinePopup() {
        this.fetchDayTimelineData(true, true);
    }
    
    fetchDayTimelineData(showLoader = false, showErrorToast = false) {
        if (showLoader) {
            this.timelineLoading = true;
        }

        return getDayTimeline({ visitDate: this.selectedDate })
            .then(r => {
                const records = r || [];
                this.timelineVisits = records;
                this.dailyVisits = records;
            })
            .catch(err => {
                this.timelineVisits = [];
                this.dailyVisits = [];
                if (showErrorToast) {
                    this.showToast(
                        'Unable to load timeline',
                        err?.body?.message || 'Please try again.',
                        'error'
                    );
                }
            })
            .finally(() => {
                if (showLoader) {
                    this.timelineLoading = false;
                }
            });
    }

    loadVisits() {
        if (!this.selectedBeatId) return;

        getVisitsByBeat({
            beatId: this.selectedBeatId,
            visitDate: this.selectedDate
        })
        .then(r => this.applyVisits(r));
    }

    /* =====================
       ACTIONS
    ====================== */
    handleTimelineClick() {
        this.timelineOpen = !this.timelineOpen;
        if (this.timelineOpen) {
            this.showBeatDropdown = false;
            this.loadTimelinePopup();
        }
    }

    handleTabChange(event) {
        const nextTab = event?.currentTarget?.dataset?.tab;
        if (!nextTab || nextTab === this.activeProductSchemeTab) return;
        this.activeProductSchemeTab = nextTab;
    }

    handleOpenNewProductsModal() {
        this.showNewProductsModal = true;
    }

    handleCloseNewProductsModal() {
        this.showNewProductsModal = false;
    }

    handleOpenSchemesModal() {
        this.showSchemesModal = true;
    }

    handleCloseSchemesModal() {
        this.showSchemesModal = false;
    }

    handleOpenBeatPlanWeekly() {
        this.activeMainScreen = 'beatPlanWeekly';
    }

    handleCloseBeatPlanWeekly() {
        this.activeMainScreen = 'dashboard';
    }

    handleBeatToggle() {
        this.showBeatDropdown = !this.showBeatDropdown;
    }

    handleBeatSelect(e) {
        this.selectedBeatId = e.currentTarget.dataset.id;
        this.selectedBeatName = e.currentTarget.dataset.name;
        this.showBeatDropdown = false;

        this.viewMode = 'BEAT';
        this.activeMainScreen = 'field';
        this.stayOnFieldNoBeat = false;
        this.applyVisits([], false);
        this.loadVisits();
    }

    handleBackToDashboard() {
        this.activeMainScreen = 'dashboard';
        this.showBeatDropdown = false;
        this.stayOnFieldNoBeat = false;
    }

    handleGenerateInsights() {
        this.showToast(
            'Insights ready',
            this.nextActionLine,
            'info'
        );
    }

    handleDateChange(e) {
        this.selectedDate = e.currentTarget.dataset.date;
        const today = formatDateValue(new Date());
        this.isToday = this.selectedDate === today;
        this.refreshDateScopedData();
    }

    handleRefresh() {
        this.applyVisits([], false);
        this.loadDashboardSnapshot();
        this.fetchDayTimelineData();
        setTimeout(() => {
            if (this.viewMode === 'BEAT') this.loadVisits();
            if (this.timelineOpen) this.loadTimelinePopup();
        }, 0);
    }

    handleOpenVisit(event) {
        const visitId = event.detail?.visit?.Id;
        if (!visitId) return;

        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: {
                componentName: 'c__visitDetailPage'
            },
            state: {
                c__visitId: visitId
            }
        });
    }

    handleStartDay() {
        if (this.startDayDisabled) return;
        this.performDayAction(
            startDay,
            () => {
                this.dayStarted = true;
                this.dayEnded = false;

                // Dispatch a component-scoped custom event so this component can react if needed.
                // Consumers outside this component are not required for this approach.
                this.dispatchEvent(new CustomEvent('fielddaystatuschange', {
                    detail: { action: 'start', dayStarted: true, dayEnded: false },
                    bubbles: false,
                    composed: false
                }));
            },
            'Day started',
            'You are checked in for today.'
        );
    }

    handleEndDay() {
        if (this.endDayDisabled) return;
        this.performDayAction(
            endDay,
            () => {
                this.dayEnded = true;

                // Dispatch a component-scoped custom event
                this.dispatchEvent(new CustomEvent('fielddaystatuschange', {
                    detail: { action: 'end', dayStarted: this.dayStarted, dayEnded: true },
                    bubbles: false,
                    composed: false
                }));
            },
            'Day ended',
            'You are checked out for today.'
        );
    }

    performDayAction(apexMethod, onSuccess, title, message) {
        if (!navigator?.geolocation) {
            this.showToast('Location unavailable', 'Geolocation is not supported.', 'error');
            return;
        }

        navigator.geolocation.getCurrentPosition(
            pos => {
                apexMethod({
                    lat: pos.coords.latitude.toString(),
                    lon: pos.coords.longitude.toString()
                })
                .then(() => {
                    if (onSuccess) onSuccess();
                    this.refreshDayViews();
                    this.showToast(title, message, 'success');
                })
                .catch(err => {
                    this.showToast(
                        'Action failed',
                        err?.body?.message || 'Please try again.',
                        'error'
                    );
                });
            },
            () => this.showToast('Location required', 'Please enable location permission.', 'error'),
            { enableHighAccuracy: true }
        );
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    applyVisits(nextVisits, shouldPulse = true) {
        this.visits = [...nextVisits];
        if (shouldPulse) {
            this.pulseSummaryIfChanged();
        }
    }

    pulseSummaryIfChanged() {
        const next = {
            completed: this.completedCount,
            inProgress: this.inProgressCount,
            pending: this.pendingCount
        };

        const changed = next.completed !== this._lastSummary.completed ||
            next.inProgress !== this._lastSummary.inProgress ||
            next.pending !== this._lastSummary.pending;

        this._lastSummary = next;

        if (!changed) return;

        this.summaryPulse = false;
        requestAnimationFrame(() => {
            this.summaryPulse = true;
            clearTimeout(this._summaryPulseTimeout);
            this._summaryPulseTimeout = setTimeout(() => {
                this.summaryPulse = false;
            }, 320);
        });
    }

    /* =====================
       GETTERS (UI)
    ====================== */
    get beatLabel() {
        return this.selectedBeatName || 'Select Beat for Today';
    }

    get firstName() {
        return this.userName?.split(' ')[0] || 'Sales Rep';
    }

    get beatOptions() {
        return (this.beats || []).map(beat => ({
            ...beat,
            rowClass: `beat-option${beat.Id === this.selectedBeatId ? ' selected' : ''}`,
            checkMark: beat.Id === this.selectedBeatId ? '✓' : ''
        }));
    }

    get effectiveDailyVisits() {
        return this.dailyVisits.length ? this.dailyVisits : this.visits;
    }

    get isBeatMode() {
        return this.viewMode === 'BEAT';
    }

    get isTimelineMode() {
        return this.viewMode === 'DAY';
    }

    get progressPercentage() {
        const completed = this.effectiveDailyVisits.filter(
            v => this.normalizeStatus(this.getVisitStatus(v)) === 'completed'
        ).length;

        return this.effectiveDailyVisits.length
            ? Math.round((completed / this.effectiveDailyVisits.length) * 100)
            : 0;
    }

    get progressStyle() {
        return `width: ${this.progressPercentage}%;`;
    }

    get totalVisits() {
        return this.effectiveDailyVisits.length;
    }

    get completedCount() {
        return this.effectiveDailyVisits.filter(
            v => this.normalizeStatus(this.getVisitStatus(v)) === 'completed'
        ).length;
    }

    get inProgressCount() {
        return this.effectiveDailyVisits.filter(
            v => this.normalizeStatus(this.getVisitStatus(v)) === 'in progress'
        ).length;
    }

    get pendingCount() {
        const total = this.visits.length;
        return Math.max(total - this.completedCount - this.inProgressCount, 0);
    }

    get startDayDisabled() {
        return !this.isToday || this.dayStarted || this.dayEnded;
    }

    get endDayDisabled() {
        return !this.isToday || !this.dayStarted || this.dayEnded;
    }

    get showStartDayButton() {
        return !this.dayStarted && !this.dayEnded;
    }

    get showEndDayButton() {
        return this.dayStarted && !this.dayEnded;
    }

    get showDayEndedButton() {
        return this.dayEnded;
    }

    get summaryCompletedClass() {
        return `summary-pill done${this.summaryPulse ? ' pulse' : ''}`;
    }

    get summaryProgressClass() {
        return `summary-pill progress${this.summaryPulse ? ' pulse' : ''}`;
    }

    get summaryPendingClass() {
        return `summary-pill pending${this.summaryPulse ? ' pulse' : ''}`;
    }

    get isLatestProductsTab() {
        return this.activeProductSchemeTab === 'products';
    }

    get isActiveSchemesTab() {
        return this.activeProductSchemeTab === 'schemes';
    }

    get latestProductsTabClass() {
        return `tab-btn${this.isLatestProductsTab ? ' active' : ''}`;
    }

    get schemesTabClass() {
        return `tab-btn${this.isActiveSchemesTab ? ' active' : ''}`;
    }


    get selectedDateLabel() {
        if (!this.selectedDate) {
            return '';
        }
        const dateObj = new Date(`${this.selectedDate}T00:00:00`);
        return dateObj.toLocaleDateString('en-IN', {
            weekday: 'short',
            day: '2-digit',
            month: 'short',
            year: 'numeric'
        });
    }
    get salesTargetAmount() {
        const snapshotTarget = Number(this.dashboardSnapshot?.targetAmount);
        if (!Number.isNaN(snapshotTarget) && snapshotTarget > 0) {
            return snapshotTarget;
        }
        return 0;
    }

    get salesAchievedAmount() {
        const snapshotActual = Number(this.dashboardSnapshot?.actualSales);
        if (!Number.isNaN(snapshotActual) && snapshotActual >= 0) {
            return snapshotActual;
        }
        return (this.completedCount * 12000) + (this.inProgressCount * 6000);
    }

    get salesPendingAmount() {
        return Math.max(this.salesTargetAmount - this.salesAchievedAmount, 0);
    }

    get salesAchievementPercent() {
        const snapshotPercent = Number(this.dashboardSnapshot?.achievementPercent);
        if (!Number.isNaN(snapshotPercent) && snapshotPercent >= 0) {
            return Math.min(100, Math.round(snapshotPercent));
        }
        return Math.min(100, Math.round((this.salesAchievedAmount / this.salesTargetAmount) * 100));
    }

    get salesProgressStyle() {
        return `width:${this.salesAchievementPercent}%`;
    }

    get formattedTargetAmount() {
        return this.formatINRCurrency(this.salesTargetAmount);
    }

    get formattedAchievedAmount() {
        return this.formatINRCurrency(this.salesAchievedAmount);
    }

    get formattedPendingAmount() {
        return this.formatINRCurrency(this.salesPendingAmount);
    }

    get incentiveTarget() {
        return Math.max(this.totalVisits, 1);
    }

    get incentiveAchieved() {
        return this.completedCount;
    }

    get incentivePercent() {
        return Math.min(100, Math.round((this.incentiveAchieved / this.incentiveTarget) * 100));
    }

    get incentiveProgressStyle() {
        return `width:${this.incentivePercent}%`;
    }

    get productivityScore() {
        if (!this.dayStarted) return 0;
        if (this.dayEnded) return 100;
        return Math.min(98, Math.max(35, this.progressPercentage + 32));
    }

    get beatCoverageLabel() {
        return `${this.completedCount + this.inProgressCount}/${Math.max(this.totalVisits, 0)}`;
    }

    get nextActionLine() {
        if (!this.dayStarted) return 'Start day to unlock beats and visit operations.';
        if (!this.selectedBeatId) return 'Select a beat to load your outlets and route.';
        if (!this.completedCount) return 'Complete your first outlet to build momentum.';
        if (!this.dayEnded) return 'Review expenses and close day after final visit.';
        return 'Day complete. Review performance and prepare tomorrow.';
    }

    get motivationLine() {
        const hour = new Date().getHours();
        if (!this.dayStarted) return 'Strong start wins the day. Check in and attack the first beat.';
        if (hour < 13) return 'Morning consistency drives target conversion.';
        if (hour < 17) return 'Push high value SKUs now to maximize incentive.';
        if (!this.dayEnded) return 'Finish strong: update final expenses and complete day-end.';
        return 'Great finish. Keep the same discipline tomorrow.';
    }

    get flowStartClass() {
        return `journey-step${this.dayStarted ? ' done' : ' active'}`;
    }

    get flowCockpitClass() {
        if (!this.dayStarted) return 'journey-step';
        if (this.selectedBeatId) return 'journey-step done';
        return 'journey-step active';
    }

    get flowBeatClass() {
        if (!this.dayStarted) return 'journey-step';
        if (this.selectedBeatId) return 'journey-step done';
        return 'journey-step active';
    }

    get flowVisitsClass() {
        if (!this.selectedBeatId) return 'journey-step';
        if (this.completedCount > 0) return 'journey-step done';
        return 'journey-step active';
    }

    get flowEndClass() {
        if (this.dayEnded) return 'journey-step done';
        if (this.dayStarted) return 'journey-step active';
        return 'journey-step';
    }

    get journeyStateLabel() {
        if (this.dayEnded) return 'Day Completed';
        if (this.dayStarted) return 'In Field';
        return 'Not Started';
    }

    get journeyStateClass() {
        if (this.dayEnded) return 'journey-state ended';
        if (this.dayStarted) return 'journey-state active';
        return 'journey-state';
    }

    get performanceLiftPercent() {
        if (!this.dayStarted) return 0;
        return Math.min(35, Math.max(8, this.progressPercentage - 5));
    }

    get incentiveCurrentLabel() {
        const snapshotIncentive = Number(this.dashboardSnapshot?.incentiveAmount);
        if (!Number.isNaN(snapshotIncentive) && snapshotIncentive >= 0) {
            return this.formatINRCurrency(snapshotIncentive);
        }
        return this.formatINRCurrency(this.salesAchievedAmount);
    }

    get incentiveTargetLabel() {
        return this.formatINRCurrency(this.salesTargetAmount);
    }

    get incentiveFloorLabel() {
        return this.formatINRCurrency(Math.round(this.salesTargetAmount * 0.38));
    }

    get incentiveMidLabel() {
        return this.formatINRCurrency(Math.round(this.salesTargetAmount * 0.64));
    }

    get progressDonutStyle() {
        return `--progress:${this.progressPercentage}`;
    }

    get firstProductCategory() {
        return this.newProducts?.[0]?.category || 'Consumer Electronics';
    }

    get segmentWidthA() {
        return Math.max(18, Math.round(this.salesAchievementPercent * 0.42));
    }

    get segmentWidthB() {
        return Math.max(22, Math.round(100 - (this.salesAchievementPercent * 0.26)));
    }

    get salesSegmentAStyle() {
        return `width:${Math.min(this.segmentWidthA, 60)}%`;
    }

    get salesSegmentBStyle() {
        return `width:${Math.min(this.segmentWidthB, 65)}%`;
    }

    get salesSegmentCStyle() {
        const width = Math.max(10, 100 - this.segmentWidthA - this.segmentWidthB);
        return `width:${width}%`;
    }

    get userInitials() {
        return this.userName
            ?.split(' ')
            .map(c => c[0])
            .join('') || 'SR';
    }

    get isDashboardScreen() {
        return this.activeMainScreen === 'dashboard';
    }

    get isFieldScreen() {
        return this.activeMainScreen === 'field';
    }

    get isBeatPlanWeeklyScreen() {
        return this.activeMainScreen === 'beatPlanWeekly';
    }

    get hasBeatSelected() {
        return !!this.selectedBeatId;
    }

    get currentMonthLabel() {
        if (this.dashboardSnapshot?.monthLabel) {
            return this.dashboardSnapshot.monthLabel;
        }
        return new Date().toLocaleDateString('en-IN', {
            month: 'long'
        });
    }

    get monthlyPerformanceLabel() {
        const rating = this.dashboardSnapshot?.performanceRating;
        if (rating) return rating;
        const score = this.salesAchievementPercent;
        if (score >= 90) return 'Excellent';
        if (score >= 70) return 'Strong';
        if (score >= 50) return 'On Track';
        return 'Needs Focus';
    }

    get featuredProductName() {
        return this.newProducts?.[0]?.name || 'Fresh Product';
    }

    get featuredProductCategory() {
        return this.newProducts?.[0]?.category || 'General';
    }

    get featuredSchemeTitle() {
        return this.dashboardSnapshot?.schemeTitle || this.activeSchemes?.[0]?.title || 'Retail Push';
    }

    get featuredSchemeDetail() {
        return this.dashboardSnapshot?.schemeDetail || this.activeSchemes?.[0]?.detail || 'Demo scheme';
    }

    get actualSalesLabel() {
        return this.formatINRCurrency(this.salesAchievedAmount);
    }

    get targetAmountLabel() {
        return this.formatINRCurrency(this.salesTargetAmount);
    }

    get achievementPercentLabel() {
        return `${this.salesAchievementPercent}%`;
    }

    get achievementProgressStyle() {
        return `width:${Math.max(0, Math.min(100, this.salesAchievementPercent))}%`;
    }

    get dashboardCompletedVisits() {
        const value = Number(this.dashboardSnapshot?.completedVisits);
        if (!Number.isNaN(value) && value >= 0) return Math.round(value);
        return this.completedCount;
    }

    get dashboardPlannedVisits() {
        const value = Number(this.dashboardSnapshot?.plannedVisits);
        if (!Number.isNaN(value) && value >= 0) return Math.round(value);
        return this.totalVisits;
    }

    get visitProgressLabel() {
        return `${this.dashboardCompletedVisits}/${this.dashboardPlannedVisits}`;
    }

    get incentiveAmountLabel() {
        return this.incentiveCurrentLabel;
    }

    get avgOrderValueLabel() {
        const completed = Math.max(this.dashboardCompletedVisits, 1);
        const avg = Math.round(this.salesAchievedAmount / completed);
        return this.formatINRCurrency(avg);
    }

    get pendingCollectionLabel() {
        return this.formatINRCurrency(this.salesPendingAmount);
    }

    get activeSchemeCountLabel() {
        const fromSnapshot = this.dashboardSnapshot?.schemeTitle ? 1 : 0;
        const fallback = this.activeSchemes?.length || 0;
        return `${Math.max(fromSnapshot, fallback)}`;
    }


    get dateOptions() {
        const base = new Date();
        base.setDate(base.getDate() + this.dateWindowOffset);
        const todayVal = formatDateValue(new Date());

        return [...Array(this.dateWindowSize).keys()].map(i => {
            const d = new Date(base);
            d.setDate(base.getDate() + i);
            const val = formatDateValue(d);
            const isSelected = val === this.selectedDate;
            const isToday = val === todayVal;

            return {
                value: val,
                day: d.toLocaleDateString('en', { weekday: 'short' }),
                date: d.getDate(),
                class: `date-btn${isSelected ? ' active' : ''}${isToday ? ' today' : ''}`
            };
        });
    }

    handlePrevWindow() {
        this.dateWindowOffset -= this.dateWindowSize;
    }

    handleNextWindow() {
        this.dateWindowOffset += this.dateWindowSize;
    }

    handleTodayJump() {
        const today = formatDateValue(new Date());
        this.selectedDate = today;
        this.isToday = true;
        this.dateWindowOffset = DEFAULT_DATE_WINDOW_OFFSET;
        this.refreshDateScopedData();
    }

    handleVisitTabChange(event) {
        const tab = event?.detail?.tab;
        if (!tab || tab === this.activeVisitTab) return;
        this.activeVisitTab = tab;
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

    formatINRCurrency(value) {
        return new Intl.NumberFormat('en-IN', {
            style: 'currency',
            currency: 'INR',
            maximumFractionDigits: 0
        }).format(value || 0);
    }
}