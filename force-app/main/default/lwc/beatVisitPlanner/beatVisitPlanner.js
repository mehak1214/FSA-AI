import { LightningElement, track } from 'lwc';

// ─── Constants ────────────────────────────────────────────────────────────────
const VISIT_TYPES = [
    'Order Visit', 'Promo Visit', 'Sample Visit',
    'Collection Visit', 'Service Visit', 'Audit Visit'
];

const VISIT_STATUSES = ['Planned', 'Completed', 'Missed'];

const MISSED_REASONS = [
    'Customer Not Available', 'Outlet Closed', 'Weather Conditions',
    'Vehicle Breakdown', 'Road Block', 'Other'
];

// Mock accounts (replace with @wire getAccountList in real implementation)
const MOCK_ACCOUNTS = [
    { Id: '001A', Name: 'ABC Retail',        Outlet_Code__c: 'OUT-001', BillingCity: 'Mumbai'    },
    { Id: '001B', Name: 'Metro Mart',         Outlet_Code__c: 'OUT-002', BillingCity: 'Pune'      },
    { Id: '001C', Name: 'Sunrise Mart',       Outlet_Code__c: 'OUT-003', BillingCity: 'Pune'      },
    { Id: '001D', Name: 'Star Distributors',  Outlet_Code__c: 'OUT-004', BillingCity: 'Pimpri'    },
    { Id: '001E', Name: 'XYZ Store',          Outlet_Code__c: 'OUT-005', BillingCity: 'Chinchwad' },
    { Id: '001F', Name: 'City Bazaar',        Outlet_Code__c: 'OUT-006', BillingCity: 'Pune'      },
    { Id: '001G', Name: 'Quick Basket',       Outlet_Code__c: 'OUT-007', BillingCity: 'Pune'      },
    { Id: '001H', Name: 'Daily Needs Hub',    Outlet_Code__c: 'OUT-008', BillingCity: 'Pune'      },
];

// Card colour palette (matching screenshot)
const PALETTES = [
    '#1a7f5a', '#1d4ed8', '#b91c1c', '#7c3aed',
    '#0369a1', '#be185d', '#c2410c', '#0f766e'
];

const DAY_LABELS = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

// ─── Utility functions ────────────────────────────────────────────────────────
function getWeekDays(offset = 0) {
    const today = new Date();
    const dow   = today.getDay();
    const mon   = new Date(today);
    mon.setDate(today.getDate() - (dow === 0 ? 6 : dow - 1) + offset * 7);

    return DAY_LABELS.map((label, i) => {
        const d = new Date(mon);
        d.setDate(mon.getDate() + i);
        return {
            label,
            num    : d.getDate(),
            dateStr: d.toISOString().split('T')[0],
            full   : d,
            visits : []
        };
    });
}

function formatWeekLabel(days) {
    const s  = days[0].full;
    const e  = days[6].full;
    const ms = s.toLocaleString('en-US', { month: 'short' });
    const me = e.toLocaleString('en-US', { month: 'short' });
    return `Week: ${ms} ${s.getDate()} \u2013 ${ms === me ? '' : me + ' '}${e.getDate()}`;
}

function timeToMin(t) {
    if (!t) return 0;
    const [h, m] = t.split(':').map(Number);
    return h * 60 + m;
}

function to12(t) {
    if (!t) return '';
    const [h, m] = t.split(':').map(Number);
    const ap = h >= 12 ? 'PM' : 'AM';
    return `${h % 12 || 12}:${String(m).padStart(2, '0')} ${ap}`;
}

function findOverlap(visits, start, end, excludeId = null) {
    const s1 = timeToMin(start), e1 = timeToMin(end);
    for (const v of visits) {
        if (v.Id === excludeId) continue;
        const s2 = timeToMin(v.Planned_Start_Time__c);
        const e2 = timeToMin(v.Planned_End_Time__c);
        if (s1 < e2 && e1 > s2) return v;
    }
    return null;
}

function badgeMeta(status) {
    if (status === 'Completed') return { label: 'EXECUTED', bg: '#bbf7d0', color: '#166534' };
    if (status === 'Missed')    return { label: 'MISSED',   bg: '#fecaca', color: '#991b1b' };
    return                             { label: 'PENDING',  bg: '#fef08a', color: '#854d0e' };
}

// ─── Component ────────────────────────────────────────────────────────────────
export default class BeatVisitPlanner extends LightningElement {

    // ── Reactive state ─────────────────────────────────────────────────────
    @track weekOffset   = 0;
    @track visitsByDate = {};     // { 'YYYY-MM-DD': [visit, ...] }
    @track showModal    = false;
    @track submitted    = false;
    @track toast        = null;

    // Modal state
    @track modalDay     = null;   // { dateStr, label, num }
    @track formData     = this._defaultForm();
    @track errors       = {};
    @track overlapWarning = '';

    // Colour assignment map
    _outletColors = {};
    _toastTimer   = null;

    // ── Static lists ────────────────────────────────────────────────────────
    get accounts()      { return MOCK_ACCOUNTS;   }
    get visitTypes()    { return VISIT_TYPES;      }
    get visitStatuses() { return VISIT_STATUSES;   }
    get missedReasons() { return MISSED_REASONS;   }

    // ── Computed: week ──────────────────────────────────────────────────────
    get weekDays() {
        const days = getWeekDays(this.weekOffset);
        return days.map(d => ({
            ...d,
            visits: this._buildVisitCards(d.dateStr)
        }));
    }

    get weekLabel() {
        return formatWeekLabel(getWeekDays(this.weekOffset));
    }

    // ── Computed: stats ─────────────────────────────────────────────────────
    get allVisits() {
        return Object.values(this.visitsByDate).flat();
    }
    get totalVisits()   { return this.allVisits.length; }
    get executedCount() { return this.allVisits.filter(v => v.Visit_Status__c === 'Completed').length; }
    get pendingCount()  { return this.allVisits.filter(v => v.Visit_Status__c === 'Planned').length;   }
    get missedCount()   { return this.allVisits.filter(v => v.Visit_Status__c === 'Missed').length;    }

    // ── Computed: submit button ─────────────────────────────────────────────
    get isSubmitDisabled() { return this.submitted || this.totalVisits === 0; }
    get submitBtnClass() {
        if (this.submitted)          return 'btn-submit submitted';
        if (this.totalVisits === 0)  return 'btn-submit disabled';
        return 'btn-submit active';
    }

    // ── Computed: modal ─────────────────────────────────────────────────────
    get modalDayLabel() {
        if (!this.modalDay) return '';
        const d = this.modalDay;
        const day = getWeekDays(this.weekOffset).find(x => x.dateStr === d.dateStr);
        if (!day) return '';
        const fmt = day.full.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        return `${fmt}, ${d.label[0]}${d.label.slice(1).toLowerCase()}`;
    }

    get isMissed()     { return this.formData.status === 'Missed'; }
    get notesLength()  { return (this.formData.notes || '').length; }

    get outletSelectClass() { return this.errors.outlet    ? 'err-border' : ''; }
    get startTimeClass()    { return this.errors.startTime ? 'err-border' : ''; }
    get endTimeClass()      { return this.errors.endTime   ? 'err-border' : ''; }
    get reasonSelectClass() { return this.errors.reason    ? 'err-border' : ''; }

    // ── Toast class ─────────────────────────────────────────────────────────
    get toastClass() {
        if (!this.toast) return '';
        const t = this.toast.type;
        return `toast ${t === 'error' ? 'toast-error' : t === 'info' ? 'toast-info' : 'toast-success'}`;
    }

    // ── Navigation ──────────────────────────────────────────────────────────
    prevWeek() { this.weekOffset -= 1; }
    nextWeek() { this.weekOffset += 1; }

    // ── Modal open/close ────────────────────────────────────────────────────
    openAddVisitModal() {
        // Default to current day or first day of week
        const today = new Date().toISOString().split('T')[0];
        const days  = getWeekDays(this.weekOffset);
        const day   = days.find(d => d.dateStr === today) || days[0];
        this._openModal(day);
    }

    openDayModal(event) {
        const { date, label, num } = event.currentTarget.dataset;
        this._openModal({ dateStr: date, label, num });
    }

    _openModal(day) {
        this.modalDay  = day;
        this.formData  = this._defaultForm();
        this.errors    = {};
        this.overlapWarning = '';
        this.showModal = true;
    }

    closeModal() {
        this.showModal = false;
        this.modalDay  = null;
        this.errors    = {};
        this.overlapWarning = '';
    }

    handleOverlayClick(event) {
        if (event.target === event.currentTarget) this.closeModal();
    }

    // ── Form handlers ───────────────────────────────────────────────────────
    handleOutletChange(e)  {
        this.formData = { ...this.formData, outlet: e.target.value };
        this.errors   = { ...this.errors, outlet: '' };
        this._checkOverlap();
    }
    handleVtypeChange(e)   { this.formData = { ...this.formData, visitType: e.target.value }; }
    handleStartChange(e)   {
        this.formData = { ...this.formData, startTime: e.target.value };
        this.errors   = { ...this.errors, startTime: '', endTime: '' };
        this._checkOverlap();
    }
    handleEndChange(e)     {
        this.formData = { ...this.formData, endTime: e.target.value };
        this.errors   = { ...this.errors, endTime: '' };
        this._checkOverlap();
    }
    handleStatusChange(e)  {
        this.formData = { ...this.formData, status: e.target.value, reason: '' };
        this.errors   = { ...this.errors, reason: '' };
    }
    handleReasonChange(e)  {
        this.formData = { ...this.formData, reason: e.target.value };
        this.errors   = { ...this.errors, reason: '' };
    }
    handleNotesChange(e)   { this.formData = { ...this.formData, notes: e.target.value }; }

    _checkOverlap() {
        const { startTime, endTime } = this.formData;
        if (!startTime || !endTime || !this.modalDay) { this.overlapWarning = ''; return; }
        const existing = this.visitsByDate[this.modalDay.dateStr] || [];
        const ov = findOverlap(existing, startTime, endTime);
        if (ov) {
            const name = MOCK_ACCOUNTS.find(a => a.Id === ov.Outlet1__c)?.Name || ov.outletName;
            this.overlapWarning = `This visit overlaps with ${name} ${to12(ov.Planned_Start_Time__c)} - ${to12(ov.Planned_End_Time__c)}`;
        } else {
            this.overlapWarning = '';
        }
    }

    // ── Save visit ──────────────────────────────────────────────────────────
    saveVisit() {
        const errs = this._validate();
        if (Object.keys(errs).length) { this.errors = errs; return; }

        const { outlet, visitType, startTime, endTime, status, reason, notes } = this.formData;
        const acc     = MOCK_ACCOUNTS.find(a => a.Id === outlet);
        const dateStr = this.modalDay.dateStr;
        const dayVisits = this.visitsByDate[dateStr] || [];
        const color   = this._getColor(outlet);

        const visit = {
            Id                           : `V-${Date.now()}`,
            Name                         : `VST-${Date.now().toString().slice(-5)}`,
            Outlet1__c            : outlet,
            Planned_Start_Time__c : startTime,
            Planned_End_Time__c   : endTime,
            Visit_Status__c       : status,
            Missed_Reason__c      : reason,
            Missed_Remarks__c     : notes,
            Visit_Date__c         : dateStr,
            Sequence__c           : dayVisits.length + 1,
            Beat__c               : 'BEAT-1',
            Sales_Rep__c          : 'John Doe',
            Is_Completed__c       : false,
            visitType,
            outletName : acc?.Name,
            outletCode : acc?.Outlet_Code__c,
            color,
        };

        // Immutable update
        const updated = { ...this.visitsByDate };
        updated[dateStr] = [...(updated[dateStr] || []), visit];
        this.visitsByDate = updated;

        this.closeModal();
        this._showToast(`\u2713 Visit saved \u2014 ${acc?.Name}`);
    }

    // ── Remove visit ────────────────────────────────────────────────────────
    removeVisit(event) {
        event.stopPropagation();
        const { id, date } = event.currentTarget.dataset;
        const updated = { ...this.visitsByDate };
        updated[date] = (updated[date] || []).filter(v => v.Id !== id);
        this.visitsByDate = updated;
        this._showToast('Visit removed', 'info');
    }

    // ── Submit beat plan ────────────────────────────────────────────────────
    submitBeatPlan() {
        if (this.totalVisits === 0) { this._showToast('Add at least one visit first', 'error'); return; }
        this.submitted = true;
        this._showToast('\uD83C\uDF89 Beat Plan submitted for approval!');
    }

    // ── Private helpers ─────────────────────────────────────────────────────
    _defaultForm() {
        return {
            outlet: '', visitType: 'Order Visit',
            startTime: '09:00', endTime: '10:00',
            status: 'Planned', reason: '', notes: ''
        };
    }

    _validate() {
        const { outlet, startTime, endTime, status, reason } = this.formData;
        const e = {};
        if (!outlet)                                   e.outlet    = 'Please select an outlet';
        if (!startTime)                                e.startTime = 'Required';
        if (!endTime)                                  e.endTime   = 'Required';
        if (startTime && endTime && startTime >= endTime) e.endTime = 'End must be after Start';
        if (status === 'Missed' && !reason)            e.reason    = 'Please select a reason';
        return e;
    }

    _getColor(outletId) {
        if (this._outletColors[outletId] !== undefined) return PALETTES[this._outletColors[outletId]];
        const idx = Object.keys(this._outletColors).length % PALETTES.length;
        this._outletColors[outletId] = idx;
        return PALETTES[idx];
    }

    _buildVisitCards(dateStr) {
        const visits = (this.visitsByDate[dateStr] || [])
            .slice()
            .sort((a, b) => (a.Planned_Start_Time__c || '').localeCompare(b.Planned_Start_Time__c || ''));

        return visits.map(v => {
            const badge = badgeMeta(v.Visit_Status__c);
            return {
                ...v,
                timeRange  : `${to12(v.Planned_Start_Time__c)} \u2013 ${to12(v.Planned_End_Time__c)}`,
                cardClass  : 'visit-card',
                cardStyle  : `background:${v.color};`,
                badgeClass : 'status-badge',
                badgeStyle : `background:${badge.bg};color:${badge.color};`,
                badgeLabel : badge.label,
            };
        });
    }

    _showToast(msg, type = 'success') {
        if (this._toastTimer) clearTimeout(this._toastTimer);
        this.toast = { msg, type };
        this._toastTimer = setTimeout(() => { this.toast = null; }, 3200);
    }
}