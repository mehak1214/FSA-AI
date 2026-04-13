@IsTest
private class AccountStatusServiceTest {

    private static Account createTestAccount(String status) {
        Account acc = new Account(
            Name = 'Account Status Service Test',
            OutletStatus__c = status
        );
        insert acc;
        return acc;
    }

    @IsTest
    static void testValidateTransitionAllowsDraftForNewRecord() {
        Test.startTest();
        AccountStatusService.validateTransition(null, AccountStatusService.STATUS_DRAFT);
        Test.stopTest();
    }

    @IsTest
    static void testValidateTransitionRejectsNonDraftForNewRecord() {
        try {
            AccountStatusService.validateTransition(null, AccountStatusService.STATUS_SUBMITTED);
            System.assert(false, 'Expected AuraHandledException for new account with non-Draft status');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('New accounts must start in Draft status.'), e.getMessage());
        }
    }

    @IsTest
    static void testValidateTransitionAllowsSameStatusSave() {
        Test.startTest();
        AccountStatusService.validateTransition(AccountStatusService.STATUS_ACTIVE, AccountStatusService.STATUS_ACTIVE);
        Test.stopTest();
    }

    @IsTest
    static void testValidateTransitionRejectsInvalidTransition() {
        try {
            AccountStatusService.validateTransition(AccountStatusService.STATUS_DRAFT, AccountStatusService.STATUS_ACTIVE);
            System.assert(false, 'Expected AuraHandledException for invalid Draft→Active transition');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('Invalid status transition'), e.getMessage());
        }
    }

    @IsTest
    static void testValidateTransitionAllowsValidTransition() {
        Test.startTest();
        AccountStatusService.validateTransition(AccountStatusService.STATUS_REJECTED, AccountStatusService.STATUS_ABANDONED);
        Test.stopTest();
    }

    @IsTest
    static void testTransitionStatusRejectsInvalidArguments() {
        try {
            AccountStatusService.transitionStatus(null, AccountStatusService.STATUS_SUBMITTED);
            System.assert(false, 'Expected AuraHandledException for null accountId');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('accountId and newStatus are required.'), e.getMessage());
        }

        Account accountRecord = createTestAccount(AccountStatusService.STATUS_DRAFT);
        try {
            AccountStatusService.transitionStatus(accountRecord.Id, '');
            System.assert(false, 'Expected AuraHandledException for blank newStatus');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('accountId and newStatus are required.'), e.getMessage());
        }
    }

    @IsTest
    static void testSubmitForApprovalRejectsNullAccountId() {
        try {
            AccountStatusService.submitForApproval(null);
            System.assert(false, 'Expected AuraHandledException for null accountId');
        } catch (Exception e) {
            System.assert(e.getMessage().contains('accountId is required.'), e.getMessage());
        }
    }

    @IsTest
    static void testGetAllowedNextStatusesReturnsExpectedValues() {
        List<String> submittedNext = AccountStatusService.getAllowedNextStatuses(AccountStatusService.STATUS_SUBMITTED);
        System.assertEquals(2, submittedNext.size(), 'Submitted should allow exactly two next statuses');
        System.assert(submittedNext.contains(AccountStatusService.STATUS_ACTIVE), 'Submitted should allow Active');
        System.assert(submittedNext.contains(AccountStatusService.STATUS_REJECTED), 'Submitted should allow Rejected');

        List<String> unknownNext = AccountStatusService.getAllowedNextStatuses('Unknown Status');
        System.assertEquals(0, unknownNext.size(), 'Unknown status should return an empty allowed list');
    }

    @IsTest
    static void testTransitionStatusUpdatesAccountStatus() {
        Account accountRecord = createTestAccount(AccountStatusService.STATUS_DRAFT);

        Test.startTest();
        AccountStatusService.transitionStatus(accountRecord.Id, AccountStatusService.STATUS_SUBMITTED);
        Test.stopTest();

        Account updatedAccount = [SELECT OutletStatus__c FROM Account WHERE Id = :accountRecord.Id];
        System.assertEquals(AccountStatusService.STATUS_SUBMITTED, updatedAccount.OutletStatus__c, 'Account status should update to Submitted');
    }

    @IsTest
    static void testSubmitForApprovalRollsBackWhenApprovalNotConfigured() {
        Account accountRecord = createTestAccount(AccountStatusService.STATUS_DRAFT);
        Boolean approvalFailed = false;

        try {
            Test.startTest();
            AccountStatusService.submitForApproval(accountRecord.Id);
            Test.stopTest();
        } catch (Exception e) {
            approvalFailed = true;
            System.assert(e.getMessage().contains('No Approval Process found') || e.getMessage().contains('Approval submission failed'), e.getMessage());
        }

        Account refreshed = [SELECT OutletStatus__c FROM Account WHERE Id = :accountRecord.Id];
        if (approvalFailed) {
            System.assertEquals(AccountStatusService.STATUS_DRAFT, refreshed.OutletStatus__c, 'Account status should roll back to Draft if approval submission fails');
        } else {
            System.assertEquals(AccountStatusService.STATUS_SUBMITTED, refreshed.OutletStatus__c, 'Account status should update to Submitted if approval submission succeeds');
        }
    }
}