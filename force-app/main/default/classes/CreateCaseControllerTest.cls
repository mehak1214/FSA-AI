@IsTest
private class CreateCaseControllerTest {

    @IsTest
    static void testCreateCaseController() {
        Account acct = TestDataFactory.createAccount('Case Account', 'Franchise');
        Product2 product = TestDataFactory.createVashiProduct('CaseProduct', true);
        Order order = TestDataFactory.createOrderRecord(acct, 1000, Date.today(), 'Activated');
        Case c = TestDataFactory.createCaseForOrder(order, acct, 'Subject', 'Reason', 'Type');

        ContentVersion cv = new ContentVersion(
            Title = 'file.jpg',
            PathOnClient = 'file.jpg',
            VersionData = Blob.valueOf('abc'),
            IsMajorVersion = true,
            FirstPublishLocationId = c.Id
        );
        insert cv;

        CreateCaseController.PicklistMetadata meta = CreateCaseController.getPicklistMetadata();
        System.assertNotEquals(null, meta);

        Map<String, Object> orderInfo = CreateCaseController.getOrderInfo(order.Id);
        System.assertEquals(order.Id, orderInfo.get('orderId'));

        String contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        Map<String, Object> fileInfo = CreateCaseController.getFileSize(contentDocId);
        System.assert(fileInfo.containsKey('size'));

        Map<String, Object> result = CreateCaseController.createCase(
            acct.Id,
            order.Id,
            'New Case',
            'Description',
            'Solution',
            'Reason',
            'Type',
            'Comment',
            'INR',
            contentDocId,
            null,
            null,
            null
        );
        System.assertEquals(true, result.get('success'));
    }
}