@IsTest
private class ExpenseAuditLoggerTest {

    @IsTest
    static void testExpenseAuditLogging() {
        User manager = TestDataFactory.getRunningUser();
        User rep = TestDataFactory.createUser('RepAudit', 'repaudit', manager.Id);
        Expense_Report__c report = TestDataFactory.createExpenseReport(rep, Date.today(), 'Draft');
        Expense__c expense = TestDataFactory.createExpense(rep, report.Id, Date.today(), 100, 'Travel', 'Draft', null);

        Integer beforeCount = [SELECT count() FROM Expense_Audit_Log__c];

        ExpenseAuditLogger.logExpenseSubmitted(expense.Id, report.Id);
        ExpenseAuditLogger.logResubmit(expense.Id, report.Id);
        ExpenseAuditLogger.logAbandon(expense.Id, report.Id);
        ExpenseAuditLogger.logReportSubmitted(report.Id, 1);
        ExpenseAuditLogger.logExpenseApproved(expense.Id, report.Id);
        ExpenseAuditLogger.logExpenseRejected(expense.Id, report.Id, 'Incorrect amount');
        ExpenseAuditLogger.logReportStatusChanged(report.Id, 'Draft', 'Submitted');

        List<Expense__c> expenses = new List<Expense__c>{expense};
        ExpenseAuditLogger.logBulkExpenseStatusChange(expenses, 'Approved', report.Id, null);

        System.assert([SELECT count() FROM Expense_Audit_Log__c] > beforeCount);
    }
}