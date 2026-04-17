/**
 * @description Schedulable class to schedule PaymentStatusUpdateBatch
 *              to run daily at 11:59 PM
 * 
 * Usage: Schedule from Setup or execute:
 * System.schedule('Payment Overdue Status Update', '0 59 23 * * ?', new PaymentStatusUpdateScheduler());
 */
global class PaymentStatusUpdateScheduler implements Schedulable {
    
    /**
     * @description Execute method - called by the scheduler
     */
    global void execute(SchedulableContext sc) {
        // Execute the batch with a batch size of 200
        Database.executeBatch(new PaymentStatusUpdateBatch(), 200);
    }
}
