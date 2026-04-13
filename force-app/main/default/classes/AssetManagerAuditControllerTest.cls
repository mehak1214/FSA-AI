@IsTest
private class AssetManagerAuditControllerTest {

    @IsTest
    static void testAssetManagerAuditControllerFlows() {
        User currentUser = TestDataFactory.getRunningUser();
        Account outlet = TestDataFactory.createAccount('Audit Manager Outlet', 'Franchise');
        Product2 product = TestDataFactory.createVashiProduct('AssetAuditMgrProduct', true);
        Asset__c asset = TestDataFactory.createAssetRecord('Manager Audit Asset', 'Active', outlet, product);
        Beat__c beat = TestDataFactory.createBeat(currentUser, true);
        Visit__c visit = TestDataFactory.createVisitApproved(currentUser, outlet, beat, 1, Date.today());
        TestDataFactory.createAssetAudit(asset, visit, 'Needs Repair', null);

        List<Asset_Audit__c> audits = AssetManagerAuditController.getAudits('Needs Repair', 'today');
        System.assert(audits.size() >= 1);

        AssetManagerAuditController.updateAssetStatus(asset.Id, 'Scrapped');
        asset = [SELECT Asset_Status__c FROM Asset__c WHERE Id = :asset.Id];
        System.assertEquals('Scrapped', asset.Asset_Status__c);

        Visit_Task__c task = AssetManagerAuditController.createFollowUpTask(visit.Id, asset.Id, 'Follow Up', 'Inspect condition', true);
        System.assertEquals('Pending', task.Status__c);
        System.assertEquals(asset.Id, task.Related_Asset__c);
    }
}