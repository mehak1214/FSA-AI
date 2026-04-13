@IsTest
private class NewRetailAccountControllerTest {

    @IsTest
    static void testNewRetailAccountController() {
        NewRetailAccountController.OutletWrapper wrapper = new NewRetailAccountController.OutletWrapper();
        wrapper.shopName = 'New Retail Store';
        wrapper.businessType = 'Retail';
        wrapper.ownerFirstName = 'Bob';
        wrapper.ownerLastName = 'Merchant';
        wrapper.ownerEmail = 'bob@test.com';
        wrapper.recordTypeId = TestDataFactory.getFranchiseRtId();
        wrapper.outletStatus = 'Draft';

        String accId = NewRetailAccountController.createOutletAccount(JSON.serialize(wrapper));
        System.assertNotEquals(null, accId);

        NewRetailAccountController.OutletWrapper loaded = NewRetailAccountController.getAccountForEdit(accId);
        System.assertEquals('New Retail Store', loaded.shopName);

        NewRetailAccountController.uploadFile(accId, 'upload.txt', EncodingUtil.base64Encode(Blob.valueOf('content')), 'text/plain');
    }
}