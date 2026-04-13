@IsTest
private class AssetAuditControllerTest {

    @IsTest
    static void testAssetAuditControllerFlows() {
        User currentUser = TestDataFactory.getRunningUser();
        Account outlet = TestDataFactory.createAccount('Asset Audit Outlet', 'Franchise');
        Product2 product = TestDataFactory.createVashiProduct('AssetAuditProduct', true);
        Asset__c asset = TestDataFactory.createAssetRecord('Audit Asset', 'Active', outlet, product);
        Beat__c beat = TestDataFactory.createBeat(currentUser, true);
        Visit__c visit = TestDataFactory.createVisitApproved(currentUser, outlet, beat, 1, Date.today());
        Asset_Audit__c audit = TestDataFactory.createAssetAudit(asset, visit, 'Good', '/image.jpg');

        AssetAuditController.AssetAuditContext context = AssetAuditController.getAssetAuditContext(asset.Id, visit.Id);
        System.assertEquals(asset.Id, context.assetId);
        System.assertEquals(true, context.canAudit);
        System.assertEquals(true, context.hasAuditToday);

        String savedAuditId = AssetAuditController.saveAssetAudit(visit.Id, asset.Id, null, 'Damaged', 15.5, 85.3);
        System.assertNotEquals(null, savedAuditId);

        String updatedAuditId = AssetAuditController.saveAssetAudit(visit.Id, asset.Id, audit.Id, 'Needs Repair', null, null);
        System.assertEquals(audit.Id, updatedAuditId);

        String photoUrl = AssetAuditController.uploadAssetAuditPhoto(audit.Id, EncodingUtil.base64Encode(Blob.valueOf('image bytes')), 'image/jpeg', 'audit.jpg');
        System.assert(photoUrl.contains('/sfc/servlet.shepherd/version/download/'));
    }
}