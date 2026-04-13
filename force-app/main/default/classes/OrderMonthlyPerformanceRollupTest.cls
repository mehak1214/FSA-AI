@IsTest
private class OrderMonthlyPerformanceRollupTest {

    @IsTest
    static void testMonthlyPerformanceRollup() {
        Account acct = TestDataFactory.createAccount('Order Month Account', 'Franchise');
        Product2 p = TestDataFactory.createVashiProduct('OrderMonthProduct', true);
        PricebookEntry pbe = TestDataFactory.createStdActivePbe(p, 20);
        Order order = TestDataFactory.createOrderRecord(acct, 200, Date.today(), 'Draft');
        TestDataFactory.createOrderItem(order, pbe, 2, 20);

        Date monthStart = Date.newInstance(Date.today().year(), Date.today().month(), 1);
        Test.setCreatedDate(order.Id, DateTime.newInstance(monthStart, Time.newInstance(10, 0, 0, 0)));
        TestDataFactory.createMonthlyPerformance(UserInfo.getUserId(), monthStart, 100);

        OrderMonthlyPerformanceRollup.handle(new List<Order>{order}, new List<Order>{order});
    }
}