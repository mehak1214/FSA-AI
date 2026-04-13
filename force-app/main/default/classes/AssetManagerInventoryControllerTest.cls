@IsTest
private class AssetManagerInventoryControllerTest {

    @IsTest
    static void testInventoryControllerFlows() {
        User currentUser = TestDataFactory.getRunningUser();
        Account outlet = TestDataFactory.createAccount('Inventory Outlet', 'Franchise');
        Product2 product = TestDataFactory.createVashiProduct('InventoryProduct', true);
        Asset__c inventoryAsset = TestDataFactory.createAssetRecord('Inventory Asset', 'Pending Preparation', null, product);
        Account outlet2 = TestDataFactory.createAccount('Inventory Outlet 2', 'Franchise');
        Beat__c beat2 = TestDataFactory.createBeat(currentUser, true);
        TestDataFactory.createBeatPlanStore(beat2, outlet2, true);
        TestDataFactory.createAssetAllocation(inventoryAsset, outlet2, 'Planned', Date.today().addDays(-3));

        System.assert(AssetManagerInventoryController.getAssets('All', 'Inventory', null).size() >= 1);
        System.assertEquals(inventoryAsset.Id, AssetManagerInventoryController.getAssetDetail(inventoryAsset.Id).Id);
        System.assert(AssetManagerInventoryController.getOutlets().size() >= 1);
        System.assert(AssetManagerInventoryController.getProducts().size() >= 1);

        String newAssetId = AssetManagerInventoryController.createAsset('New Serial', product.Id, String.valueOf(Date.today()), 1000, 'Active');
        System.assertNotEquals(null, newAssetId);

        System.assert(AssetManagerInventoryController.getSalesRepsForOutlet(outlet2.Id).size() >= 1);
        AssetManagerInventoryController.deployAsset(inventoryAsset.Id, outlet2.Id, currentUser.Id, String.valueOf(Date.today()), String.valueOf(Date.today()), 'Deploy now');
        Asset__c deployed = [SELECT Asset_Status__c FROM Asset__c WHERE Id = :inventoryAsset.Id];
        System.assertEquals('Pending Preparation', deployed.Asset_Status__c);

        AssetManagerInventoryController.markDelivered(inventoryAsset.Id);
        deployed = [SELECT Asset_Status__c FROM Asset__c WHERE Id = :inventoryAsset.Id];
        System.assertEquals('Deployed', deployed.Asset_Status__c);

        AssetManagerInventoryController.updateAssetStatus(inventoryAsset.Id, 'In Transit');
        deployed = [SELECT Asset_Status__c FROM Asset__c WHERE Id = :inventoryAsset.Id];
        System.assertEquals('In Transit', deployed.Asset_Status__c);
    }
}