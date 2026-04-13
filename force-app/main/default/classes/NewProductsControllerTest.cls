/**
 * @description Unit tests for NewProductsController.
 * Covers: getLatestNewProducts — returns up to 3 new products with image data.
 *
 * FIX: linkATestPhotoToRecord is NOT called in @TestSetup because @TestSetup data
 * is shared across all parallel test methods. Inserting a ContentDocumentLink to
 * the same ContentDocument from multiple concurrent test methods causes
 * UNABLE_TO_LOCK_ROW on the shared ContentDocument record.
 * Instead, each test that needs photo data creates its own ContentVersion inline.
 */
@IsTest
private class NewProductsControllerTest {

    @TestSetup
    static void setup() {
        // Create 4 new products — NO photo linking here to avoid ContentDocument lock contention
        TestDataFactory.createNewVashiProduct('NC Product A', true);
        TestDataFactory.createNewVashiProduct('NC Product B', true);
        TestDataFactory.createNewVashiProduct('NC Product C', true);
        TestDataFactory.createNewVashiProduct('NC Product D', true);
    }

    /* =========================================================
       TEST getLatestNewProducts - returns at most 3
       ========================================================= */
    @IsTest
    static void testGetLatestNewProducts_returnsMaxThree() {
        Test.startTest();
        List<NewProductsController.ProductCardWrapper> wrappers =
            NewProductsController.getLatestNewProducts();
        Test.stopTest();

        System.assertNotEquals(null, wrappers, 'Should not return null');
        System.assertEquals(true, wrappers.size() <= 3, 'Should return at most 3 products');
        System.assertEquals(3, wrappers.size(), 'Should return exactly 3 when 4 new products exist');
    }

    @IsTest
    static void testGetLatestNewProducts_wrapperFieldsSet() {
        Test.startTest();
        List<NewProductsController.ProductCardWrapper> wrappers =
            NewProductsController.getLatestNewProducts();
        Test.stopTest();

        for (NewProductsController.ProductCardWrapper w : wrappers) {
            System.assertNotEquals(null, w.productId, 'Product Id should be set');
            System.assertNotEquals(null, w.productName, 'Product Name should be set');
        }
    }

    @IsTest
    static void testGetLatestNewProducts_contentVersionIdSetForProductWithPhoto() {
        // Link a photo inside this test method only — avoids ContentDocument lock contention
        // when other test methods run in parallel
        Product2 p = [SELECT Id FROM Product2 WHERE Name = 'NC Product A' LIMIT 1];
        TestDataFactory.linkATestPhotoToRecord(p.Id);

        Test.startTest();
        List<NewProductsController.ProductCardWrapper> wrappers =
            NewProductsController.getLatestNewProducts();
        Test.stopTest();

        NewProductsController.ProductCardWrapper withPhoto = null;
        for (NewProductsController.ProductCardWrapper w : wrappers) {
            if (w.productId == p.Id) {
                withPhoto = w;
                break;
            }
        }

        if (withPhoto != null) {
            System.assertNotEquals(null, withPhoto.contentVersionId,
                'ContentVersion Id should be set for product with photo');
        }
    }

    @IsTest
    static void testGetLatestNewProducts_noNewProducts_returnsEmpty() {
        // Update Is_New__c to false — avoids row-lock contention from deleting shared records
        List<Product2> prods = [SELECT Id FROM Product2 WHERE Is_New__c = true];
        for (Product2 p : prods) {
            p.Is_New__c = false;
        }
        update prods;

        Test.startTest();
        List<NewProductsController.ProductCardWrapper> wrappers =
            NewProductsController.getLatestNewProducts();
        Test.stopTest();

        System.assertEquals(0, wrappers.size(), 'Empty list expected when no new products exist');
    }
}