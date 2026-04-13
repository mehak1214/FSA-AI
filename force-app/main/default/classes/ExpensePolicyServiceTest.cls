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
                // AuraHandledException.getMessage() returns 'Script-thrown exception'
                // in test context — catching the exception type is sufficient proof
                // that the hard-block code path fired correctly.
                System.assert(true, 'Hard block AuraHandledException was thrown as expected');
            }

            // To trigger a pure allowance breach we need usedSoFar + newAmount > allowance(200)
            // without hitting the per-type hard block (cap=100, hard limit=150).
            // Insert a prior Submitted expense of 160 → usedSoFar=160.
            // Then evaluate amount=50 (Travel): projected=210 > 200 → allowance soft warn.
            // 50 < 100 (Travel cap) so no type breach; 210 < 300 so no hard block.
            Expense_Report__c report = new Expense_Report__c(
                Sales_Rep__c  = rep.Id,
                Report_Date__c = Date.today(),
                Status__c      = 'Submitted'
            );
            insert report;
            Expense__c priorExp = new Expense__c(
                Sales_Rep__c      = rep.Id,
                Expense_Report__c = report.Id,
                Expense_Date__c   = Date.today(),
                Amount__c         = 160,
                Expense_Type__c   = 'Travel',
                Status__c         = 'Submitted',
                Description__c    = 'Prior spend'
            );
            insert priorExp;

            ExpensePolicyService.PolicyCheckResult allowanceWarn = ExpensePolicyService.evaluate(rep.Id, 'Travel', 50, String.valueOf(Date.today()), null);
            System.assert(allowanceWarn.hasBreach, 'Expected allowance breach when projected total exceeds allowance');
            System.assertEquals('Monthly Allowance', allowanceWarn.breachType, 'Breach type should be Monthly Allowance');
        }
        Test.stopTest();
    }
}