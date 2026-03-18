public with sharing class OrdersByUserController {

    /* =========================================================
       PRODUCT WRAPPER CLASS
       ========================================================= */
    public class ProductWrapper {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal totalPrice;

        public ProductWrapper(OrderItem item) {
            this.productId = item.Product2Id;
            this.productName = item.Product2.Name;
            this.quantity = item.Quantity;
            this.unitPrice = item.UnitPrice;
            // Calculate total price: quantity * unit price
            this.totalPrice = (item.Quantity != null && item.UnitPrice != null) 
                ? (item.Quantity * item.UnitPrice) 
                : 0;
        }
    }

    /* =========================================================
       ORDER WRAPPER CLASS
       ========================================================= */
    public class OrderWrapper {
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String orderType;
        @AuraEnabled public Integer productCount;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Date orderDate;
        @AuraEnabled public String shippingStreet;
        @AuraEnabled public String shippingCity;
        @AuraEnabled public String shippingState;
        @AuraEnabled public String shippingPostalCode;
        @AuraEnabled public String shippingCountry;
        @AuraEnabled public String dealerName;
        @AuraEnabled public Id dealerId;
        @AuraEnabled public String activatedByName;
        @AuraEnabled public List<ProductWrapper> products;

        public OrderWrapper() {}

        public OrderWrapper(Order order, List<OrderItem> orderItems) {
            this.orderId = order.Id;
            this.orderNumber = order.OrderNumber;
            this.status = order.Status;
            this.orderType = order.Type;
            this.totalAmount = order.TotalAmount;
            this.orderDate = order.EffectiveDate;
            this.shippingStreet = order.ShippingStreet;
            this.shippingCity = order.ShippingCity;
            this.shippingState = order.ShippingState;
            this.shippingPostalCode = order.ShippingPostalCode;
            this.shippingCountry = order.ShippingCountry;
            this.products = new List<ProductWrapper>();
            
            if (order.Account != null) {
                this.dealerName = order.Account.Name;
                this.dealerId = order.Account.Id;
            }
            if (order.ActivatedBy != null) {
                this.activatedByName = order.ActivatedBy.Name;
            }

            // Add products to this order
            for (OrderItem item : orderItems) {
                this.products.add(new ProductWrapper(item));
            }
            this.productCount = orderItems.size();
        }
    }

    /* =========================================================
       ORDER DETAIL WRAPPER CLASS
       ========================================================= */
    public class OrderDetailWrapper {
        @AuraEnabled public Id orderId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String orderType;
        @AuraEnabled public Integer productCount;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public Date orderStartDate;
        @AuraEnabled public String dealerName;
        @AuraEnabled public String activatedByName;
        @AuraEnabled public String description;
        @AuraEnabled public String billingStreet;
        @AuraEnabled public String billingCity;
        @AuraEnabled public String billingState;
        @AuraEnabled public String billingPostalCode;
        @AuraEnabled public String billingCountry;
        @AuraEnabled public String shippingStreet;
        @AuraEnabled public String shippingCity;
        @AuraEnabled public String shippingState;
        @AuraEnabled public String shippingPostalCode;
        @AuraEnabled public String shippingCountry;

        public OrderDetailWrapper(Order orderRecord) {
            this.orderId = orderRecord.Id;
            this.accountId = orderRecord.AccountId;
            this.orderNumber = orderRecord.OrderNumber;
            this.status = orderRecord.Status;
            this.orderType = orderRecord.Type;
            this.totalAmount = orderRecord.TotalAmount;
            this.orderStartDate = orderRecord.EffectiveDate;
            this.description = orderRecord.Description;

            this.billingStreet = orderRecord.BillingStreet;
            this.billingCity = orderRecord.BillingCity;
            this.billingState = orderRecord.BillingState;
            this.billingPostalCode = orderRecord.BillingPostalCode;
            this.billingCountry = orderRecord.BillingCountry;

            this.shippingStreet = orderRecord.ShippingStreet;
            this.shippingCity = orderRecord.ShippingCity;
            this.shippingState = orderRecord.ShippingState;
            this.shippingPostalCode = orderRecord.ShippingPostalCode;
            this.shippingCountry = orderRecord.ShippingCountry;

            if (orderRecord.Account != null) {
                this.dealerName = orderRecord.Account.Name;
            }
            if (orderRecord.ActivatedBy != null) {
                this.activatedByName = orderRecord.ActivatedBy.Name;
            }
        }
    }

    /* =========================================================
       GET CURRENT USER ID
       ========================================================= */
    @AuraEnabled(cacheable=false)
    public static String getCurrentUserId() {
        return UserInfo.getUserId();
    }

    /* =========================================================
       GET ORDERS BY ACTIVATED BY USER (Sales Rep)
       ========================================================= */
    @AuraEnabled(cacheable=false)
    public static List<OrderWrapper> getOrdersByActivatedByUser(Id userId, Id visitFranchiseId) {
        List<OrderWrapper> orderWrappers = new List<OrderWrapper>();

        try {
            // If visitFranchiseId is provided, filter by Account (franchise) first.
            List<Order> orders;
            if (visitFranchiseId != null) {
                orders = [
                    SELECT
                        Id,
                        OrderNumber,
                        Status,
                        Type,
                        TotalAmount,
                        EffectiveDate,
                        ShippingStreet,
                        ShippingCity,
                        ShippingState,
                        ShippingPostalCode,
                        ShippingCountry,
                        AccountId,
                        Account.Name,
                        Account.Id,
                        ActivatedById,
                        ActivatedBy.Name
                    FROM Order
                    WHERE AccountId = :visitFranchiseId
                    ORDER BY CreatedDate DESC
                    LIMIT 1000
                ];
            } else {
                // Backward compatible fallback: orders activated by current user.
                orders = [
                    SELECT
                        Id,
                        OrderNumber,
                        Status,
                        Type,
                        TotalAmount,
                        EffectiveDate,
                        ShippingStreet,
                        ShippingCity,
                        ShippingState,
                        ShippingPostalCode,
                        ShippingCountry,
                        AccountId,
                        Account.Name,
                        Account.Id,
                        ActivatedById,
                        ActivatedBy.Name
                    FROM Order
                    WHERE ActivatedById = :userId
                    ORDER BY CreatedDate DESC
                    LIMIT 1000
                ];
            }

            // Get all order IDs
            Set<Id> orderIds = new Set<Id>();
            for (Order order : orders) {
                orderIds.add(order.Id);
            }

            // Query order items for all orders
            Map<Id, List<OrderItem>> orderItemsMap = new Map<Id, List<OrderItem>>();
            List<OrderItem> orderItems = [
                SELECT 
                    Id,
                    OrderId,
                    Product2Id,
                    Product2.Name,
                    Quantity,
                    UnitPrice
                FROM OrderItem
                WHERE OrderId IN :orderIds
                ORDER BY OrderId, CreatedDate ASC
            ];

            // Group order items by order ID
            for (OrderItem item : orderItems) {
                if (!orderItemsMap.containsKey(item.OrderId)) {
                    orderItemsMap.put(item.OrderId, new List<OrderItem>());
                }
                orderItemsMap.get(item.OrderId).add(item);
            }

            // Create order wrappers with products
            for (Order order : orders) {
                List<OrderItem> items = orderItemsMap.containsKey(order.Id) ? orderItemsMap.get(order.Id) : new List<OrderItem>();
                orderWrappers.add(new OrderWrapper(order, items));
            }
        } catch (Exception e) {
            System.debug('Error fetching orders: ' + e.getMessage());
            throw new AuraHandledException('Unable to fetch orders: ' + e.getMessage());
        }

        return orderWrappers;
    }

    /* =========================================================
       GET ORDERS WITH CUSTOM FILTERS
       ========================================================= */
    @AuraEnabled(cacheable=false)
    public static List<OrderWrapper> getOrdersByActivatedByUserWithStatus(Id userId, String status, Id visitFranchiseId) {
        List<OrderWrapper> orderWrappers = new List<OrderWrapper>();

        try {
            String statusFilter = '';
            if (String.isNotBlank(status) && status != 'All') {
                statusFilter = ' AND Status = :status';
            }

            String baseFilter = visitFranchiseId != null
                ? 'AccountId = :visitFranchiseId'
                : 'ActivatedById = :userId';

            String query = 'SELECT Id, OrderNumber, Status, Type, TotalAmount, EffectiveDate, ShippingStreet, ShippingCity, ' +
                          'ShippingState, ShippingPostalCode, ShippingCountry, AccountId, Account.Name, ' +
                          'Account.Id, ActivatedById, ActivatedBy.Name ' +
                          'FROM Order ' +
                          'WHERE ' + baseFilter + statusFilter +
                          ' ORDER BY CreatedDate DESC LIMIT 1000';

            List<Order> orders = Database.query(query);

            // Get all order IDs
            Set<Id> orderIds = new Set<Id>();
            for (Order order : orders) {
                orderIds.add(order.Id);
            }

            // Query order items for all orders
            Map<Id, List<OrderItem>> orderItemsMap = new Map<Id, List<OrderItem>>();
            List<OrderItem> orderItems = [
                SELECT 
                    Id,
                    OrderId,
                    Product2Id,
                    Product2.Name,
                    Quantity,
                    UnitPrice
                FROM OrderItem
                WHERE OrderId IN :orderIds
                ORDER BY OrderId, CreatedDate ASC
            ];

            // Group order items by order ID
            for (OrderItem item : orderItems) {
                if (!orderItemsMap.containsKey(item.OrderId)) {
                    orderItemsMap.put(item.OrderId, new List<OrderItem>());
                }
                orderItemsMap.get(item.OrderId).add(item);
            }

            // Create order wrappers with products
            for (Order order : orders) {
                List<OrderItem> items = orderItemsMap.containsKey(order.Id) ? orderItemsMap.get(order.Id) : new List<OrderItem>();
                orderWrappers.add(new OrderWrapper(order, items));
            }
        } catch (Exception e) {
            System.debug('Error fetching orders: ' + e.getMessage());
            throw new AuraHandledException('Unable to fetch orders: ' + e.getMessage());
        }

        return orderWrappers;
    }

    /* =========================================================
       GET ORDER DETAIL BY ID
       ========================================================= */
    @AuraEnabled(cacheable=false)
    public static OrderDetailWrapper getOrderDetail(Id orderId) {
        try {
            Order orderRecord = [
                SELECT
                    Id,
                    AccountId,
                    OrderNumber,
                    Status,
                    Type,
                    TotalAmount,
                    EffectiveDate,
                    Description,
                    BillingStreet,
                    BillingCity,
                    BillingState,
                    BillingPostalCode,
                    BillingCountry,
                    ShippingStreet,
                    ShippingCity,
                    ShippingState,
                    ShippingPostalCode,
                    ShippingCountry,
                    Account.Name,
                    ActivatedBy.Name
                FROM Order
                WHERE Id = :orderId
                LIMIT 1
            ];

            OrderDetailWrapper detail = new OrderDetailWrapper(orderRecord);
            detail.productCount = [
                SELECT COUNT()
                FROM OrderItem
                WHERE OrderId = :orderId
            ];

            return detail;
        } catch (Exception e) {
            System.debug('Error fetching order detail: ' + e.getMessage());
            throw new AuraHandledException('Unable to fetch order detail: ' + e.getMessage());
        }
    }

}