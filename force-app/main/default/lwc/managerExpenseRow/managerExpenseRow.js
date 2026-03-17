import { LightningElement, api } from 'lwc';

const STATUS_CLASSES = {
    'Draft'    : 'status-pill pill-draft',
    'Submitted': 'status-pill pill-submitted',
    'Approved' : 'status-pill pill-approved',
    'Rejected' : 'status-pill pill-rejected',
    'Paid'     : 'status-pill pill-paid'
};

// Statuses where individual approve/reject buttons should show
const ACTIONABLE_STATUSES = new Set(['Draft', 'Submitted']);

export default class ManagerExpenseRow extends LightningElement {
    @api expense = {};

    get formattedDate() {
        if (!this.expense.expenseDate) return '—';
        const d = new Date(this.expense.expenseDate + 'T00:00:00');
        return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
    }

    get formattedAmount() {
        if (this.expense.amount == null) return '—';
        return new Intl.NumberFormat('en-IN', {
            style: 'currency', currency: 'INR', maximumFractionDigits: 2
        }).format(this.expense.amount);
    }

    get truncatedDesc() {
        const d = this.expense.description || '';
        return d.length > 60 ? d.substring(0, 60) + '…' : d;
    }

    get statusClass() {
        return STATUS_CLASSES[this.expense.status] || 'status-pill pill-draft';
    }

    get rowClass() {
        return `expense-row status-row-${(this.expense.status || '').toLowerCase()}`;
    }

    get isActionable() {
        return ACTIONABLE_STATUSES.has(this.expense.status);
    }

    handleApprove() {
        this.dispatchEvent(new CustomEvent('approveexpense', {
            detail  : { expenseId: this.expense.id },
            bubbles : true,
            composed: true
        }));
    }

    handleReject() {
        this.dispatchEvent(new CustomEvent('rejectexpense', {
            detail  : { expenseId: this.expense.id },
            bubbles : true,
            composed: true
        }));
    }
}