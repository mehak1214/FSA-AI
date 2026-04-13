/**
 * @description Unit tests for OrdersByUserController.
 * Covers: getCurrentUserId, getOrdersByActivatedByUser,
 *         getOrdersByActivatedByUserWithStatus, getOrderDetail.
 */
@IsTest
private class OrdersByUserControllerTest {

    @TestSetup
    static void setup() {
        // Product and Pricebook
        Product2 product = TestDataFactory.createVashiProduct('Order Test Product', true);
        PricebookEntry pbe = TestDataFactory.createStdActivePbe(product, 50.00);

        // Franchise Account
        Account franchise = TestDataFactory.createAccount('Orders Franchise', 'Franchise');

        // Order linked to the franchise
        Order o = new Order(
            AccountId       = franchise.Id,
            EffectiveDate   = Date.today(),
            Status          = 'Draft',
            Pricebook2Id    = Test.getStandardPricebookId()
        );
        insert o;

        // Order item
        OrderItem oi = new OrderItem(
            OrderId          = o.Id,
            PricebookEntryId = pbe.Id,
            Quantity         = 5,
            UnitPrice        = 50.00
        );
        insert oi;

        // Activate order so ActivatedById is populated
        o.Status = 'Activated';
        update o;
    }

    private static Account getFranchise() {
        String query =
            'SELECT Id FROM Account ' +
            (Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')
                ? 'WHERE RecordType.DeveloperName = \'Franchise\' '
                : '') +
            'LIMIT 1';
        return Database.query(query);
    }

    private static Order getOrder() {
        return [SELECT Id, AccountId FROM Order LIMIT 1];
    }

    /* =========================================================
       TEST getCurrentUserId
       ========================================================= */
    @IsTest
    static void testGetCurrentUserId() {
        Test.startTest();
        String userId = OrdersByUserController.getCurrentUserId();
        Test.stopTest();

        System.assertEquals(UserInfo.getUserId(), userId, 'Should return current user Id');
    }

    /* =========================================================
       TEST getOrdersByActivatedByUser - with franchiseId
       ========================================================= */
    @IsTest
    static void testGetOrdersByActivatedByUser_withFranchiseId() {
        Account franchise = getFranchise();

        Test.startTest();
        List<OrdersByUserController.OrderWrapper> wrappers =
            OrdersByUserController.getOrdersByActivatedByUser(UserInfo.getUserId(), franchise.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrappers, 'Wrappers list should not be null');
        System.assertEquals(1, wrappers.size(), 'One order expected for the franchise');

        OrdersByUserController.OrderWrapper w = wrappers[0];
        System.assertNotEquals(null, w.orderId, 'Order Id should be set');
        System.assertNotEquals(null, w.orderNumber, 'Order Number should be set');
        System.assertNotEquals(null, w.products, 'Products list should not be null');
        System.assertEquals(1, w.productCount, 'One product expected on order');
    }

    @IsTest
    static void testGetOrdersByActivatedByUser_withUserIdFallback() {
        Test.startTest();
        List<OrdersByUserController.OrderWrapper> wrappers =
            OrdersByUserController.getOrdersByActivatedByUser(UserInfo.getUserId(), null);
        Test.stopTest();

        System.assertNotEquals(null, wrappers, 'Wrappers list should not be null (may be empty if order not activated by user)');
    }

    /* =========================================================
       TEST getOrdersByActivatedByUserWithStatus
       ========================================================= */
    @IsTest
    static void testGetOrdersByActivatedByUserWithStatus_allStatus() {
        Account franchise = getFranchise();

        Test.startTest();
        List<OrdersByUserController.OrderWrapper> wrappers =
            OrdersByUserController.getOrdersByActivatedByUserWithStatus(UserInfo.getUserId(), 'All', franchise.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrappers, 'Wrappers should not be null');
        System.assertEquals(1, wrappers.size(), 'One order expected with All status filter');
    }

    @IsTest
    static void testGetOrdersByActivatedByUserWithStatus_specificStatus() {
        Account franchise = getFranchise();

        Test.startTest();
        List<OrdersByUserController.OrderWrapper> wrappers =
            OrdersByUserController.getOrdersByActivatedByUserWithStatus(UserInfo.getUserId(), 'Activated', franchise.Id);
        Test.stopTest();

        System.assertNotEquals(null, wrappers, 'Wrappers should not be null');
        System.assertEquals(1, wrappers.size(), 'One activated order expected');
    }

    @IsTest
    static void testGetOrdersByActivatedByUserWithStatus_nonMatchingStatus() {
        Account franchise = getFranchise();

        Test.startTest();
        List<OrdersByUserController.OrderWrapper> wrappers =
            OrdersByUserController.getOrdersByActivatedByUserWithStatus(UserInfo.getUserId(), 'Draft', franchise.Id);
        Test.stopTest();

        System.assertEquals(0, wrappers.size(), 'No Draft orders should exist after activation');
    }

    /* =========================================================
       TEST getOrderDetail
       ========================================================= */
    @IsTest
    static void testGetOrderDetail_returnsDetail() {
        Order order = getOrder();

        Test.startTest();
        OrdersByUserController.OrderDetailWrapper detail =
            OrdersByUserController.getOrderDetail(order.Id);
        Test.stopTest();

        System.assertNotEquals(null, detail, 'Order detail should not be null');
        System.assertEquals(order.Id, detail.orderId, 'Order Id should match');
        System.assertNotEquals(null, detail.orderNumber, 'Order number should be set');
        System.assertNotEquals(null, detail.status, 'Status should be set');
        System.assertEquals(1, detail.productCount, 'One product expected');
    }

    @IsTest
    static void testGetOrderDetail_invalidIdThrowsException() {
        Test.startTest();
        try {
            // Use a non-existent Order Id to trigger QueryException
            OrdersByUserController.getOrderDetail(null);
            System.assert(false, 'Expected AuraHandledException for null orderId');
        } catch (AuraHandledException e) {
            System.assert(true, 'AuraHandledException thrown as expected');
        }
        Test.stopTest();
    }

    /* =========================================================
       TEST ProductWrapper fields
       ========================================================= */
    @IsTest
    static void testProductWrapper_totalPriceCalculated() {
        Account franchise = getFranchise();

        Test.startTest();
        List<OrdersByUserController.OrderWrapper> wrappers =
            OrdersByUserController.getOrdersByActivatedByUser(UserInfo.getUserId(), franchise.Id);
        Test.stopTest();

        OrdersByUserController.OrderWrapper order = wrappers[0];
        OrdersByUserController.ProductWrapper pw = order.products[0];
        System.assertEquals(250.00, pw.totalPrice, 'Total price should be quantity * unit price');
        System.assertEquals(5, pw.quantity, 'Quantity should match');
        System.assertEquals(50.00, pw.unitPrice, 'Unit price should match');
    }
}