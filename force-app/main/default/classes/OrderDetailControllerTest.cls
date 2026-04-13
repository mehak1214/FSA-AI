@IsTest
private class OrderDetailControllerTest {

    @IsTest
    static void testOrderDetailController() {
        Account acct = TestDataFactory.createAccount('Order Account', 'Franchise');
        Product2 p = TestDataFactory.createVashiProduct('OrderProduct', true);
        PricebookEntry pbe = TestDataFactory.createStdActivePbe(p, 20);
        Order order = TestDataFactory.createOrderRecord(acct, 200, Date.today(), 'Draft');
        TestDataFactory.createOrderItem(order, pbe, 2, 20);
        TestDataFactory.createCaseForOrder(order, acct, 'Problem', 'Issue', 'Type');

        OrderDetailController.OrderDetailWrapper detail = OrderDetailController.getOrderDetail(order.Id);
        System.assertEquals(order.Id, detail.orderId);
        System.assertEquals(1, detail.orderItemsCount);
        System.assertEquals(1, detail.casesCount);
    }
}