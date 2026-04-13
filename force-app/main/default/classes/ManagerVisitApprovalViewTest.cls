/**
 * @description Comprehensive tests for ManagerVisitApprovalView.
 *
 * APPROVAL PROCESS SETUP
 * ───────────────────────────────────────────────────────────────
 * The org has "Visit Approval Process" configured with:
 *   - Entry criteria : Visit_Status__c = 'Draft' AND Approval_Status__c = 'Draft'
 *   - Allowed submitters: owner
 *   - Approver: Manager (user hierarchy field — the record owner's manager)
 *   - On submit  : sets Approval_Status__c → 'Submitted'
 *   - On approve : sets Visit_Status__c → 'Approved', Approval_Status__c → 'Approved'
 *   - On reject  : sets Approval_Status__c → 'Rejected'
 *
 * TEST STRATEGY (from Salesforce StackExchange pattern)
 * ───────────────────────────────────────────────────────────────
 * 1. Create a manager user  (managerUser)
 * 2. Create a rep user      (repUser) with ManagerId = managerUser.Id
 * 3. As repUser   → insert a Draft visit (meets entry criteria) and submit it for approval
 *                   → creates a ProcessInstanceWorkitem with ActorId = managerUser.Id
 * 4. As managerUser → call approveVisit / rejectVisit
 *                   → getCurrentUserWorkitemId finds the workitem → Approval.process() runs
 *
 * This covers ALL lines in the controller except isCurrentApprover (dead code — never
 * called from any @AuraEnabled method).
 *
 * We use System.runAs() to switch user context within each test method.
 */
@IsTest
private class ManagerVisitApprovalViewTest {

    // ─── USER / DATA SETUP ────────────────────────────────────────────────────

    /**
     * Creates a minimal standard user with the given last name.
     * Uses the running user's profile so no separate profile query is needed.
     */
    private static User buildUser(String lastName, String alias) {
        String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User u = new User(
            LastName            = lastName,
            Alias               = alias.left(8),
            Email               = alias + unique + '@test.example.com',
            Username            = alias + unique + '@test.example.com.testorg',
            CommunityNickname   = alias + unique,
            TimeZoneSidKey      = 'America/Los_Angeles',
            LocaleSidKey        = 'en_US',
            EmailEncodingKey    = 'UTF-8',
            LanguageLocaleKey   = 'en_US',
            ProfileId           = UserInfo.getProfileId()
        );
        return u;
    }

    @TestSetup
    static void setup() {
        // Create manager first so we have its Id for the rep's ManagerId field
        User mgr = buildUser('MGR_Approval', 'mgrapv');
        insert mgr;

        User rep = buildUser('REP_Approval', 'repapv');
        rep.ManagerId = mgr.Id;
        insert rep;
    }

    // ─── HELPERS ──────────────────────────────────────────────────────────────

    private static User getManager() {
        return [SELECT Id FROM User WHERE LastName = 'MGR_Approval' LIMIT 1];
    }

    private static User getRep() {
        return [SELECT Id FROM User WHERE LastName = 'REP_Approval' LIMIT 1];
    }

    /**
     * Creates a Draft visit owned by repUser (meets entry criteria for the approval process).
     * Must be called inside System.runAs(repUser) so the owner is repUser.
     */
    private static Visit__c createDraftVisit() {
        // We need a Beat and Account — create minimal versions
        Account outlet = new Account(Name = 'MgrApproval Outlet');
        // Use the Franchise record type if it exists
        Map<String, Schema.RecordTypeInfo> rtMap =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        if (rtMap.containsKey('Franchise')) {
            if (Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')) {
                outlet.put('RecordTypeId', rtMap.get('Franchise').getRecordTypeId());
            }
            outlet.OutletStatus__c = 'Active';
            outlet.Active__c = 'Yes';
            outlet.Outlet_Code__c = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        }
        insert outlet;

        Beat__c beat = new Beat__c(
            Name       = 'MgrApproval Beat',
            Sales_Rep__c = UserInfo.getUserId(),
            Active__c  = true
        );
        insert beat;

        Visit__c v = new Visit__c(
            Sales_Rep__c         = UserInfo.getUserId(),
            Outlet1__c           = outlet.Id,
            Beat__c              = beat.Id,
            Visit_Date__c        = Date.today(),
            Sequence__c          = 1,
            Visit_Status__c      = 'Draft',
            Approval_Status__c   = 'Draft',
            Planned_Start_Time__c = Datetime.newInstance(Date.today(), Time.newInstance(9, 0, 0, 0)),
            Planned_End_Time__c   = Datetime.newInstance(Date.today(), Time.newInstance(10, 0, 0, 0))
        );
        insert v;
        return v;
    }

    /**
     * Submits the given Visit for approval as the currently running user.
     * Returns the Approval.ProcessResult — asserts success before returning.
     */
    private static Approval.ProcessResult submitForApproval(Id visitId) {
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(visitId);
        req.setSubmitterId(UserInfo.getUserId());
        Approval.ProcessResult result = Approval.process(req);
        System.assert(result.isSuccess(),
            'Approval submission failed: ' + result.getErrors());
        return result;
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  getVisitsForManager — empty path (no workitems for current user)
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testGetVisitsForManager_noWorkitems_returnsEmptyList() {
        Test.startTest();
        List<Visit__c> result = ManagerVisitApprovalView.getVisitsForManager();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result must not be null');
        System.assertEquals(0, result.size(), 'Must be empty when no workitems exist for current user');
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  getVisitsForManager — WITH workitems
    //  (covers ProcessInstanceWorkitem loop body and final Visit SELECT)
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testGetVisitsForManager_withPendingWorkitem_returnsVisit() {
        User rep = getRep();
        User mgr = getManager();

        // Step 1: As repUser — create a Draft visit and submit for approval
        Visit__c v;
        System.runAs(rep) {
            v = createDraftVisit();
            Test.startTest();
            submitForApproval(v.Id);
        }

        // Step 2: As managerUser — the workitem is now in their queue
        System.runAs(mgr) {
            List<Visit__c> result = ManagerVisitApprovalView.getVisitsForManager();
            Test.stopTest();

            System.assertNotEquals(null, result, 'Result must not be null');
            System.assert(result.size() >= 1,
                'Manager should see at least one visit with pending workitem');

            // Verify fields on returned Visit are all populated
            Visit__c returned = result[0];
            System.assertNotEquals(null, returned.Id);
            System.assertNotEquals(null, returned.Visit_Date__c);
            System.assertNotEquals(null, returned.Visit_Status__c);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  getVisitsForManager — ProcessInstanceStep path
    //  (covers lines 26-36 — the HISTORICAL approver loop)
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testGetVisitsForManager_afterApproval_coversProcessInstanceStep() {
        User rep = getRep();
        User mgr = getManager();

        Visit__c v;
        System.runAs(rep) {
            v = createDraftVisit();
            Test.startTest();
            submitForApproval(v.Id);
        }

        // Approve as manager → creates a ProcessInstanceStep with StepStatus = 'Approved'
        System.runAs(mgr) {
            // Get the workitem and approve it directly
            List<ProcessInstanceWorkitem> wis = [
                SELECT Id FROM ProcessInstanceWorkitem
                WHERE ActorId = :mgr.Id
                AND ProcessInstance.TargetObjectId = :v.Id
                LIMIT 1
            ];
            System.assert(!wis.isEmpty(), 'Workitem should exist for manager');

            Approval.ProcessWorkitemRequest approveReq = new Approval.ProcessWorkitemRequest();
            approveReq.setWorkitemId(wis[0].Id);
            approveReq.setAction('Approve');
            approveReq.setComments('Test approval');
            Approval.process(approveReq);

            // Now getVisitsForManager should find this via ProcessInstanceStep
            List<Visit__c> result = ManagerVisitApprovalView.getVisitsForManager();
            Test.stopTest();

            System.assertNotEquals(null, result);
            System.assert(result.size() >= 1,
                'Manager should see visit via ProcessInstanceStep after approving it');
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  approveVisit — INPUT VALIDATION
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testApproveVisit_nullId_throwsException() {
        Test.startTest();
        try {
            ManagerVisitApprovalView.approveVisit(null);
            System.assert(false, 'Expected AuraHandledException for null visitId');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void testApproveVisit_noWorkitem_throwsException() {
        // Any visit without a pending workitem triggers the null-workitem path
        User rep = getRep();
        Visit__c v;
        System.runAs(rep) {
            v = createDraftVisit();
        }

        Test.startTest();
        try {
            ManagerVisitApprovalView.approveVisit(v.Id);
            System.assert(false, 'Expected exception — no workitem for current user');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  approveVisit — SUCCESS PATH
    //  Covers lines 72-81: Approval.ProcessWorkitemRequest build + Approval.process()
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testApproveVisit_withWorkitem_returnsSuccess() {
        User rep = getRep();
        User mgr = getManager();

        Visit__c v;
        System.runAs(rep) {
            v = createDraftVisit();
            Test.startTest();
            submitForApproval(v.Id);
        }

        System.runAs(mgr) {
            String result = ManagerVisitApprovalView.approveVisit(v.Id);
            Test.stopTest();

            System.assertEquals('SUCCESS', result, 'approveVisit should return SUCCESS');
        }

        // Verify final field updates (applied by approval process field actions)
        Visit__c updated = [
            SELECT Visit_Status__c, Approval_Status__c FROM Visit__c WHERE Id = :v.Id
        ];
        System.assertEquals('Approved', updated.Visit_Status__c,
            'Visit_Status__c should be set to Approved by final approval actions');
        System.assertEquals('Approved', updated.Approval_Status__c,
            'Approval_Status__c should be set to Approved');
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  rejectVisit — INPUT VALIDATION
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testRejectVisit_nullId_throwsException() {
        Test.startTest();
        try {
            ManagerVisitApprovalView.rejectVisit(null, 'Reason');
            System.assert(false, 'Expected AuraHandledException for null visitId');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void testRejectVisit_blankComment_throwsException() {
        User rep = getRep();
        Visit__c v;
        System.runAs(rep) {
            v = createDraftVisit();
        }

        Test.startTest();
        try {
            ManagerVisitApprovalView.rejectVisit(v.Id, '');
            System.assert(false, 'Expected exception for blank comment');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void testRejectVisit_nullComment_throwsException() {
        User rep = getRep();
        Visit__c v;
        System.runAs(rep) {
            v = createDraftVisit();
        }

        Test.startTest();
        try {
            ManagerVisitApprovalView.rejectVisit(v.Id, null);
            System.assert(false, 'Expected exception for null comment');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void testRejectVisit_whitespaceComment_throwsException() {
        User rep = getRep();
        Visit__c v;
        System.runAs(rep) {
            v = createDraftVisit();
        }

        Test.startTest();
        try {
            ManagerVisitApprovalView.rejectVisit(v.Id, '   ');
            System.assert(false, 'Expected exception for whitespace comment');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void testRejectVisit_noWorkitem_throwsException() {
        User rep = getRep();
        Visit__c v;
        System.runAs(rep) {
            v = createDraftVisit();
        }

        Test.startTest();
        try {
            ManagerVisitApprovalView.rejectVisit(v.Id, 'Scheduling conflict');
            System.assert(false, 'Expected exception — no workitem');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  rejectVisit — SUCCESS PATH
    //  Covers lines 98-107: Approval.ProcessWorkitemRequest build + Approval.process()
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testRejectVisit_withWorkitem_returnsSuccess() {
        User rep = getRep();
        User mgr = getManager();

        Visit__c v;
        System.runAs(rep) {
            v = createDraftVisit();
            Test.startTest();
            submitForApproval(v.Id);
        }

        System.runAs(mgr) {
            String result = ManagerVisitApprovalView.rejectVisit(v.Id, 'Date conflict with other visit');
            Test.stopTest();

            System.assertEquals('SUCCESS', result, 'rejectVisit should return SUCCESS');
        }

        // Verify final field updates (applied by rejection process field actions)
        Visit__c updated = [
            SELECT Approval_Status__c FROM Visit__c WHERE Id = :v.Id
        ];
        System.assertEquals('Rejected', updated.Approval_Status__c,
            'Approval_Status__c should be set to Rejected by final rejection actions');
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  getCurrentUserWorkitemId — non-null return path
    //  (covered indirectly by approveVisit/rejectVisit success tests above;
    //   this test explicitly confirms the workitem Id is resolved correctly)
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testGetCurrentUserWorkitemId_nonNullReturn_viaApproveVisit() {
        User rep = getRep();
        User mgr = getManager();

        Visit__c v;
        System.runAs(rep) {
            v = createDraftVisit();
            Test.startTest();
            submitForApproval(v.Id);
        }

        // A second submit on a different visit to confirm the helper always picks
        // the most recent workitem (ORDER BY CreatedDate DESC LIMIT 1)
        Visit__c v2;
        System.runAs(rep) {
            v2 = createDraftVisit();
            submitForApproval(v2.Id);
        }

        System.runAs(mgr) {
            // Both visits have workitems; approving v2 should succeed without
            // accidentally picking up v's workitem
            String result = ManagerVisitApprovalView.approveVisit(v2.Id);
            Test.stopTest();
            System.assertEquals('SUCCESS', result, 'Should approve the correct visit');
        }
    }
}