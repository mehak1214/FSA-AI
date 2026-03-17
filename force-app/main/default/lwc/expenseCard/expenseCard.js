import { LightningElement, api, track } from 'lwc';

const TYPE_ICONS = {
    'Travel'                    : 'utility:car',
    'Food & Beverages'          : 'utility:food_and_drink',
    'Market Execution Expenses' : 'utility:product_consumed',
    'Communications Expenses'   : 'utility:phone_portrait',
    'Miscellaneous Expenses'    : 'utility:all',
    'Other'                     : 'utility:question'
};

const STATUS_CLASSES = {
    'Draft'    : 'status-badge status-draft',
    'Submitted': 'status-badge status-submitted',
    'Approved' : 'status-badge status-approved',
    'Rejected' : 'status-badge status-rejected',
    'Paid'     : 'status-badge status-paid'
};

export default class ExpenseCard extends LightningElement {
    @api expense = {};

    get formattedAmount() {
        if (this.expense.amount == null) return '—';
        return new Intl.NumberFormat('en-IN', {
            style   : 'currency',
            currency: 'INR',
            maximumFractionDigits: 2
        }).format(this.expense.amount);
    }

    get formattedDate() {
        if (!this.expense.expenseDate) return '—';
        const d = new Date(this.expense.expenseDate + 'T00:00:00');
        return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
    }

    get typeIcon() {
        return TYPE_ICONS[this.expense.expenseType] || 'utility:money';
    }

    get statusBadgeClass() {
        return STATUS_CLASSES[this.expense.status] || 'status-badge status-draft';
    }

    get cardClass() {
        return `expense-card status-border-${(this.expense.status || 'draft').toLowerCase().replace(/ /g, '-')}`;
    }

    get truncatedDescription() {
        const desc = this.expense.description || '';
        return desc.length > 80 ? desc.substring(0, 80) + '…' : desc;
    }

    get isDraft() {
        return this.expense.status === 'Draft';
    }

    get isRejected() {
        return this.expense.status === 'Rejected';
    }

    get rejectionReasonDisplay() {
        const reason = this.expense.rejectionReason;
        if (!reason) return 'No reason provided.';
        return reason.length > 100 ? reason.substring(0, 100) + '…' : reason;
    }

    handleCardClick() {
        this.dispatchEvent(new CustomEvent('cardclick', {
            detail : { expenseId: this.expense.id },
            bubbles: true,
            composed: true
        }));
    }

    handleDelete(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('deleteexpense', {
            detail : { expenseId: this.expense.id },
            bubbles: true,
            composed: true
        }));
    }

    handleSubmit(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('submitexpense', {
            detail : { expenseId: this.expense.id },
            bubbles: true,
            composed: true
        }));
    }

    stopPropagation(event) {
        event.stopPropagation();
    }
}