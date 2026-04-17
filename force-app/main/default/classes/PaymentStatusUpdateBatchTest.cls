/**
 * @description Test class for PaymentStatusUpdateBatch and PaymentStatusUpdateScheduler
 */
@isTest
public class PaymentStatusUpdateBatchTest {
    
    /**
     * @description Test data setup - creates test orders and payments
     */
    @testSetup
    static void setupTestData() {
        // Create a test account
        Account testAccount = new Account(
            Name = 'Test Franchise Account',
            BillingCity = 'Test City',
            BillingCountry = 'Test Country'
        );
        insert testAccount;
        
        // Get standard pricebook
        Id pricebookId = Test.getStandardPricebookId();
        
        // Create a test product
        Product2 testProduct = new Product2(
            Name = 'Test Product',
            IsActive = true
        );
        insert testProduct;
        
        // Create pricebook entry
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = testProduct.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;
        
        // Create test order (older order - exactly 10 days old)
        Order oldOrder = new Order(
            AccountId = testAccount.Id,
            Pricebook2Id = pricebookId,
            Status = 'Activated',
            EffectiveDate = Date.today().addDays(-10),
            Type = 'Regular Order'
        );
        insert oldOrder;
        
        // Create order item
        OrderItem oldOrderItem = new OrderItem(
            OrderId = oldOrder.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert oldOrderItem;
        
        // Create payment for old order - Pending status
        Payment oldPaymentPending = new Payment(
            AccountId = testAccount.Id,
            Order__c = oldOrder.Id,
            Amount = 100,
            Paid_Amount__c = 0,
            Type = 'Sale',
            ProcessingMode = 'External',
            Status = 'Draft'
        );
        oldPaymentPending.put('Payment_Status__c', 'Pending');
        oldPaymentPending.put('Outstanding_Amount__c', 100);
        insert oldPaymentPending;
        
        // Create payment for old order - Partially Paid status
        Payment oldPaymentPartiallyPaid = new Payment(
            AccountId = testAccount.Id,
            Order__c = oldOrder.Id,
            Amount = 100,
            Paid_Amount__c = 40,
            Type = 'Sale',
            ProcessingMode = 'External',
            Status = 'Draft'
        );
        oldPaymentPartiallyPaid.put('Payment_Status__c', 'Partially Paid');
        oldPaymentPartiallyPaid.put('Outstanding_Amount__c', 60);
        insert oldPaymentPartiallyPaid;
        
        // Create test order (recent order - within 10 days)
        Order recentOrder = new Order(
            AccountId = testAccount.Id,
            Pricebook2Id = pricebookId,
            Status = 'Activated',
            EffectiveDate = Date.today().addDays(-5),
            Type = 'Regular Order'
        );
        insert recentOrder;
        
        // Create order item for recent order
        OrderItem recentOrderItem = new OrderItem(
            OrderId = recentOrder.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert recentOrderItem;
        
        // Create payment for recent order - should NOT be updated
        Payment recentPaymentPending = new Payment(
            AccountId = testAccount.Id,
            Order__c = recentOrder.Id,
            Amount = 100,
            Paid_Amount__c = 0,
            Type = 'Sale',
            ProcessingMode = 'External',
            Status = 'Draft'
        );
        recentPaymentPending.put('Payment_Status__c', 'Pending');
        recentPaymentPending.put('Outstanding_Amount__c', 100);
        insert recentPaymentPending;
    }
    
    /**
     * @description Test batch execution - verifies payments 10 or more days old are marked as Overdue
     */
    @isTest
    static void testBatchExecution() {
        // Execute the batch
        Test.startTest();
        Database.executeBatch(new PaymentStatusUpdateBatch(), 200);
        Test.stopTest();
        
        // Query and verify results
        List<Payment> allPayments = [SELECT Id, Payment_Status__c FROM Payment ORDER BY CreatedDate ASC];
        
        // We should have 3 payments total
        System.assertEquals(3, allPayments.size(), 'Should have 3 payments');
        
        // First two payments (old orders) should be marked as Overdue
        System.assertEquals('Overdue', allPayments[0].Payment_Status__c, 'First payment should be Overdue');
        System.assertEquals('Overdue', allPayments[1].Payment_Status__c, 'Second payment should be Overdue');
        
        // Third payment (recent order) should still be Pending
        System.assertEquals('Pending', allPayments[2].Payment_Status__c, 'Third payment should still be Pending');
    }
    
    /**
     * @description Test scheduler - verifies scheduler can be created and executed
     */
    @isTest
    static void testScheduler() {
        Test.startTest();
        // Schedule the job
        String jobId = System.schedule('Test Payment Status Update', '0 59 23 * * ?', new PaymentStatusUpdateScheduler());
        Test.stopTest();
        
        // Verify the job was scheduled
        System.assertNotEquals(null, jobId, 'Job should be scheduled successfully');
        
        // Verify the scheduled job exists
        List<CronTrigger> scheduledJobs = [SELECT Id, CronExpression FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals(1, scheduledJobs.size(), 'Scheduled job should exist');
        System.assertEquals('0 59 23 * * ?', scheduledJobs[0].CronExpression, 'Cron expression should match');
    }
}
