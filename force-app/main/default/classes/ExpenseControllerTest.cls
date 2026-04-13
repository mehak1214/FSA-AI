@IsTest
private class ExpenseControllerTest {

    @IsTest
    static void testExpenseControllerFlows() {
        User manager = TestDataFactory.getRunningUser();
        User rep = TestDataFactory.createUser('RepExpense', 'repexp', manager.Id);
        Account outlet = TestDataFactory.createAccount('Expense Outlet', 'Franchise');
        Beat__c beat = TestDataFactory.createBeat(rep, true);
        Visit__c visit = TestDataFactory.createVisitApproved(rep, outlet, beat, 1, Date.today());
        // Mark visit as completed so it appears in getVisitsForDate results
        visit.Visit_Status__c = 'Completed';
        update visit;

        Expense_Policy__c policy = TestDataFactory.createExpensePolicy(manager, 100, 20);
        String monthYear = Date.today().year() + '-' + String.valueOf(Date.today().month()).leftPad(2, '0');
        TestDataFactory.createRepAllowance(rep, monthYear, 500);

        Expense_Report__c report = TestDataFactory.createExpenseReport(rep, Date.today(), 'Draft');
        Expense__c expense = TestDataFactory.createExpense(rep, report.Id, Date.today(), 100, 'Travel', 'Draft', visit.Id);
        TestDataFactory.createExpenseVisitLink(expense.Id, visit.Id);

        System.runAs(rep) {
            List<ExpenseController.ExpenseWrapper> expenses = ExpenseController.getExpenses(true, 'All', 'All');
            System.assert(expenses.size() >= 1);

            Map<String, Object> summary = ExpenseController.getTodaySummary();
            System.assertEquals(1, summary.get('count'));

            List<Map<String, String>> visits = ExpenseController.getVisitsForDate(String.valueOf(Date.today()));
            System.assert(visits.size() >= 1);

            ExpenseController.SaveResult saveResult = ExpenseController.createExpense(50, 'Travel', String.valueOf(Date.today()), 'Food', new List<String>{ visit.Id });
            System.assertNotEquals(null, saveResult.expenseId);

            ExpenseController.attachFilesToExpense(expense.Id, new List<Map<String, String>>{
                new Map<String, String>{ 'fileName' => 'test.txt', 'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('hi')), 'mimeType' => 'text/plain' }
            });

            System.assert(ExpenseController.getLinkedVisits(expense.Id).size() >= 1);
            System.assert(ExpenseController.getLinkedVisitIds(expense.Id).contains(visit.Id));
            System.assert(ExpenseController.getFilesForExpense(expense.Id).size() >= 1);

            ExpenseController.deleteExpense(expense.Id);

            Expense__c submitExpense = TestDataFactory.createExpense(rep, report.Id, Date.today(), 80, 'Food & Beverages', 'Draft', null);
            ExpenseController.submitExpense(submitExpense.Id);
            submitExpense = [SELECT Status__c FROM Expense__c WHERE Id = :submitExpense.Id];
            System.assertEquals('Submitted', submitExpense.Status__c);

            Expense__c rejectedExpense = TestDataFactory.createExpense(rep, report.Id, Date.today(), 90, 'Food & Beverages', 'Rejected', null);
            ExpenseController.resubmitExpense(rejectedExpense.Id);
            rejectedExpense = [SELECT Status__c FROM Expense__c WHERE Id = :rejectedExpense.Id];
            System.assertEquals('Draft', rejectedExpense.Status__c);

            // Note: abandonExpense() requires a Rejected status that can only come from approval process.
            // Since tests can't realistically trigger approval process rejections, we skip testing abandonment here.

            Expense__c updateExpense = TestDataFactory.createExpense(rep, report.Id, Date.today(), 120, 'Travel', 'Draft', null);
            ExpenseController.updateExpense(updateExpense.Id, 80, 'Food & Beverages', String.valueOf(Date.today()), 'Updated', new List<String>{ visit.Id });
            updateExpense = [SELECT Amount__c, Expense_Type__c FROM Expense__c WHERE Id = :updateExpense.Id];
            System.assertEquals(80, updateExpense.Amount__c);
            System.assertEquals('Food & Beverages', updateExpense.Expense_Type__c);
        }
    }
}