import { LightningElement, track, wire } from 'lwc';
import { refreshApex }         from '@salesforce/apex';
import getMyPolicy             from '@salesforce/apex/PolicyAllowanceController.getMyPolicy';
import savePolicy              from '@salesforce/apex/PolicyAllowanceController.savePolicy';
import getTeamAllowances       from '@salesforce/apex/PolicyAllowanceController.getTeamAllowances';
import saveAllowance           from '@salesforce/apex/PolicyAllowanceController.saveAllowance';

const CAP_FIELD_DEFS = [
    { key: 'travelCap',         label: 'Travel' },
    { key: 'foodCap',           label: 'Food & Beverages' },
    { key: 'marketExecCap',     label: 'Market Execution Expenses' },
    { key: 'communicationsCap', label: 'Communications Expenses' },
    { key: 'miscCap',           label: 'Miscellaneous Expenses' },
    { key: 'otherCap',          label: 'Other' }
];

const MONTH_NAMES = ['January','February','March','April','May','June',
                     'July','August','September','October','November','December'];

export default class ManagerPolicySetup extends LightningElement {

    // ── Policy state ─────────────────────────────────
    @track isPolicyLoading  = true;
    @track isSavingPolicy   = false;
    @track policySaveSuccess= false;
    @track policyForm = {
        policyId        : null,
        travelCap       : null,
        foodCap         : null,
        marketExecCap   : null,
        communicationsCap: null,
        miscCap         : null,
        otherCap        : null,
        warnThresholdPct: 80
    };
    _wiredPolicyResult;

    // ── Allowance state ──────────────────────────────
    @track isAllowancesLoading = true;
    @track _currentYear;
    @track _currentMonth;   // 1-based
    @track _repInputs = {}; // userId → { amount, allowanceId, isSaving }
    _wiredAllowancesResult;

    connectedCallback() {
        const now = new Date();
        this._currentYear  = now.getFullYear();
        this._currentMonth = now.getMonth() + 1;
    }

    // ── Wire: policy ─────────────────────────────────
    @wire(getMyPolicy)
    wiredPolicy(result) {
        this._wiredPolicyResult = result;
        this.isPolicyLoading = false;
        if (result.data) {
            const d = result.data;
            this.policyForm = {
                policyId        : d.policyId        || null,
                travelCap       : d.travelCap        || null,
                foodCap         : d.foodCap          || null,
                marketExecCap   : d.marketExecCap    || null,
                communicationsCap: d.communicationsCap|| null,
                miscCap         : d.miscCap          || null,
                otherCap        : d.otherCap         || null,
                warnThresholdPct: d.warnThresholdPct != null ? d.warnThresholdPct : 80
            };
        }
    }

    // ── Wire: allowances ─────────────────────────────
    @wire(getTeamAllowances, { monthYear: '$currentMonthKey' })
    wiredAllowances(result) {
        this._wiredAllowancesResult = result;
        this.isAllowancesLoading = false;
        if (result.data) {
            // Sync input state with loaded data — preserve any unsaved edits
            const next = { ...this._repInputs };
            result.data.forEach(rep => {
                if (!next[rep.userId]) {
                    next[rep.userId] = {
                        amount      : rep.allowanceAmount,
                        allowanceId : rep.allowanceId,
                        isSaving    : false
                    };
                } else {
                    next[rep.userId].allowanceId = rep.allowanceId; // update id if newly saved
                }
            });
            this._repInputs = next;
        }
    }

    // ── Getters ──────────────────────────────────────

    get currentMonthKey() {
        if (!this._currentYear || !this._currentMonth) return null;
        return this._currentYear + '-' +
               String(this._currentMonth).padStart(2, '0');
    }

    get currentMonthLabel() {
        if (!this._currentYear || !this._currentMonth) return '';
        return MONTH_NAMES[this._currentMonth - 1] + ' ' + this._currentYear;
    }

    get isCurrentMonth() {
        const now = new Date();
        return this._currentYear  === now.getFullYear() &&
               this._currentMonth === now.getMonth() + 1;
    }

    get capFields() {
        return CAP_FIELD_DEFS.map(f => ({
            ...f,
            value: this.policyForm[f.key] != null ? this.policyForm[f.key] : ''
        }));
    }

    get repRows() {
        if (!this._wiredAllowancesResult?.data) return [];
        return this._wiredAllowancesResult.data.map(rep => {
            const inp      = this._repInputs[rep.userId] || {};
            const amount   = inp.amount != null ? inp.amount : rep.allowanceAmount;
            const spent    = rep.spentAmount || 0;
            const pct      = (amount > 0) ? Math.min((spent / amount * 100), 100) : 0;
            const barClass = pct >= 100 ? 'ps-bar-fill ps-bar-fill--over'
                           : pct >= 80  ? 'ps-bar-fill ps-bar-fill--warn'
                           :              'ps-bar-fill';
            return {
                userId         : rep.userId,
                repName        : rep.repName,
                allowanceId    : inp.allowanceId || rep.allowanceId,
                allowanceAmount: amount,
                spentFormatted : this._fmt(spent),
                spentPct       : rep.spentPct != null ? rep.spentPct : 0,
                barClass,
                barStyle       : 'width:' + Math.min(pct, 100).toFixed(1) + '%',
                isSaving       : inp.isSaving || false
            };
        });
    }

    get noTeam() {
        return !this.isAllowancesLoading &&
               this._wiredAllowancesResult?.data?.length === 0;
    }

    // ── Policy handlers ──────────────────────────────

    handleCapInput(event) {
        const key = event.target.dataset.key;
        const val = event.target.value !== '' ? parseFloat(event.target.value) : null;
        this.policyForm = { ...this.policyForm, [key]: val };
    }

    async handleSavePolicy() {
        this.isSavingPolicy   = true;
        this.policySaveSuccess = false;
        try {
            const newId = await savePolicy({
                policyId        : this.policyForm.policyId,
                travelCap       : this.policyForm.travelCap,
                foodCap         : this.policyForm.foodCap,
                marketExecCap   : this.policyForm.marketExecCap,
                communicationsCap: this.policyForm.communicationsCap,
                miscCap         : this.policyForm.miscCap,
                otherCap        : this.policyForm.otherCap,
                warnThresholdPct: this.policyForm.warnThresholdPct
            });
            this.policyForm = { ...this.policyForm, policyId: newId };
            this.policySaveSuccess = true;
            refreshApex(this._wiredPolicyResult);
            setTimeout(() => { this.policySaveSuccess = false; }, 3000);
        } catch (e) {
            console.error('Policy save error', e);
        } finally {
            this.isSavingPolicy = false;
        }
    }

    // ── Allowance handlers ───────────────────────────

    handlePrevMonth() {
        if (this._currentMonth === 1) {
            this._currentMonth = 12;
            this._currentYear--;
        } else {
            this._currentMonth--;
        }
        this._repInputs = {};
        this.isAllowancesLoading = true;
    }

    handleNextMonth() {
        if (this.isCurrentMonth) return;
        if (this._currentMonth === 12) {
            this._currentMonth = 1;
            this._currentYear++;
        } else {
            this._currentMonth++;
        }
        this._repInputs = {};
        this.isAllowancesLoading = true;
    }

    handleAllowanceInput(event) {
        const userId = event.target.dataset.userid;
        const allowanceId = event.target.dataset.allowanceid;
        const val  = event.target.value !== '' ? parseFloat(event.target.value) : null;
        const curr = this._repInputs[userId] || {};
        this._repInputs = {
            ...this._repInputs,
            [userId]: { ...curr, amount: val, allowanceId, isSaving: false }
        };
    }

    async handleSaveAllowance(event) {
        const userId = event.currentTarget.dataset.userid;
        const inp    = this._repInputs[userId] || {};
        if (inp.amount == null) return;

        this._repInputs = {
            ...this._repInputs,
            [userId]: { ...inp, isSaving: true }
        };

        try {
            const newId = await saveAllowance({
                allowanceId : inp.allowanceId || null,
                repId       : userId,
                monthYear   : this.currentMonthKey,
                amount      : inp.amount
            });
            this._repInputs = {
                ...this._repInputs,
                [userId]: { ...inp, allowanceId: newId, isSaving: false }
            };
            refreshApex(this._wiredAllowancesResult);
        } catch (e) {
            console.error('Allowance save error', e);
            this._repInputs = {
                ...this._repInputs,
                [userId]: { ...inp, isSaving: false }
            };
        }
    }

    // ── Helpers ──────────────────────────────────────
    _fmt(val) {
        if (val == null) return '0';
        return new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 }).format(val);
    }
}