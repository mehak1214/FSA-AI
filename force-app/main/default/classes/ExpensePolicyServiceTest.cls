@IsTest
private class ExpensePolicyServiceTest {

    @IsTest
    static void testExpensePolicyEvaluation() {
        User manager = TestDataFactory.getRunningUser();
        User rep = TestDataFactory.createUser('RepPolicy', 'reppol', manager.Id);
        Expense_Policy__c policy = TestDataFactory.createExpensePolicy(manager, 100, 20);
        String monthYear = Date.today().year() + '-' + String.valueOf(Date.today().month()).leftPad(2, '0');
        TestDataFactory.createRepAllowance(rep, monthYear, 200);

        Test.startTest();
        System.runAs(rep) {
            ExpensePolicyService.PolicyCheckResult ok = ExpensePolicyService.evaluate(rep.Id, 'Travel', 50, String.valueOf(Date.today()), null);
            System.assertEquals(false, ok.hasBreach);

            ExpensePolicyService.PolicyCheckResult warn = ExpensePolicyService.evaluate(rep.Id, 'Travel', 120, String.valueOf(Date.today()), null);
            System.assertEquals(true, warn.hasBreach);
            System.assertEquals('Type Cap', warn.breachType);

            try {
                ExpensePolicyService.evaluate(rep.Id, 'Travel', 160, String.valueOf(Date.today()), null);
                System.assert(false, 'Expected hard block exception');
            } catch (AuraHandledException e) {
                System.assert(e.getMessage().contains('exceeds the hard limit'));
            }

            ExpensePolicyService.PolicyCheckResult allowanceWarn = ExpensePolicyService.evaluate(rep.Id, 'Food & Beverages', 180, String.valueOf(Date.today()), null);
            System.assert(allowanceWarn.hasBreach);
            System.assertNotEquals(null, allowanceWarn.breachType);
        }
        Test.stopTest();
    }
}