public with sharing class OrderDetailController {

    public class OrderItemWrapper {
        @AuraEnabled public Id     orderItemId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal totalPrice;
        @AuraEnabled public String  unitOfMeasure;
        @AuraEnabled public String  description;
    }

    public class CaseWrapper {
        @AuraEnabled public Id      caseId;
        @AuraEnabled public String  caseNumber;
        @AuraEnabled public String  subject;
        @AuraEnabled public String  status;
        @AuraEnabled public String  type;
        @AuraEnabled public String  reason;
        @AuraEnabled public String  priority;
        @AuraEnabled public String  ownerName;
        @AuraEnabled public String  solutionRequired;
        @AuraEnabled public Decimal totalPrice;
    }

    public class OrderDetailWrapper {
        // ── Header ──────────────────────────────────────────────────────
        @AuraEnabled public Id      orderId;
        @AuraEnabled public Id      accountId;
        @AuraEnabled public String  orderNumber;
        @AuraEnabled public String  status;
        @AuraEnabled public Date    effectiveDate;
        @AuraEnabled public Date    endDate;
        @AuraEnabled public String  accountName;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public String  type;
        @AuraEnabled public String  description;
        @AuraEnabled public String  billingStreet;
        @AuraEnabled public String  billingCity;
        @AuraEnabled public String  billingState;
        @AuraEnabled public String  billingPostalCode;
        @AuraEnabled public String  billingCountry;
        @AuraEnabled public String  shippingStreet;
        @AuraEnabled public String  shippingCity;
        @AuraEnabled public String  shippingState;
        @AuraEnabled public String  shippingPostalCode;
        @AuraEnabled public String  shippingCountry;
        @AuraEnabled public String  ownerName;
        @AuraEnabled public String  poNumber;
        @AuraEnabled public String  contractNumber;
        // ── Line items ───────────────────────────────────────────────────
        @AuraEnabled public List<OrderItemWrapper> orderItems;
        @AuraEnabled public Integer orderItemsCount;
        @AuraEnabled public Decimal calculatedTotal; // sum of line item totals
        // ── Related cases ────────────────────────────────────────────────
        @AuraEnabled public List<CaseWrapper> cases;
        @AuraEnabled public Integer casesCount;
    }

    @AuraEnabled(cacheable=false)
    public static OrderDetailWrapper getOrderDetail(Id orderId) {
        if (orderId == null) {
            throw new AuraHandledException('Order ID is required.');
        }

        try {
            // ── Query Order header ────────────────────────────────────────
            List<Order> orders = [
                SELECT Id, AccountId, OrderNumber, Status, EffectiveDate, EndDate,
                       TotalAmount, Type, Description, PoNumber,
                       BillingStreet, BillingCity, BillingState,
                       BillingPostalCode, BillingCountry,
                       ShippingStreet, ShippingCity, ShippingState,
                       ShippingPostalCode, ShippingCountry,
                       Account.Name, Owner.Name,
                       Contract.ContractNumber
                FROM Order
                WHERE Id = :orderId
                LIMIT 1
            ];

            if (orders.isEmpty()) {
                throw new AuraHandledException('Order not found.');
            }

            Order o = orders[0];
            OrderDetailWrapper wrapper = new OrderDetailWrapper();
            wrapper.orderId       = o.Id;
            wrapper.accountId     = o.AccountId;
            wrapper.orderNumber   = o.OrderNumber;
            wrapper.status        = o.Status;
            wrapper.effectiveDate = o.EffectiveDate;
            wrapper.endDate       = o.EndDate;
            wrapper.totalAmount   = o.TotalAmount;
            wrapper.type          = o.Type;
            wrapper.description   = o.Description;
            wrapper.poNumber      = o.PoNumber;
            wrapper.accountName   = o.Account?.Name;
            wrapper.ownerName     = o.Owner?.Name;
            wrapper.contractNumber = o.Contract?.ContractNumber;

            // Billing address
            wrapper.billingStreet     = o.BillingStreet;
            wrapper.billingCity       = o.BillingCity;
            wrapper.billingState      = o.BillingState;
            wrapper.billingPostalCode = o.BillingPostalCode;
            wrapper.billingCountry    = o.BillingCountry;

            // Shipping address
            wrapper.shippingStreet     = o.ShippingStreet;
            wrapper.shippingCity       = o.ShippingCity;
            wrapper.shippingState      = o.ShippingState;
            wrapper.shippingPostalCode = o.ShippingPostalCode;
            wrapper.shippingCountry    = o.ShippingCountry;

            // ── Query OrderItems ─────────────────────────────────────────
            List<OrderItem> items = [
                SELECT Id, Product2.Name, Product2.ProductCode,
                       Quantity, UnitPrice, TotalPrice,
                       Product2.Description,
                       Description
                FROM OrderItem
                WHERE OrderId = :orderId
                ORDER BY CreatedDate ASC
            ];

            List<OrderItemWrapper> itemWrappers = new List<OrderItemWrapper>();
            Decimal calcTotal = 0;
            for (OrderItem item : items) {
                OrderItemWrapper iw = new OrderItemWrapper();
                iw.orderItemId    = item.Id;
                iw.productName    = item.Product2?.Name    ?? '--';
                iw.productCode    = item.Product2?.ProductCode ?? '';
                iw.quantity       = item.Quantity;
                iw.unitPrice      = item.UnitPrice;
                iw.totalPrice     = item.TotalPrice;
                iw.description    = item.Description ?? item.Product2?.Description ?? '';
                iw.unitOfMeasure  = null;
                if (item.TotalPrice != null) calcTotal += item.TotalPrice;
                itemWrappers.add(iw);
            }

            wrapper.orderItems      = itemWrappers;
            wrapper.orderItemsCount = itemWrappers.size();
            wrapper.calculatedTotal = calcTotal;

            // ── Query related Cases ───────────────────────────────────────
            // Uses a without sharing inner class so FLS/sharing rules on the
            // Case.Order__c lookup field don't silently block the query.
            wrapper.cases      = new CaseQueryHelper().getCasesForOrder(orderId);
            wrapper.casesCount = wrapper.cases.size();

            return wrapper;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load order details: ' + ex.getMessage());
        }
    }

    // ── Inner class runs without sharing so Case FLS / sharing rules
    //    never silently block the Order__c lookup query ─────────────────
    private without sharing class CaseQueryHelper {
        List<CaseWrapper> getCasesForOrder(Id orderId) {
            List<CaseWrapper> result = new List<CaseWrapper>();
            List<Case> caseRows = [
                SELECT Id, CaseNumber, Subject, Status, Type, Reason,
                       Priority, Owner.Name,
                       Solution_Required__c, Total_Price__c
                FROM Case
                WHERE Order__c = :orderId
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];
            for (Case c : caseRows) {
                CaseWrapper cw = new CaseWrapper();
                cw.caseId           = c.Id;
                cw.caseNumber       = c.CaseNumber;
                cw.subject          = c.Subject;
                cw.status           = c.Status;
                cw.type             = c.Type;
                cw.reason           = c.Reason;
                cw.priority         = c.Priority;
                cw.ownerName        = c.Owner?.Name;
                cw.solutionRequired = c.Solution_Required__c != null
                                        ? String.valueOf(c.Solution_Required__c) : null;
                cw.totalPrice       = c.Total_Price__c;
                result.add(cw);
            }
            return result;
        }
    }
}