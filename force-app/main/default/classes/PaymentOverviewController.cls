public with sharing class PaymentOverviewController {
    
    public class PaymentOverviewResponse {
        @AuraEnabled public Decimal pendingAmount;
        @AuraEnabled public Integer overdueCount;
        @AuraEnabled public Date lastPaymentDate;
    }

    @AuraEnabled(cacheable=true)
    public static PaymentOverviewResponse getPaymentOverview(Id accountId) {
        try {
            if (accountId == null) {
                throw new AuraHandledException('Account ID is required.');
            }

            PaymentOverviewResponse response = new PaymentOverviewResponse();
            response.pendingAmount = 0;
            response.overdueCount = 0;
            response.lastPaymentDate = null;

            // Query Payment records
            List<Payment> payments = [
                SELECT Id, Amount, Date, Outstanding_Amount__c, 
                       Paid_Amount__c, Payment_Status__c,
                       AccountId
                FROM Payment
                WHERE AccountId = :accountId
                ORDER BY Date DESC
            ];

            if (payments.isEmpty()) {
                return response;
            }

            // Get last payment date
            for (Payment payment : payments) {
                if (payment.Date != null) {
                    response.lastPaymentDate = (Date)payment.Date;
                    break;
                }
            }

            // Calculate pending amount and overdue count
            Decimal pendingSum = 0;
            Integer overdueCount = 0;

            for (Payment payment : payments) {
                String status = payment.Payment_Status__c;

                // Sum outstanding amount for Pending and Overdue statuses
                if (status != null && (status.equals('Pending') || status.equals('Overdue'))) {
                    if (payment.Outstanding_Amount__c != null) {
                        pendingSum += payment.Outstanding_Amount__c;
                    }
                }

                // Count overdue payments
                if (status != null && status.equals('Overdue')) {
                    overdueCount++;
                }
            }

            response.pendingAmount = pendingSum;
            response.overdueCount = overdueCount;

            return response;

        } catch (Exception e) {
            throw new AuraHandledException('Error fetching payment overview: ' + e.getMessage());
        }
    }
}