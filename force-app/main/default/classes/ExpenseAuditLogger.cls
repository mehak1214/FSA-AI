/**
 * ExpenseAuditLogger
 * Centralised utility for writing Expense_Audit_Log__c records.
 *
 * Design principles:
 *  - Called explicitly from Apex action methods (not from triggers), so each
 *    log entry knows EXACTLY what action was intended — no field-diff inference.
 *  - All writes are fire-and-forget: logged with Database.insert(log, false)
 *    so an audit failure NEVER rolls back the main business transaction.
 *  - The class is `without sharing` so audit logs are always written regardless
 *    of the running user's record visibility.
 *  - All public methods are static — no instantiation needed.
 *
 * Usage:
 *   ExpenseAuditLogger.logExpenseSubmitted(expenseId, reportId);
 *   ExpenseAuditLogger.logReportSubmitted(reportId, expenseCount);
 *   ExpenseAuditLogger.logExpenseApproved(expenseId, reportId);
 *   ExpenseAuditLogger.logExpenseRejected(expenseId, reportId, reason);
 *   ExpenseAuditLogger.logReportStatusChanged(reportId, oldStatus, newStatus);
 */
public without sharing class ExpenseAuditLogger {

    // ─────────────────────────────────────────────
    // PUBLIC API
    // ─────────────────────────────────────────────

    /** Individual expense submitted by the sales rep */
    public static void logExpenseSubmitted(Id expenseId, Id reportId) {
        write(new Expense_Audit_Log__c(
            Action__c          = 'Expense Submitted',
            Expense__c         = expenseId,
            Expense_Report__c  = reportId,
            Old_Status__c      = 'Draft',
            New_Status__c      = 'Submitted',
            Notes__c           = 'Individual expense submitted by sales rep.'
        ));
    }

    /** Rejected expense resubmitted — reset to Draft for editing */
    public static void logResubmit(Id expenseId, Id reportId) {
        write(new Expense_Audit_Log__c(
            Action__c          = 'Expense Resubmitted',
            Expense__c         = expenseId,
            Expense_Report__c  = reportId,
            Old_Status__c      = 'Rejected',
            New_Status__c      = 'Draft',
            Notes__c           = 'Sales rep chose to resubmit after rejection. Expense reset to Draft for editing.'
        ));
    }

    /** Rejected expense abandoned by the sales rep */
    public static void logAbandon(Id expenseId, Id reportId) {
        write(new Expense_Audit_Log__c(
            Action__c          = 'Expense Abandoned',
            Expense__c         = expenseId,
            Expense_Report__c  = reportId,
            Old_Status__c      = 'Rejected',
            New_Status__c      = 'Abandoned',
            Notes__c           = 'Sales rep chose to abandon expense after rejection.'
        ));
    }

    /** Full report submitted (all Draft expenses set to Submitted in bulk) */
    public static void logReportSubmitted(Id reportId, Integer expenseCount) {
        write(new Expense_Audit_Log__c(
            Action__c          = 'Report Submitted',
            Expense_Report__c  = reportId,
            Old_Status__c      = 'Draft',
            New_Status__c      = 'Submitted',
            Notes__c           = expenseCount + ' expense(s) submitted with this report.'
        ));
    }

    /** Single expense approved by the manager */
    public static void logExpenseApproved(Id expenseId, Id reportId) {
        write(new Expense_Audit_Log__c(
            Action__c          = 'Expense Approved',
            Expense__c         = expenseId,
            Expense_Report__c  = reportId,
            Old_Status__c      = 'Submitted',
            New_Status__c      = 'Approved'
        ));
    }

    /** Single expense rejected by the manager */
    public static void logExpenseRejected(Id expenseId, Id reportId, String reason) {
        write(new Expense_Audit_Log__c(
            Action__c          = 'Expense Rejected',
            Expense__c         = expenseId,
            Expense_Report__c  = reportId,
            Old_Status__c      = 'Submitted',
            New_Status__c      = 'Rejected',
            Rejection_Reason__c = reason
        ));
    }

    /** Bulk approve/reject — one log entry per expense */
    public static void logBulkExpenseStatusChange(
            List<Expense__c> expenses,
            String           newStatus,
            Id               reportId,
            String           rejectionReason) {

        List<Expense_Audit_Log__c> logs = new List<Expense_Audit_Log__c>();
        String action = (newStatus == 'Approved') ? 'Expense Approved' : 'Expense Rejected';

        for (Expense__c e : expenses) {
            Expense_Audit_Log__c log = new Expense_Audit_Log__c(
                Action__c          = action,
                Expense__c         = e.Id,
                Expense_Report__c  = reportId,
                Old_Status__c      = e.Status__c,
                New_Status__c      = newStatus,
                Performed_By__c    = UserInfo.getUserId(),
                Timestamp__c       = Datetime.now()
            );
            if (newStatus == 'Rejected' && String.isNotBlank(rejectionReason)) {
                log.Rejection_Reason__c = rejectionReason;
            }
            logs.add(log);
        }

        if (!logs.isEmpty()) {
            Database.insert(logs, false); // false = partial success; never block main tx
        }
    }

    /** Report-level status transition (fired from syncReportStatus) */
    public static void logReportStatusChanged(Id reportId, String oldStatus, String newStatus) {
        write(new Expense_Audit_Log__c(
            Action__c          = 'Report Status Changed',
            Expense_Report__c  = reportId,
            Old_Status__c      = oldStatus,
            New_Status__c      = newStatus,
            Notes__c           = 'Report status auto-synced from expense statuses.'
        ));
    }

    // ─────────────────────────────────────────────
    // PRIVATE HELPERS
    // ─────────────────────────────────────────────

    private static void write(Expense_Audit_Log__c log) {
        log.Performed_By__c = UserInfo.getUserId();
        log.Timestamp__c    = Datetime.now();
        Database.insert(log, false); // never throw — audit must not break main tx
    }
}