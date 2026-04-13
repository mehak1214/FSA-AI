@IsTest
private class ManagerExpenseControllerTest {

    @IsTest
    static void testManagerExpenseControllerFlows() {
        User manager = TestDataFactory.getRunningUser();
        User rep = TestDataFactory.createUser('RepManagerExpense', 'repme', manager.Id);
        Test.startTest();
        System.runAs(manager) {
            Expense_Report__c report = TestDataFactory.createExpenseReport(rep, Date.today(), 'Submitted');
            Expense__c exp1 = TestDataFactory.createExpense(rep, report.Id, Date.today(), 100, 'Travel', 'Submitted', null);
            Expense__c exp2 = TestDataFactory.createExpense(rep, report.Id, Date.today(), 150, 'Food & Beverages', 'Draft', null);
            TestDataFactory.createExpenseVisitLink(exp1.Id, null);
            ExpenseController.attachFilesToExpense(exp1.Id, new List<Map<String, String>>{
                new Map<String, String>{ 'fileName' => 'mge.csv', 'base64Data' => EncodingUtil.base64Encode(Blob.valueOf('x')), 'mimeType' => 'text/csv' }
            });

            List<ManagerExpenseController.ExpenseReportWrapper> wrapperList = ManagerExpenseController.getPendingApprovalReports();
            System.assert(wrapperList.size() >= 1);

            ManagerExpenseController.ReportDetailWrapper detail = ManagerExpenseController.getReportDetail(report.Id);
            System.assertEquals(report.Id, detail.report.id);
            System.assert(detail.expenses.size() >= 1);

            ManagerExpenseController.bulkUpdateExpenseStatus(report.Id, 'Submitted', 'Approved', null);
            List<Expense__c> updated = [SELECT Status__c FROM Expense__c WHERE Expense_Report__c = :report.Id];
            System.assert(updated.size() >= 1);

            Expense__c exp3 = TestDataFactory.createExpense(rep, report.Id, Date.today(), 80, 'Travel', 'Draft', null);
            ManagerExpenseController.updateExpenseStatus(exp3.Id, 'Approved', null);
            exp3 = [SELECT Status__c FROM Expense__c WHERE Id = :exp3.Id];
            System.assertEquals('Approved', exp3.Status__c);
        }
        Test.stopTest();
    }
}