@IsTest
private class AssetManagerDashboardControllerTest {

    @IsTest
    static void testDashboardControllerMetrics() {
        // Set up all test data
        User currentUser = TestDataFactory.getRunningUser();
        Account outlet = TestDataFactory.createAccount('Dashboard Outlet', 'Franchise');
        Product2 product = TestDataFactory.createVashiProduct('DashboardProduct', true);
        Asset__c damagedAsset = TestDataFactory.createAssetRecord('Damaged Asset', 'Under Repair', outlet, product);
        Asset__c activeAsset = TestDataFactory.createAssetRecord('Active Asset', 'Active', outlet, product);
        Asset__c deployedAsset = TestDataFactory.createAssetRecord('Deployed Asset', 'Deployed', outlet, product);
        Beat__c beat = TestDataFactory.createBeat(currentUser, true);
        Visit__c visit = TestDataFactory.createVisitApproved(currentUser, outlet, beat, 1, Date.today());
        TestDataFactory.createAssetAllocation(activeAsset, outlet, 'Planned', Date.today().addDays(-5));
        TestDataFactory.createAssetAllocation(deployedAsset, outlet, 'Planned', Date.today().addDays(-7));
        TestDataFactory.createAssetAudit(damagedAsset, visit, 'Damaged', null);
        TestDataFactory.createAssetAudit(activeAsset, visit, 'Needs Repair', null);
        TestDataFactory.createBeatPlanStore(beat, outlet, true);
        TestDataFactory.createVisitTask(visit, activeAsset, 'Blocker', true, 'Blocked/Retailer Refused');
        TestDataFactory.createVisitTask(visit, deployedAsset, 'Normal Task', true, 'Pending');  // Pending + Mandatory for getPendingMandatoryTasks()

        // Do not use Test.startTest/stopTest with cacheable methods - they create transaction
        // boundaries that prevent visibility into pre-created test data
        Map<String, Integer> counts = AssetManagerDashboardController.getDashboardCounts();
        System.assert(counts.get('blockedTasks') >= 1, 'Expected at least 1 blocked task');
        System.assert(counts.get('damagedAssets') >= 1, 'Expected at least 1 damaged asset');
        System.assert(counts.get('assetsWithIssues') >= 1, 'Expected at least 1 asset with issues');
        System.assert(counts.get('pendingMandatoryTasks') >= 1, 'Expected at least 1 pending mandatory task');
        System.assert(counts.get('activeDeployed') >= 1, 'Expected at least 1 active/deployed asset');

        System.assert(AssetManagerDashboardController.getBlockedTasks().size() >= 1, 'Expected blocked tasks list');
        System.assert(AssetManagerDashboardController.getAssetsWithIssues().size() >= 1, 'Expected assets with issues');
        System.assert(AssetManagerDashboardController.getRepsInField().size() >= 1, 'Expected reps in field');
        System.assert(AssetManagerDashboardController.getOverdueDeployments().size() >= 1, 'Expected overdue deployments');
        System.assert(AssetManagerDashboardController.getPendingMandatoryTasks().size() >= 1, 'Expected pending mandatory tasks');
        System.assert(AssetManagerDashboardController.getAssetsWithNoRecentAudit().size() >= 1, 'Expected assets with no recent audit');
    }
}