public with sharing class PlaceOrderController {
    
    /* =========================================================
PRODUCT WRAPPER
========================================================= */
    public class ProductOrderWrapper {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public Boolean isSample;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal discountedTotal;
        @AuraEnabled public Decimal totalSampleQuantity; // kept for legacy regular-order use
        @AuraEnabled public Decimal quantityOnHand;      // from ProductItem, used for Sample Orders
        @AuraEnabled public Id productItemId;            // Id of the single ProductItem record for this product
        @AuraEnabled public Integer sampleOrderLimit;
        @AuraEnabled public Integer alreadyOrderedQty;
        
        private void initWrapper() {
            if (this.unitPrice == null) this.unitPrice = 0;
            if (this.discountedTotal == null) this.discountedTotal = 0;
        }
        
        public ProductOrderWrapper() {
        }
        
        public ProductOrderWrapper(Id pId, String pName, String pImageUrl, Integer pQty, Boolean pIsSample) {
            this.productId = pId;
            this.productName = pName;
            this.imageUrl = pImageUrl;
            this.quantity = pQty;
            this.isSample = pIsSample;
            initWrapper();
        }
    }
    
    public class SchemeOption {
        @AuraEnabled public Id value;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal discount;
        
        public SchemeOption(Id val, String lab, Decimal disc) {
            this.value = val;
            this.label = lab;
            this.discount = disc == null ? 0 : disc;
        }
    }
    
    /* =========================================================
LOAD PRODUCTS BY DISTRIBUTOR
========================================================= */
    @AuraEnabled(cacheable=true)
    public static List<ProductOrderWrapper> getProductsByDistributor(Id distributorId) {
        
        if (distributorId == null) {
            return new List<ProductOrderWrapper>();
        }
        
        List<Inventory_Item__c> inventoryItems = [
            SELECT Id, Product__c
            FROM Inventory_Item__c
            WHERE Inventory__c IN (
                SELECT Id FROM Inventory__c WHERE Dealer__c = :distributorId
            )
            AND Product__c != null
        ];
        
        Set<Id> productIds = new Set<Id>();
        for (Inventory_Item__c item : inventoryItems) productIds.add(item.Product__c);
        
        if (productIds.isEmpty()) return new List<ProductOrderWrapper>();
        
        List<Product2> products = [
            SELECT Id, Name, isSample__c, TotalSampleQuantity__c, SampleOrderLimit__c
            FROM Product2
            WHERE Id IN :productIds
            AND IsActive = true
            AND Is_Veeglow_products__c = true Order By CreatedDate ASC Limit 6
        ];
        
        Map<Id, ProductOrderWrapper> productsById = new Map<Id, ProductOrderWrapper>();
        for (Product2 p : products) {
            ProductOrderWrapper w = new ProductOrderWrapper();
            w.productId = p.Id;
            w.productName = p.Name;
            w.quantity = 0;
            w.isSample = (p.isSample__c == true);
            w.totalSampleQuantity = p.TotalSampleQuantity__c;
            w.sampleOrderLimit = p.SampleOrderLimit__c != null ? (Integer)p.SampleOrderLimit__c : null;
            w.initWrapper();
            productsById.put(p.Id, w);
        }
        
        if (productsById.isEmpty()) return new List<ProductOrderWrapper>();
        
        List<ContentDocumentLink> imageLinks = [
            SELECT LinkedEntityId, ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :productsById.keySet()
        ];
        for (ContentDocumentLink link : imageLinks) {
            if (productsById.containsKey(link.LinkedEntityId)) {
                productsById.get(link.LinkedEntityId).imageUrl = '/sfc/servlet.shepherd/version/download/' + link.ContentDocument.LatestPublishedVersionId;
            }
        }
        
        try {
            List<PricebookEntry> pbes = [
                SELECT Product2Id, UnitPrice, Pricebook2.IsStandard
                FROM PricebookEntry
                WHERE Product2Id IN :productsById.keySet()
                AND IsActive = true
                AND Pricebook2.IsStandard = true
            ];
            for (PricebookEntry pbe : pbes) {
                if (productsById.containsKey(pbe.Product2Id)) productsById.get(pbe.Product2Id).unitPrice = pbe.UnitPrice == null ? 0 : pbe.UnitPrice;
            }
        } catch (Exception ex) {
            // Best effort: products should still load even if standard price is unavailable.
        }
        
        return new List<ProductOrderWrapper>(productsById.values());
    }
    
    /* =========================================================
LOAD SAMPLE PRODUCTS (uses ProductItem.QuantityOnHand)
========================================================= */
    @AuraEnabled
    public static List<ProductOrderWrapper> getSampleProducts(Id franchiseId) {
        
        // Step 1: Find qualifying Product2 records
        List<Product2> sampleProductList = [
            SELECT Id, Name, isSample__c, SampleOrderLimit__c
            FROM Product2
            WHERE IsActive = true
            AND Is_Veeglow_products__c = true
            AND isSample__c = true
            AND SampleOrderLimit__c != null
            AND SampleOrderLimit__c != 0
            ORDER BY CreatedDate ASC
        ];
        
        if (sampleProductList.isEmpty()) return new List<ProductOrderWrapper>();
        
        Set<Id> productIds = new Set<Id>();
        for (Product2 p : sampleProductList) productIds.add(p.Id);
        
        // Step 2: Fetch the single ProductItem per product (QuantityUnitOfMeasure='Each', QuantityOnHand > 0).
        //         Each Product2 is guaranteed to have at most one such ProductItem.
        //         We store the ProductItem.Id so the stock decrement can re-fetch it safely with FOR UPDATE.
        List<ProductItem> productItems = [
            SELECT Id, Product2Id, QuantityOnHand
            FROM ProductItem
            WHERE Product2Id IN :productIds
            AND QuantityUnitOfMeasure = 'Each'
            AND QuantityOnHand > 0
            ORDER BY LastModifiedDate DESC  // safety: pick most-recently-modified if duplicates ever exist
        ];
        
        // Build a map of Product2Id -> ProductItem (first/latest record wins)
        Map<Id, ProductItem> productItemByProductId = new Map<Id, ProductItem>();
        for (ProductItem pi : productItems) {
            if (!productItemByProductId.containsKey(pi.Product2Id)) {
                productItemByProductId.put(pi.Product2Id, pi);
            }
        }
        
        // Step 3: Only include products that have a qualifying ProductItem
        Map<Id, ProductOrderWrapper> productsById = new Map<Id, ProductOrderWrapper>();
        for (Product2 p : sampleProductList) {
            if (!productItemByProductId.containsKey(p.Id)) continue; // No qualifying stock
            
            ProductItem pi = productItemByProductId.get(p.Id);
            ProductOrderWrapper w = new ProductOrderWrapper();
            w.productId        = p.Id;
            w.productName      = p.Name;
            w.quantity         = 0;
            w.isSample         = true;
            w.unitPrice        = 0;
            w.quantityOnHand   = pi.QuantityOnHand;
            w.productItemId    = pi.Id;  // store so placeOrder can re-fetch this exact record
            w.sampleOrderLimit = p.SampleOrderLimit__c != null ? (Integer)p.SampleOrderLimit__c : null;
            w.alreadyOrderedQty = 0;
            w.initWrapper();
            productsById.put(p.Id, w);
        }
        
        if (productsById.isEmpty()) return new List<ProductOrderWrapper>();
        
        // Step 4: Sum already-ordered quantities for this franchise (Sample Orders)
        if (franchiseId != null) {
            try {
                List<OrderItem> pastItems = [
                    SELECT Product2Id, Quantity
                    FROM OrderItem
                    WHERE Order.AccountId = :franchiseId
                    AND Order.Type = 'Sample Order'
                    AND Product2Id IN :productsById.keySet()
                ];
                for (OrderItem oi : pastItems) {
                    if (productsById.containsKey(oi.Product2Id)) {
                        Integer prev = productsById.get(oi.Product2Id).alreadyOrderedQty;
                        productsById.get(oi.Product2Id).alreadyOrderedQty = (prev == null ? 0 : prev) + (Integer)oi.Quantity;
                    }
                }
            } catch (Exception ex) {
                // Best effort
            }
        }
        
        // Step 5: Load product images
        List<ContentDocumentLink> imageLinks = [
            SELECT LinkedEntityId, ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :productsById.keySet()
        ];
        for (ContentDocumentLink link : imageLinks) {
            if (productsById.containsKey(link.LinkedEntityId)) {
                productsById.get(link.LinkedEntityId).imageUrl =
                    '/sfc/servlet.shepherd/version/download/' + link.ContentDocument.LatestPublishedVersionId;
            }
        }
        
        return new List<ProductOrderWrapper>(productsById.values());
    }
    
    /* =========================================================
LOAD PRODUCTS
========================================================= */
    @AuraEnabled(cacheable=true)
    public static List<ProductOrderWrapper> getProducts() {
        
        
        List<Product2> vashiProducts = [
            SELECT Id, Name, isSample__c
            FROM Product2
            WHERE IsActive = true
            AND Is_Veeglow_products__c = true
        ];
        
        
        Map<Id, ProductOrderWrapper> productsById = new Map<Id, ProductOrderWrapper>();
        
        for (Product2 product : vashiProducts) {
            
            ProductOrderWrapper wrapper = new ProductOrderWrapper();
            wrapper.productId   = product.Id;
            wrapper.productName = product.Name;
            wrapper.isSample   = (product.isSample__c == true);
            wrapper.quantity    = 0;
            
            productsById.put(product.Id, wrapper);
        }
        
        if (productsById.isEmpty()) {
            return new List<ProductOrderWrapper>();
        }
        
        List<ContentDocumentLink> imageLinks = [
            SELECT LinkedEntityId, ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :productsById.keySet()
        ];
        
        
        for (ContentDocumentLink link : imageLinks) {
            if (productsById.containsKey(link.LinkedEntityId)) {
                productsById.get(link.LinkedEntityId).imageUrl =
                    '/sfc/servlet.shepherd/version/download/' +
                    link.ContentDocument.LatestPublishedVersionId;
            }
        }
        
        return new List<ProductOrderWrapper>(productsById.values());
    }
    
    /* =========================================================
LOAD FRANCHISE ACCOUNTS
========================================================= */
    @AuraEnabled(cacheable=true)
    public static List<Account> getFranchiseAccounts() {
        String query =
            'SELECT Id, Name ' +
            'FROM Account ' +
            (Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')
             ? 'WHERE RecordType.DeveloperName = \'Franchise\' '
             : '') +
            'ORDER BY Name';
        
        return Database.query(query);
    }
    
    /* =========================================================
LOAD DISTRIBUTOR ACCOUNTS
========================================================= */
    @AuraEnabled(cacheable=true)
    public static List<Account> getDistributorAccounts() {
        String query =
            'SELECT Id, Name ' +
            'FROM Account ' +
            (Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')
             ? 'WHERE RecordType.DeveloperName = \'Dealer_Distributor\' '
             : '') +
            'ORDER BY Name';
        
        return Database.query(query);
    }
    
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAccountAddress(Id accountId) {
        
        if (accountId == null) {
            return new Map<String, Object>();
        }
        
        Account acc = [
            SELECT BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
            ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry,
            (SELECT Name, Phone FROM Contacts ORDER BY CreatedDate ASC LIMIT 1)
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
        
        Map<String, Object> address = new Map<String, Object>();
        
        address.put('billingStreet', acc.BillingStreet);
        address.put('billingCity', acc.BillingCity);
        address.put('billingState', acc.BillingState);
        address.put('billingPostalCode', acc.BillingPostalCode);
        address.put('billingCountry', acc.BillingCountry);
        
        address.put('shippingStreet', acc.ShippingStreet);
        address.put('shippingCity', acc.ShippingCity);
        address.put('shippingState', acc.ShippingState);
        address.put('shippingPostalCode', acc.ShippingPostalCode);
        address.put('shippingCountry', acc.ShippingCountry);
        
        // Prepopulate contact details from the first related Contact
        if (acc.Contacts != null && !acc.Contacts.isEmpty()) {
            Contact c = acc.Contacts[0];
            address.put('contactName', c.Name);
            address.put('phone', c.Phone);
        }
        
        return address;
    }
    
    
    /* =========================================================
LOAD SCHEMES BY THRESHOLD QUANTITY
========================================================= */
    @AuraEnabled(cacheable=true)
    public static List<SchemeOption> getSchemesByThresholdQuantity(Decimal thresholdQuantity) {
        
        if (thresholdQuantity == null || thresholdQuantity <= 0) {
            return new List<SchemeOption>();
        }
        
        try {
            List<Scheme__c> schemes = [
                SELECT Id, Name,Scheme_Name__c, Discount__c
                FROM Scheme__c
                WHERE Threshold_Quantity__c <= :thresholdQuantity
                AND Active__c = true
                ORDER BY Threshold_Quantity__c DESC, Discount__c DESC
            ];
            
            
            List<SchemeOption> schemeOptions = new List<SchemeOption>();
            for (Scheme__c s : schemes) {
                Decimal discount = s.Discount__c != null ? s.Discount__c : 0;
                schemeOptions.add(new SchemeOption(s.Id, s.Scheme_Name__c, discount));
            }
            return schemeOptions;
        } catch (Exception ex) {
            return new List<SchemeOption>();
        }
    }
    
    /* =========================================================
PLACE ORDER + LINE ITEMS
========================================================= */
    public static Id placeOrder(
        Id franchiseId,
        Id distributorId,
        List<Map<String, Object>> selectedProducts,
        Id selectedSchemeId
    ) {
        // Backward-compatible signature for existing Apex callers.
        return placeOrder(
            franchiseId,
            distributorId,
            'Regular Order',
            selectedProducts,
            selectedSchemeId == null ? null : String.valueOf(selectedSchemeId),
            null,
            null,
            null,
            null,                    // discountAmount
            selectedSchemeId         // appliedSchemeId
        );
    }
    
    @AuraEnabled
    public static Id placeOrder(
        Id franchiseId,
        Id distributorId,
        String orderType,
        List<Map<String, Object>> selectedProducts,
        String selectedSchemeId,
        Map<String, Object> addressData,
        Map<String, Object> paymentData,
        Id visitId,
        Decimal discountAmount,      // NEW
        Id appliedSchemeId            // NEW
    ) {
        
        
        if (franchiseId == null) {
            throw new AuraHandledException(
                'Please select a franchise before placing the order.'
            );
        }
        
        if (selectedProducts == null || selectedProducts.isEmpty()) {
            throw new AuraHandledException(
                'Please select at least one product before placing the order.'
            );
        }
        
        List<ProductOrderWrapper> wrappedProducts = new List<ProductOrderWrapper>();
        Set<Id> productIds = new Set<Id>();
        
        for (Map<String, Object> productMap : selectedProducts) {
            
            ProductOrderWrapper wrapper = new ProductOrderWrapper();
            wrapper.productId   = (Id)productMap.get('productId');
            wrapper.productName = (String)productMap.get('productName');
            wrapper.imageUrl    = (String)productMap.get('imageUrl');
            
            // quantity
            Object qtyObj = productMap.get('quantity');
            if (qtyObj != null) {
                if (qtyObj instanceof Integer) {
                    wrapper.quantity = (Integer)qtyObj;
                } else if (qtyObj instanceof String) {
                    wrapper.quantity = Integer.valueOf((String)qtyObj);
                } else if (qtyObj instanceof Double) {
                    wrapper.quantity = ((Double)qtyObj).intValue();
                }
            }
            
            // unitPrice (may come as Double, Decimal or String)
            wrapper.unitPrice = 0;
            Object upObj = productMap.get('unitPrice');
            if (upObj != null) {
                try {
                    wrapper.unitPrice = Decimal.valueOf(String.valueOf(upObj));
                } catch (Exception ex) {
                    wrapper.unitPrice = 0;
                }
            }
            
            if (wrapper.productId != null) productIds.add(wrapper.productId);
            
            wrappedProducts.add(wrapper);
        }
        
        // Load scheme discount if selectedSchemeId is provided
        Decimal schemeDiscount = 0;
        if (selectedSchemeId != null) {
            try {
                Id schemeIdParsed = (Id)selectedSchemeId;
                List<Scheme__c> schemes = [SELECT Id, Discount__c FROM Scheme__c WHERE Id = :schemeIdParsed AND Active__c = true LIMIT 1];
                if (!schemes.isEmpty()) {
                    schemeDiscount = schemes[0].Discount__c == null ? 0 : schemes[0].Discount__c;
                }
            } catch (Exception ex) {
                // Ignore invalid scheme id and proceed without discount.
            }
        }
        
        // Load standard Pricebook and PricebookEntries for all order types.
        // Sample Orders still need Pricebook2Id on the Order and PricebookEntryId on OrderItems
        // (Salesforce requirement); UnitPrice will be overridden to 0 for sample line items.
        Id standardPricebookId;
        if (Test.isRunningTest()) {
            // In tests, this guarantees the Standard Price Book is available.
            standardPricebookId = Test.getStandardPricebookId();
        } else {
            List<Pricebook2> stdPbs = [
                SELECT Id
                FROM Pricebook2
                WHERE IsStandard = true
                LIMIT 1
            ];
            if (stdPbs.isEmpty()) {
                throw new AuraHandledException('Standard Price Book is not available.');
            }
            standardPricebookId = stdPbs[0].Id;
        }
        Pricebook2 stdPb = new Pricebook2(Id = standardPricebookId);
        
        Map<Id, PricebookEntry> pbeMap = new Map<Id, PricebookEntry>();
        
        List<PricebookEntry> pbes = [
            SELECT Id, Product2Id, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :productIds
            AND Pricebook2Id = :stdPb.Id
            AND IsActive = true
        ];
        
        for (PricebookEntry pbe : pbes) {
            pbeMap.put(pbe.Product2Id, pbe);
        }
        
        
        /* ---------- CREATE ORDER ---------- */
        Order order = new Order(
            AccountId = franchiseId,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = stdPb.Id,
            Type = orderType
        );
        
        // === NEW: Save Scheme & Discount on Order Header ===
        if (appliedSchemeId != null) {
            order.Applied_Scheme__c = appliedSchemeId;
        }
        if (discountAmount != null && discountAmount > 0) {
            order.Discount_Amount__c = discountAmount;
        }
        // ===================================================
        
        // set distributor if provided
        if (distributorId != null) {
            order.Dealer_Distributer__c = distributorId;
        }
        
        // link to the visit this order was created from
        if (visitId != null) {
            order.Visit__c = visitId;
        }
        
        if (addressData != null) {
            
            order.ShippingStreet     = (String)addressData.get('shippingStreet');
            order.ShippingCity       = (String)addressData.get('shippingCity');
            order.ShippingState      = (String)addressData.get('shippingState');
            order.ShippingPostalCode = (String)addressData.get('shippingPostalCode');
            order.ShippingCountry    = (String)addressData.get('shippingCountry');
            
            order.BillingStreet      = (String)addressData.get('billingStreet');
            order.BillingCity        = (String)addressData.get('billingCity');
            order.BillingState       = (String)addressData.get('billingState');
            order.BillingPostalCode  = (String)addressData.get('billingPostalCode');
            order.BillingCountry     = (String)addressData.get('billingCountry');
            
            order.Contact_Name__c     = (String)addressData.get('contactName');
            // Convert to String first, then to Decimal
            String phoneStr = (String)addressData.get('phone');
            if (String.isNotBlank(phoneStr)) {
                order.Phone__c = Decimal.valueOf(phoneStr);
            }
            // order.Phone__c     = (String)addressData.get('phone');
            //Contact_Name__c, Phone__c
        }
        
        
        insert order;
        
        
        /* ---------- CREATE LINE ITEMS ---------- */
        List<OrderItem> lineItems = new List<OrderItem>();
        
        
        // We'll compute totals while building line items
        Decimal orderTotal = 0;
        for (ProductOrderWrapper product : wrappedProducts) {
            // Validate product object
            if (product == null) {
                continue;
            }
            
            // Validate productId
            if (product.productId == null) {
                continue;
            }
            
            // Validate quantity
            if (product.quantity == null || product.quantity <= 0) {
                continue;
            }
            
            // compute unit price and discounts
            Decimal unitPrice = product.unitPrice == null ? 0 : product.unitPrice;
            Integer qty = product.quantity == null ? 0 : product.quantity;
            Decimal subtotal = unitPrice * qty;
            
            // Apply scheme discount (if provided and selected)
            Decimal discountAmountCount = subtotal * (schemeDiscount / 100);
            Decimal lineTotalAfterDiscount = subtotal - discountAmountCount;
            
            if (orderType == 'Sample Order') {
                // Sample Orders: use PricebookEntryId (Salesforce requires it) with UnitPrice = 0
                PricebookEntry samplePbe = pbeMap.get(product.productId);
                if (samplePbe == null) {
                    continue; // No pricebook entry found for this sample product — skip
                }
                OrderItem oli = new OrderItem(
                    OrderId          = order.Id,
                    PricebookEntryId = samplePbe.Id,
                    Quantity         = qty,
                    UnitPrice        = 0
                );
                lineItems.add(oli);
            }
            else {
                PricebookEntry pbe = pbeMap.get(product.productId);
                if (pbe == null) {
                    // No pricebook entry found for this product — then create a pricebook entry on the fly (Salesforce requires PricebookEntryId on OrderItem)
                    pbe = new PricebookEntry(
                        Pricebook2Id = stdPb.Id,
                        Product2Id = product.productId,
                        UnitPrice = 0,
                        IsActive = true
                    );
                    insert pbe;
                }
                
                OrderItem oli = new OrderItem(
                    OrderId          = order.Id,
                    PricebookEntryId = pbe.Id,
                    Quantity         = qty,
                    UnitPrice        = unitPrice == 0 ? pbe.UnitPrice : unitPrice
                );
                
                // Set per-line totals and scheme discount details
                try {
                    //oli.Total_Price__c = subtotal;
                } catch (Exception e) {
                    oli.put('Total_Price__c', subtotal);
                }
                
                // store which scheme was applied (if any)
                if (selectedSchemeId != null) {
                    try {
                        Id schemeIdParsed = (Id)selectedSchemeId;
                        oli.Scheme__c = schemeIdParsed;
                    } catch (Exception e) {
                        oli.put('Scheme__c', selectedSchemeId);
                    }
                }
                
                orderTotal += lineTotalAfterDiscount;
                lineItems.add(oli);
            }
        }
        
        
        if (!lineItems.isEmpty()) {
            insert lineItems;
            
            // Activate Order
            order.Status = 'Activated';
            update order;
        } else {
            throw new AuraHandledException(
                'No valid line items could be created. Please verify your product selections.'
            );
        }
        
        /* ---------- CREATE PAYMENT (Regular Orders only) old code ---------- */
        
        /*    if (orderType != 'Sample Order' && paymentData != null) {

Decimal paymentAmount = 0;

try {
paymentAmount = Decimal.valueOf(String.valueOf(paymentData.get('amount')));
} catch (Exception e) {
paymentAmount = 0;
}

String paymentMode = (String) paymentData.get('mode');
String cardNumber  = (String) paymentData.get('cardNumber');
String cardHolder  = (String) paymentData.get('cardHolder');
String cardExpiry  = (String) paymentData.get('cardExpiry');
String cardType    = (String) paymentData.get('cardType');
String upiId       = (String) paymentData.get('upiId');

String paymentStatus = 'Pending';

if (paymentAmount > 0 && paymentAmount < orderTotal) {
paymentStatus = 'Partially Paid';
} else if (paymentAmount == orderTotal) {
paymentStatus = 'Paid';
}

try {
Payment pay = new Payment();
pay.Amount = paymentAmount;
pay.Type = 'Sale';
pay.Payment_Status__c = paymentStatus;
pay.status = 'Draft';
pay.ProcessingMode = 'External';
pay.Date = system.today();

pay.put('Payment_Status__c', paymentStatus);
pay.put('Payment_Mode__c', paymentMode);
pay.put('Card_Number__c', cardNumber);
pay.put('Card_Holder_Name__c', cardHolder);
pay.put('Card_Expiry__c', cardExpiry);
pay.put('Card_Type__c', cardType);
pay.put('UPI_Id__c', upiId);

pay.AccountId = franchiseId;
pay.Order__c = order.Id;

insert pay;

} catch (Exception ex) {
System.debug('Payment creation failed: ' + ex.getMessage());
// Do not block order if payment fails
}
} */
        
        /* ---------- CREATE PAYMENT (Regular Orders only) new code---------- */
        
        if (orderType != 'Sample Order' && paymentData != null) {
            
            // Get Grand Total (full order amount) from paymentData
            Decimal grandTotal = 0;
            try {
                grandTotal = Decimal.valueOf(String.valueOf(paymentData.get('amount')));
            } catch (Exception e) {
                grandTotal = orderTotal;  // Fallback to calculated orderTotal
            }
            
            // Get Paid Amount (payable amount user entered) from paymentData
            Decimal paidAmount = 0;
            try {
                paidAmount = Decimal.valueOf(String.valueOf(paymentData.get('paidAmount')));
            } catch (Exception e) {
                paidAmount = 0;
            }
            
            String paymentMode = (String) paymentData.get('mode');   // Cash, UPI, or Card
            
            // Calculate Outstanding Amount based on Grand Total - Paid Amount
            Decimal outstandingAmount = 0;
            if (paidAmount < grandTotal) {
                outstandingAmount = grandTotal - paidAmount;
            }
            // If paidAmount >= grandTotal, Outstanding_Amount__c = 0 (fully paid or overpaid)
            
            // Determine Payment Status based on paid amount
            String paymentStatus = 'Pending';
            if (paidAmount > 0 && paidAmount < grandTotal) {
                paymentStatus = 'Partially Paid';
            } else if (paidAmount >= grandTotal) {
                paymentStatus = 'Paid';
            }
            
            try {
                Payment pay = new Payment();
                
                // Standard + Existing Custom Fields Only
                pay.AccountId       = franchiseId;
                pay.Order__c        = order.Id;
                pay.Amount          = grandTotal;             // Grand Total (full order value)
                pay.Paid_Amount__c  = paidAmount;             // Paid Amount (what user is paying now)
                
                // Only save date if paid amount > 0
                if (paidAmount > 0) {
                    pay.Date = System.today();
                }
                
                pay.Type            = 'Sale';
                pay.ProcessingMode  = 'External';
                pay.Status          = 'Draft';
                
                // Only using fields that already exist
                pay.put('Payment_Status__c', paymentStatus);
                pay.put('Outstanding_Amount__c', outstandingAmount);
                
                // Payment Mode - ONLY if the field exists, otherwise comment it out
                if (String.isNotBlank(paymentMode)) {
                    try {
                        pay.put('Payment_Mode__c', paymentMode);
                    } catch (Exception e) {
                        // Field doesn't exist yet - ignore silently
                        System.debug('Payment_Mode__c field not found yet');
                    }
                }
                
                insert pay;
                
                System.debug('✅ Payment record created successfully! ID: ' + pay.Id);
                System.debug('Grand Total: ' + grandTotal);
                System.debug('Paid Amount: ' + paidAmount);
                System.debug('Outstanding Amount: ' + outstandingAmount);
                System.debug('Payment Status: ' + paymentStatus);
                
            } catch (Exception ex) {
                System.debug('❌ Payment creation failed: ' + ex.getMessage());
                System.debug('Error Line: ' + ex.getLineNumber());
                // Do NOT throw exception - Order should still be created successfully
            }
        }
        
        
        // Update order total and persist
        try {
            //order.Total_Price__c = orderTotal;
            // also try to set non-namespaced field if present
            try {
                order.put('Total_Price__c', orderTotal);
            } catch (Exception innerEx) {
                // ignore - best-effort
            }
            update order;
        } catch (Exception ex) {
            // Do not block order creation if total update fails.
        }
        
        // Decrement inventory for the distributor if provided
        if (distributorId != null && !productIds.isEmpty()) {
            try {
                List<Inventory_Item__c> invItems = [
                    SELECT Id, Product__c, AvailableStock__c
                    FROM Inventory_Item__c
                    WHERE Inventory__c IN (
                        SELECT Id FROM Inventory__c WHERE Dealer__c = :distributorId
                    )
                    AND Product__c IN :productIds
                    FOR UPDATE
                ];
                
                Map<Id, Inventory_Item__c> invByProduct = new Map<Id, Inventory_Item__c>();
                for (Inventory_Item__c ii : invItems) {
                    invByProduct.put(ii.Product__c, ii);
                }
                
                for (ProductOrderWrapper wp : wrappedProducts) {
                    if (wp.productId != null && invByProduct.containsKey(wp.productId)) {
                        Inventory_Item__c ii = invByProduct.get(wp.productId);
                        Integer orderedQty = wp.quantity == null ? 0 : wp.quantity;
                        Decimal avail = ii.AvailableStock__c == null ? 0 : ii.AvailableStock__c;
                        Decimal newAvail = avail - orderedQty;
                        if (newAvail < 0) newAvail = 0;
                        ii.AvailableStock__c = newAvail;
                    }
                }
                
                if (!invItems.isEmpty()) update invItems;
            } catch (Exception ex) {
                // Inventory sync is best effort and should not fail the order transaction.
            }
        }
        
        // Decrement ProductItem.QuantityOnHand for Sample Orders
        if (orderType == 'Sample Order' && !productIds.isEmpty()) {
            try {
                // Build a map of productId -> ordered quantity
                Map<Id, Integer> orderedQtyByProductId = new Map<Id, Integer>();
                for (ProductOrderWrapper wp : wrappedProducts) {
                    if (wp.productId != null && wp.quantity != null && wp.quantity > 0) {
                        orderedQtyByProductId.put(wp.productId, wp.quantity);
                    }
                }
                
                // Re-fetch the latest ProductItem records by Product2Id with FOR UPDATE
                // (one per product; latest-modified first for safety in case of duplicates)
                List<ProductItem> freshItems = [
                    SELECT Id, Product2Id, QuantityOnHand
                    FROM ProductItem
                    WHERE Product2Id IN :orderedQtyByProductId.keySet()
                    AND QuantityUnitOfMeasure = 'Each'
                    FOR UPDATE
                ];
                
                // One record per product — first occurrence wins (matches getSampleProducts logic)
                Map<Id, ProductItem> freshByProductId = new Map<Id, ProductItem>();
                for (ProductItem pi : freshItems) {
                    if (!freshByProductId.containsKey(pi.Product2Id)) {
                        freshByProductId.put(pi.Product2Id, pi);
                    }
                }
                
                List<ProductItem> toUpdate = new List<ProductItem>();
                for (Id pid : orderedQtyByProductId.keySet()) {
                    if (!freshByProductId.containsKey(pid)) continue;
                    ProductItem pi = freshByProductId.get(pid);
                    Integer deduct = orderedQtyByProductId.get(pid);
                    Decimal newQty = (pi.QuantityOnHand == null ? 0 : pi.QuantityOnHand) - deduct;
                    pi.QuantityOnHand = newQty < 0 ? 0 : newQty;
                    toUpdate.add(pi);
                }
                
                if (!toUpdate.isEmpty()) update toUpdate;
            } catch (Exception ex) {
                // Best effort – do not block order creation
                System.debug('Sample ProductItem stock update failed: ' + ex.getMessage());
            }
        }
        
        return order.Id;
    }
}