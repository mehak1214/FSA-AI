/**
 * @description Batch class to update payment status to 'Overdue' for payments
 *              that are Pending or Partially Paid with outstanding amount > 0
 *              and order was placed 10 or more days ago
 */
global class PaymentStatusUpdateBatch implements Database.Batchable<SObject> {
    
    /**
     * @description Start method - returns the query locator for batch processing
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        // Query payments that meet the criteria:
        // - Payment_Status__c is 'Pending' or 'Partially Paid'
        // - Outstanding_Amount__c > 0
        String query = 'SELECT Id, Payment_Status__c, Order__c, Order__r.CreatedDate ' +
                       'FROM Payment ' +
                       'WHERE Payment_Status__c IN (\'Pending\', \'Partially Paid\') ' +
                       'AND Outstanding_Amount__c > 0';
        
        return Database.getQueryLocator(query);
    }
    
    /**
     * @description Execute method - processes each batch of records
     */
    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Payment> paymentsToUpdate = new List<Payment>();
        Date todayDate = Date.today();
        
        for (SObject sobj : scope) {
            Payment pay = (Payment) sobj;
            
                // Check if order was created 10 or more days ago
            if (pay.Order__r != null && pay.Order__r.CreatedDate != null) {
                DateTime orderCreatedDateTime = pay.Order__r.CreatedDate;
                Date orderCreatedDate = orderCreatedDateTime.date();
                Integer daysDifference = orderCreatedDate.daysBetween(todayDate);
                
                // If 10 or more days have passed, mark as Overdue
                if (daysDifference >= 10) {
                    pay.Payment_Status__c = 'Overdue';
                    paymentsToUpdate.add(pay);
                }
            }
        }
        
        // Update the payments
        if (!paymentsToUpdate.isEmpty()) {
            try {
                update paymentsToUpdate;
                System.debug('Updated ' + paymentsToUpdate.size() + ' payments to Overdue status');
            } catch (Exception ex) {
                System.debug('Error updating payment status: ' + ex.getMessage());
            }
        }
    }
    
    /**
     * @description Finish method - executes after all batches are processed
     */
    global void finish(Database.BatchableContext bc) {
        System.debug('✅ PaymentStatusUpdateBatch completed successfully');
    }
}
