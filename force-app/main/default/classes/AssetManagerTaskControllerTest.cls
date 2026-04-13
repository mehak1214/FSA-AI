@IsTest
private class AssetManagerTaskControllerTest {

    @IsTest
    static void testTaskControllerFlows() {
        User currentUser = TestDataFactory.getRunningUser();
        Account outlet = TestDataFactory.createAccount('Task Outlet', 'Franchise');
        Product2 product = TestDataFactory.createVashiProduct('TaskProduct', true);
        Asset__c asset = TestDataFactory.createAssetRecord('Task Asset', 'Pending Preparation', outlet, product);
        Beat__c beat = TestDataFactory.createBeat(currentUser, true);
        Visit__c visit = TestDataFactory.createVisitApproved(currentUser, outlet, beat, 2, Date.today());
        TestDataFactory.createBeatPlanStore(beat, outlet, true);

        System.assert(AssetManagerTaskController.getTasks(null, null, null, 'today') != null);
        System.assert(AssetManagerTaskController.getRetailers().size() >= 1);
        System.assert(AssetManagerTaskController.getSalesRepsForOutlet(outlet.Id).size() >= 1);

        Visit_Task__c createdTask = AssetManagerTaskController.createVisitAndTask(outlet.Id, currentUser.Id, String.valueOf(Date.today()), 'Store Visit', 'Follow up', true, asset.Id);
        System.assertEquals('Pending', createdTask.Status__c);
        System.assertEquals(asset.Id, createdTask.Related_Asset__c);

        AssetManagerTaskController.updateTaskStatus(createdTask.Id, 'Blocked/Retailer Refused', 'Retailer refused');
        Visit_Task__c updatedTask = [SELECT Status__c, Exception_Reason__c FROM Visit_Task__c WHERE Id = :createdTask.Id];
        System.assertEquals('Blocked/Retailer Refused', updatedTask.Status__c);

        System.assert(AssetManagerTaskController.getDeployedAssets().size() >= 1);
    }
}