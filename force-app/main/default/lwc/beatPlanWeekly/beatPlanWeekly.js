/**
 * beatPlanWeekly.js
 *
 * REAL SCHEMA  (ibfsa__ package)
 * ──────────────────────────────────────────────────────────────────────
 *
 *   ibfsa__Beat__c            — weekly plan header
 *     ibfsa__Sales_Rep__c     — rep lookup
 *     ibfsa__Start_Date__c    — plan start (Monday)
 *     ibfsa__End_Date__c      — plan end   (Sunday)
 *     ibfsa__Status__c        — Active / Submitted / Approved / Rejected
 *     ibfsa__Active__c        — boolean
 *
 *   ibfsa__Visit__c           — one visit per outlet per day
 *     ibfsa__Beat__c          — parent Beat lookup
 *     ibfsa__Outlet1__c       — Account lookup  (the outlet/store)
 *     ibfsa__Visit_Date__c    — Date
 *     ibfsa__Planned_Start_Time__c  — DateTime
 *     ibfsa__Planned_End_Time__c    — DateTime
 *     ibfsa__Visit_Status__c        — Planned / In Progress / Missed
 *     ibfsa__Approval_Status__c     — Planned / Pending Approval / Approved
 *     ibfsa__Is_Completed__c        — boolean
 *     ibfsa__Sequence__c            — Number (visit order in day)
 *
 *   Account (outlet)
 *     ibfsa__Beat__c              — direct Beat lookup on Account
 *     ibfsa__Outlet_Priority__c   — priority picklist
 *
 * APEX METHODS
 * ──────────────────────────────────────────────────────────────────────
 *   getWeeklyVisits(anchorDate)   → WeekData { stats, visits[] }
 *   getBeatForWeek(anchorDate)    → ibfsa__Beat__c Id | null
 *   saveVisit(visitJson)          → ibfsa__Visit__c Id
 */

import { LightningElement, track }  from 'lwc';
import { ShowToastEvent }           from 'lightning/platformShowToastEvent';
import USER_ID from '@salesforce/user/Id';

import getWeeklyVisits  from '@salesforce/apex/BeatPlanController.getWeeklyVisits';
import getOutletsForBeat from '@salesforce/apex/BeatPlanController.getOutletsForBeat';
import getUserBeats from '@salesforce/apex/BeatPlanController.getUserBeats';
import createVisitsAndSubmitForApproval from '@salesforce/apex/BeatPlanController.createVisitsAndSubmitForApproval';

// ── Constants ─────────────────────────────────────────────────────────────────
const DAY_KEYS  = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
const DAY_NAMES = { MON:'Mon', TUE:'Tue', WED:'Wed', THU:'Thu', FRI:'Fri', SAT:'Sat', SUN:'Sun' };

// Card background CSS — keyed to local status mapping
const CARD_CSS = {
    'card-completed'  : 'bp-card bp-card--completed',
    'card-draft'      : 'bp-card bp-card--draft',
    'card-missed'     : 'bp-card bp-card--missed',
    'card-inprogress' : 'bp-card bp-card--inprogress',
    'card-planned'    : 'bp-card bp-card--planned'
};

// Approval status pill CSS  (ibfsa__Approval_Status__c)
const APPROVAL_CSS = {
    'Draft'             : 'bp-pill bp-pill--planned',
    'Submitted'         : 'bp-pill bp-pill--pending',
    'Planned'           : 'bp-pill bp-pill--planned',
    'Pending Approval'  : 'bp-pill bp-pill--pending',
    'Approved'          : 'bp-pill bp-pill--completed',
    'Rejected'          : 'bp-pill bp-pill--missed'
};

// Beat status badge CSS  (ibfsa__Beat__c.ibfsa__Status__c)
const BEAT_STATUS_CSS = {
    'Active'    : 'bp-beat-badge bp-beat-badge--active',
    'Submitted' : 'bp-beat-badge bp-beat-badge--submitted',
    'Approved'  : 'bp-beat-badge bp-beat-badge--approved',
    'Rejected'  : 'bp-beat-badge bp-beat-badge--rejected',
    'Inactive'  : 'bp-beat-badge bp-beat-badge--inactive'
};

export default class BeatPlanWeekly extends LightningElement {


    // ── State ─────────────────────────────────────────────────────────────────
    @track anchorDate    = new Date();
    @track stats         = null;      // WeekStats from Apex
    @track visits        = [];        // enriched VisitWrapper[]
    @track isLoading     = false;
    @track showModal     = false;
    @track showSuccess   = false;
    @track selectedVisit = null;
    @track draftVisits = [];
    @track beatOptions = [];
    @track outletOptions = [];
    @track showDraftModal = false;
    @track draftForm = {
        visitDate: '',
        beatId: '',
        outletId: '',
        startTime: '',
        endTime: '',
        notes: ''
    };
    @track draftErrors = {};
    currentUserId = USER_ID;

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadWeek();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DATA
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Calls getWeeklyVisits(anchorDate).
     * Apex finds the active ibfsa__Beat__c for this rep + week,
     * then fetches ibfsa__Visit__c children with ibfsa__Outlet1__r (Account).
     */
    async loadWeek() {
        this.isLoading = true;
        try {
            const data   = await getWeeklyVisits({ anchorDate: this._isoDate(this.anchorDate) });
            this.stats   = data.stats;
            this.visits  = (data.visits || []).map(v => this._enrich(v));
            await this.loadBeats();
            if (this.stats?.beatId) {
                await this.loadOutlets(this.stats.beatId);
            } else {
                this.outletOptions = [];
            }
        } catch (err) {
            this._error('Failed to load visits', err);
        } finally {
            this.isLoading = false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // COMPUTED PROPERTIES
    // ─────────────────────────────────────────────────────────────────────────

    /** "Feb 11 – Feb 17"  from Apex WeekStats.weekLabel */
    get weekLabel() {
        return this.stats?.weekLabel ?? this._localWeekLabel();
    }

    /** ibfsa__Beat__c.Name */
    get beatName() {
        return this.stats?.beatName ?? null;
    }

    /** ibfsa__Beat__c.ibfsa__Status__c */
    get beatStatus() {
        return this.stats?.beatStatus ?? null;
    }

    /** CSS badge for ibfsa__Beat__c.ibfsa__Status__c */
    get beatStatusCls() {
        return BEAT_STATUS_CSS[this.stats?.beatStatus] ?? 'bp-beat-badge';
    }

    /**
     * Submit disabled when:
     *  - No active Beat for this week
     *  - Beat already Submitted or Approved
     *  - Loading
     */
    get isSubmitDisabled() {
        if (this.isLoading) return true;
        return this.currentWeekDrafts.length === 0;
    }

    get hasDraftVisits() {
        return this.draftVisits.length > 0;
    }

    get draftCount() {
        return this.currentWeekDrafts.length;
    }

    get draftDateOptions() {
        const mon = this._mondayOf(this.anchorDate);
        return DAY_KEYS.map((key, i) => {
            const d = new Date(mon);
            d.setDate(d.getDate() + i);
            const value = this._isoDate(d);
            return {
                label: `${DAY_NAMES[key]}, ${d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}`,
                value
            };
        });
    }

    get statusLabel() {
        return 'Draft';
    }

    get salesRepLabel() {
        return 'Current User';
    }

    get visitDateError() {
        return this.draftErrors?.visitDate || '';
    }

    /** Show "No Beat" panel when Apex returned no Beat and not loading */
    get showNoBeat() {
        return false;
    }

    /** True when Beat exists but has zero visits */
    get isEmpty() {
        return !this.isLoading && this.calendarRows.every(row => row.cells.every(cell => !cell.visit));
    }

    get totalVisitsDisplay() {
        return (this.stats?.totalVisits || 0) + this.currentWeekDrafts.length;
    }

    get completedDisplay() {
        return this.stats?.completed || 0;
    }

    get pendingDisplay() {
        return (this.stats?.pending || 0) + this.currentWeekDrafts.length;
    }

    get missedDisplay() {
        return this.stats?.missed || 0;
    }

    /**
     * Day column headers.
     * [ { key:'MON', abbr:'Mon', dateNum:11, cls:'bp-dh' }, … ]
     */
    get dayHeaders() {
        const mon = this._mondayOf(this.anchorDate);
        return DAY_KEYS.map((key, i) => {
            const d = new Date(mon);
            d.setDate(d.getDate() + i);
            const today = this._sameDay(d, new Date());
            return {
                key,
                abbr    : DAY_NAMES[key],
                dateNum : d.getDate(),
                cls     : `bp-dh${today ? ' bp-dh--today' : ''}`
            };
        });
    }

    /**
     * Calendar grid: N rows × 7 columns.
     * Each row is an array of 7 cells; each cell holds visit | null.
     * Visits are sorted by ibfsa__Sequence__c then ibfsa__Planned_Start_Time__c
     * (already ordered by Apex).
     */
    get calendarRows() {
        const byDay = {};
        DAY_KEYS.forEach(k => (byDay[k] = []));

        this.visits.forEach(v => {
            if (!this._isDateInCurrentWeek(v.visitDate)) return;
            if (byDay[v.dayOfWeek]) byDay[v.dayOfWeek].push(v);
        });

        this.currentWeekDrafts.forEach(d => {
            const dayKey = this._dayKeyFromDate(d.visitDate);
            if (!byDay[dayKey]) return;
            byDay[dayKey].push({
                id: d.id,
                sequence: null,
                outletName: d.outletName,
                plannedStartTime: this._to12Hour(d.startTime),
                plannedEndTime: this._to12Hour(d.endTime),
                approvalStatus: 'Draft',
                visitStatus: 'Draft',
                badgeCls: 'bp-card__badge',
                showBadge: true,
                cardCls: CARD_CSS['card-planned'],
                isDraft: true,
                sortMinutes: this._timeToMinutes(d.startTime)
            });
        });

        DAY_KEYS.forEach(k => {
            byDay[k] = byDay[k].sort((a, b) => this._visitSortMinutes(a) - this._visitSortMinutes(b));
        });

        const maxRows = Math.max(1, ...DAY_KEYS.map(k => byDay[k].length));

        return Array.from({ length: maxRows }, (_, ri) => ({
            rowIndex : ri,
            cells    : DAY_KEYS.map(key => ({
                cellKey : `${key}-${ri}`,
                visit   : byDay[key][ri] ?? null
            }))
        }));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HANDLERS
    // ─────────────────────────────────────────────────────────────────────────

    handlePrevWeek() {
        this.anchorDate = new Date(this.anchorDate);
        this.anchorDate.setDate(this.anchorDate.getDate() - 7);
        this.loadWeek();
    }

    handleNextWeek() {
        this.anchorDate = new Date(this.anchorDate);
        this.anchorDate.setDate(this.anchorDate.getDate() + 7);
        this.loadWeek();
    }

    handleDayClick(event) {
        // Future: open Add Visit pre-filled with this day
        console.log('[BeatPlan] Day clicked:', event.currentTarget.dataset.day);
    }

    handleVisitClick(event) {
        const id    = event.currentTarget.dataset.id;
        if (id && id.startsWith('draft-')) {
            this.showToast('', 'Draft visit. It will be created when you submit beat plan.', 'base');
            return;
        }
        const visit = this.visits.find(v => v.id === id);
        if (visit) {
            this.selectedVisit = visit;
            this.showModal     = true;
        }
    }

    handleCloseModal() {
        this.showModal     = false;
        this.selectedVisit = null;
    }

    /**
     * Add Visit:
     *  1. getBeatForWeek() → ibfsa__Beat__c.Id for this rep + week
     *  2. Navigate to ibfsa__Visit__c new record page with Beat pre-filled.
     *     User selects Account from ibfsa__Outlet1__c lookup on the Visit form.
     */
    async handleAddVisit() {
        try {
            if (!this.beatOptions.length) {
                await this.loadBeats();
            }
            const defaultBeatId = this.stats?.beatId || this.beatOptions[0]?.value || '';
            if (defaultBeatId) {
                await this.loadOutlets(defaultBeatId);
            } else {
                this.outletOptions = [];
            }

            const firstDate = this.draftDateOptions[0]?.value || this._isoDate(new Date());
            this.draftForm = {
                visitDate: firstDate,
                beatId: defaultBeatId,
                outletId: '',
                startTime: '09:00',
                endTime: '10:00',
                notes: ''
            };
            this.draftErrors = {};
            this.showDraftModal = true;
        } catch (err) {
            this._error('Could not open Add Visit', err);
        }
    }

    handleDraftFieldChange(event) {
        const { name, value } = event.target;
        this.draftForm = { ...this.draftForm, [name]: value };
        this.draftErrors = { ...this.draftErrors, [name]: '' };
        if (event.target && typeof event.target.setCustomValidity === 'function') {
            event.target.setCustomValidity('');
            event.target.reportValidity();
        }
        if (name === 'beatId') {
            this.draftForm = { ...this.draftForm, beatId: value, outletId: '' };
            if (value) {
                this.loadOutlets(value);
            } else {
                this.outletOptions = [];
            }
        }
    }

    handleCloseDraftModal() {
        this.showDraftModal = false;
        this.draftErrors = {};
    }

    handleAddDraftVisit() {
        const errors = {};
        let nonFutureDateMessage = '';
        if (!this.draftForm.visitDate) errors.visitDate = 'Required';
        if (this.draftForm.visitDate && this.draftForm.visitDate < this._isoDate(new Date())) {
            nonFutureDateMessage = 'Visit can only be created for today or future dates';
        }
        if (!errors.visitDate && this.draftForm.visitDate && !this._isDateInCurrentWeek(this.draftForm.visitDate)) {
            errors.visitDate = 'Select a date from the displayed week';
        }
        if (!this.draftForm.beatId) errors.beatId = 'Required';
        if (!this.draftForm.outletId) errors.outletId = 'Required';
        if (!this.draftForm.startTime) errors.startTime = 'Required';
        if (!this.draftForm.endTime) errors.endTime = 'Required';
        if (this.draftForm.startTime && this.draftForm.endTime && this.draftForm.startTime >= this.draftForm.endTime) {
            errors.endTime = 'End time must be after start time';
        }
        if (this._hasTimeConflict(this.draftForm.visitDate, this.draftForm.startTime, this.draftForm.endTime)) {
            errors.startTime = 'Time overlap';
            errors.endTime = 'Another visit exists in same date/time slot';
        }
        if (Object.keys(errors).length || nonFutureDateMessage) {
            this.draftErrors = errors;
            this._reportDraftFieldErrors();
            if (nonFutureDateMessage) {
                this._error('Invalid Visit Date', { message: nonFutureDateMessage });
            }
            if (errors.endTime && errors.endTime.includes('date/time')) {
                this._error('Duplicate Time Slot', { message: errors.endTime });
            }
            return;
        }
        this.draftErrors = {};
        this._reportDraftFieldErrors();

        const outlet = this.outletOptions.find(o => o.value === this.draftForm.outletId);
        const beat = this.beatOptions.find(b => b.value === this.draftForm.beatId);
        const tempId = `draft-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
        const draft = {
            id: tempId,
            beatId: this.draftForm.beatId,
            beatName: beat?.label || '',
            visitDate: this.draftForm.visitDate,
            outletId: this.draftForm.outletId,
            outletName: outlet?.label || 'Outlet',
            startTime: this.draftForm.startTime,
            endTime: this.draftForm.endTime,
            notes: this.draftForm.notes || '',
            approvalStatus: 'Draft',
            visitStatus: 'Draft',
            salesRepId: this.currentUserId,
            salesRepName: this.salesRepLabel,
            displayDate: new Date(this.draftForm.visitDate).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
        };
        this.draftVisits = [...this.draftVisits, draft];
        this.showDraftModal = false;
        this.showSuccessToast('Draft visit added. It will be saved on Submit Beat Plan.');
    }

    handleRemoveDraft(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        this.draftVisits = this.draftVisits.filter(d => d.id !== id);
    }

    /**
     * Submit Beat Plan:
     *  Creates and submits only the drafts in the currently visible week.
     *  Drafts from other weeks remain in local state for later submission.
     */
    async handleSubmit() {
        const weekDrafts = this.currentWeekDrafts;
        if (weekDrafts.length === 0) return;

        this.isLoading = true;
        try {
            const sequenceByDate = this._buildSequenceMap();
            const draftsSorted = [...weekDrafts].sort((a, b) => {
                if (a.visitDate === b.visitDate) {
                    return a.startTime.localeCompare(b.startTime);
                }
                return a.visitDate.localeCompare(b.visitDate);
            });
            const payload = draftsSorted.map(d => {
                const seqKey = `${d.beatId}|${d.visitDate}`;
                const currentSeq = sequenceByDate[seqKey] || 0;
                sequenceByDate[seqKey] = currentSeq + 1;
                return JSON.stringify({
                    beatId: d.beatId,
                    outletId: d.outletId,
                    visitDate: d.visitDate,
                    sequence: sequenceByDate[seqKey],
                    visitStatus: 'Draft',
                    startTime: d.startTime,
                    endTime: d.endTime,
                    notes: d.notes
                });
            });

            await createVisitsAndSubmitForApproval({ draftVisitJsonList: payload });

            this.showSuccess = true;
            setTimeout(() => { this.showSuccess = false; }, 3500);
            const weekDraftIds = new Set(weekDrafts.map(d => d.id));
            this.draftVisits = this.draftVisits.filter(d => !weekDraftIds.has(d.id));

            this.dispatchEvent(new ShowToastEvent({
                title  : 'Visits Submitted',
                message: 'Current week visits are created and submitted for approval.',
                variant: 'success'
            }));

            await this.loadWeek();
        } catch (err) {
            this._error('Submission failed', err);
        } finally {
            this.isLoading = false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PRIVATE HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * Enrich a raw VisitWrapper from Apex with computed CSS and display fields.
     *
     * colorClass   → from Apex statusToColor(visitStatus, isCompleted, approvalStatus)
     * outletName   → ibfsa__Outlet1__r.Name  (Account on Visit)
     * beatName     → ibfsa__Beat__r.Name
     * showBadge    → hide badge only when completed (green card speaks for itself)
     */
    _enrich(v) {
        const statusLabel = v.approvalStatus || v.visitStatus || '';
        const cardKey = this._cardClassFromApproval(statusLabel);
        const badgeCls = [
            'bp-card__badge',
            statusLabel === 'Draft' ? 'bp-card__badge--draft' : '',
            statusLabel === 'Submitted' ? 'bp-card__badge--submitted' : '',
            statusLabel === 'Pending Approval' ? 'bp-card__badge--pending' : '',
            statusLabel === 'Approved' ? 'bp-card__badge--approved' : '',
            statusLabel === 'Rejected' ? 'bp-card__badge--rejected' : ''
        ].filter(Boolean).join(' ');
        return {
            ...v,
            cardCls          : CARD_CSS[cardKey]                ?? CARD_CSS['card-planned'],
            visitStatus      : statusLabel,
            visitStatusCls   : APPROVAL_CSS[statusLabel]        ?? 'bp-pill',
            approvalStatusCls: APPROVAL_CSS[v.approvalStatus]   ?? 'bp-pill',
            badgeCls,
            showBadge        : !v.isCompleted,
            formattedDate    : v.visitDate
                ? new Date(v.visitDate).toLocaleDateString('en-US', {
                    month: 'short', day: 'numeric', year: 'numeric'
                  })
                : ''
        };
    }

    _localWeekLabel() {
        const mon = this._mondayOf(this.anchorDate);
        const sun = new Date(mon);
        sun.setDate(sun.getDate() + 6);
        const fmt = d => d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        return `${fmt(mon)} – ${fmt(sun)}`;
    }

    _mondayOf(d) {
        const dt   = new Date(d);
        const day  = dt.getDay();
        const diff = day === 0 ? -6 : 1 - day;
        dt.setDate(dt.getDate() + diff);
        return dt;
    }

    get currentWeekDrafts() {
        return this.draftVisits.filter(d => {
            if (!d?.visitDate) return false;
            return this._isDateInCurrentWeek(d.visitDate);
        });
    }

    _isoDate(d) {
        const dt = new Date(d);
        const y = dt.getFullYear();
        const m = String(dt.getMonth() + 1).padStart(2, '0');
        const day = String(dt.getDate()).padStart(2, '0');
        return `${y}-${m}-${day}`;
    }

    _sameDay(a, b) {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth()    === b.getMonth()
            && a.getDate()     === b.getDate();
    }

    async loadOutlets(beatId) {
        const outlets = await getOutletsForBeat({ beatId });
        this.outletOptions = (outlets || []).map(o => ({
            label: o.Name,
            value: o.Id
        }));
    }

    async loadBeats() {
        const beats = await getUserBeats({ anchorDate: this._isoDate(this.anchorDate) });
        this.beatOptions = (beats || []).map(b => ({
            label: b.name,
            value: b.id
        }));
    }

    _buildSequenceMap() {
        const map = {};
        this.visits.forEach(v => {
            if (!this._isDateInCurrentWeek(v.visitDate)) return;
            const key = this._dateKey(v.visitDate);
            const seqKey = `${v.beatId || ''}|${key}`;
            map[seqKey] = (map[seqKey] || 0) + 1;
        });
        return map;
    }

    _dateKey(value) {
        if (!value) return '';
        if (typeof value === 'string') {
            return value.includes('T') ? value.split('T')[0] : value;
        }
        return this._isoDate(new Date(value));
    }

    _dayKeyFromDate(dateValue) {
        const d = this._fromDateValue(dateValue);
        const day = d.getDay(); // 0..6
        const map = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
        return map[day] || 'MON';
    }

    _isDateInCurrentWeek(dateValue) {
        const dayIso = this._dateKey(dateValue);
        if (!dayIso) return false;
        const mon = this._mondayOf(this.anchorDate);
        const sun = new Date(mon);
        sun.setDate(sun.getDate() + 6);
        const weekStartIso = this._isoDate(mon);
        const weekEndIso = this._isoDate(sun);
        return dayIso >= weekStartIso && dayIso <= weekEndIso;
    }

    _fromDateValue(value) {
        if (!value) return new Date(NaN);
        if (value instanceof Date) return new Date(value);
        if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
            const [y, m, d] = value.split('-').map(Number);
            return new Date(y, m - 1, d);
        }
        return new Date(value);
    }

    _timeToMinutes(hhmm) {
        if (!hhmm || !hhmm.includes(':')) return Number.MAX_SAFE_INTEGER;
        const [h, m] = hhmm.split(':').map(Number);
        return (h * 60) + m;
    }

    _displayTimeToMinutes(timeStr) {
        if (!timeStr) return Number.MAX_SAFE_INTEGER;
        const clean = timeStr.trim();
        const match = clean.match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/i);
        if (!match) return Number.MAX_SAFE_INTEGER;
        let h = Number(match[1]);
        const m = Number(match[2]);
        const ap = match[3].toUpperCase();
        if (ap === 'PM' && h !== 12) h += 12;
        if (ap === 'AM' && h === 12) h = 0;
        return (h * 60) + m;
    }

    _to12Hour(hhmm) {
        if (!hhmm || !hhmm.includes(':')) return '';
        let [h, m] = hhmm.split(':').map(Number);
        const ap = h >= 12 ? 'PM' : 'AM';
        h = h % 12 || 12;
        return `${h}:${String(m).padStart(2, '0')} ${ap}`;
    }

    _reportDraftFieldErrors() {
        const fields = this.template.querySelectorAll(
            'lightning-combobox[name], lightning-input[name], lightning-textarea[name]'
        );
        fields.forEach(field => {
            const msg = this.draftErrors?.[field.name] || '';
            if (typeof field.setCustomValidity === 'function') {
                field.setCustomValidity(msg);
                field.reportValidity();
            }
        });
    }

    _visitSortMinutes(v) {
        if (typeof v.sortMinutes === 'number') return v.sortMinutes;
        return this._displayTimeToMinutes(v.plannedStartTime);
    }

    _cardClassFromApproval(statusLabel) {
        if (statusLabel === 'Approved') return 'card-completed';
        if (statusLabel === 'Rejected') return 'card-missed';
        if (statusLabel === 'Submitted' || statusLabel === 'Pending Approval') return 'card-draft';
        if (statusLabel === 'Draft') return 'card-planned';
        return 'card-planned';
    }

    _hasTimeConflict(visitDate, startTime, endTime) {
        const candidateStart = this._timeToMinutes(startTime);
        const candidateEnd = this._timeToMinutes(endTime);
        if (candidateStart >= candidateEnd) return false;

        const draftConflict = this.draftVisits.some(d => {
            if (d.visitDate !== visitDate) return false;
            const s = this._timeToMinutes(d.startTime);
            const e = this._timeToMinutes(d.endTime);
            return candidateStart < e && candidateEnd > s;
        });
        if (draftConflict) return true;

        const existingConflict = this.visits.some(v => {
            if (this._dateKey(v.visitDate) !== visitDate) return false;
            const s = this._displayTimeToMinutes(v.plannedStartTime);
            const e = this._displayTimeToMinutes(v.plannedEndTime);
            if (s === Number.MAX_SAFE_INTEGER || e === Number.MAX_SAFE_INTEGER) return false;
            return candidateStart < e && candidateEnd > s;
        });
        return existingConflict;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }

    _error(title, err) {
        const msg = err?.body?.message || err?.message || 'Unexpected error.';
        this.dispatchEvent(new ShowToastEvent({ title, message: msg, variant: 'error' }));
    }
}