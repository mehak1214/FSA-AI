import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { enqueue, getStorageStatus } from 'c/offlineQueueForExpenses';

const EXPENSE_TYPES = [
    'Travel',
    'Food & Beverages',
    'Market Execution Expenses',
    'Communications Expenses',
    'Miscellaneous Expenses',
    'Other'
];

const EMPTY_FORM = {
    amount     : '',
    expenseType: '',
    expenseDate: new Date().toISOString().slice(0, 10),
    description: ''
};

export default class AddExpenseModal extends LightningElement {

    @api isOpen = false;
    @track formData = { ...EMPTY_FORM };
    @track errors   = {};
    @track isSaving = false;

    get expenseTypeOptions() {
        return EXPENSE_TYPES.map(t => ({
            label   : t,
            value   : t,
            selected: this.formData.expenseType === t
        }));
    }

    handleInput(event) {
        const field = event.target.dataset.field;
        this.formData = { ...this.formData, [field]: event.target.value };
        if (this.errors[field]) {
            const errs = { ...this.errors };
            delete errs[field];
            this.errors = errs;
        }
    }

    validate() {
        const errs = {};
        if (!this.formData.amount || Number(this.formData.amount) <= 0) {
            errs.amount = 'Please enter a valid amount greater than 0.';
        }
        if (!this.formData.expenseType) {
            errs.expenseType = 'Please select an expense type.';
        }
        if (!this.formData.expenseDate) {
            errs.expenseDate = 'Please select a date.';
        }
        this.errors = errs;
        return Object.keys(errs).length === 0;
    }

    // ── Save ───────────────────────────────────────────────────────────────────
    // The modal's ONLY job is to write to the offline queue.
    // It never calls Apex directly — all syncing is handled by expenseList,
    // which runs after save (online) or when connectivity is restored (offline).
    // This eliminates the race condition that caused double-saves.
    // ──────────────────────────────────────────────────────────────────────────
    handleSave() {
        if (!this.validate()) return;

        this.isSaving = true;

        // ── Step 1: Pre-write storage warning at 80% ──────
        const storageStatus = getStorageStatus();
        if (storageStatus.isNearlyFull) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Storage Nearly Full',
                message: `Device storage is ${storageStatus.usedPercent}% full (${storageStatus.usedKB} KB used). Please sync your pending expenses soon.`,
                variant: 'warning',
                mode   : 'sticky'
            }));
        }

        // ── Step 2: Write to queue ────────────────────────
        const result = enqueue({
            amount     : parseFloat(this.formData.amount),
            expenseType: this.formData.expenseType,
            expenseDate: this.formData.expenseDate,
            description: this.formData.description
        });

        if (!result.ok) {
            // Storage full or write error — keep modal open so rep doesn't lose data
            this.dispatchEvent(new ShowToastEvent({
                title  : result.reason === 'full' ? 'Storage Full' : 'Save Failed',
                message: result.message,
                variant: 'error',
                mode   : 'sticky'
            }));
            this.isSaving = false;
            return;
        }

        // ── Step 3: Notify parent to attempt sync ─────────
        // expenseList will try Apex immediately if online,
        // or wait for the `online` event if not.
        this.dispatchEvent(new CustomEvent('expensequeued', {
            bubbles : true,
            composed: true
        }));

        this.resetAndClose();
    }

    handleClose() {
        this.resetAndClose();
    }

    handleBackdropClick() {
        this.resetAndClose();
    }

    resetAndClose() {
        this.formData = { ...EMPTY_FORM };
        this.errors   = {};
        this.isSaving = false;
        this.dispatchEvent(new CustomEvent('close', {
            bubbles : true,
            composed: true
        }));
    }
}