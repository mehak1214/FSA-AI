public with sharing class Outlet360Controller {
    // Bound relationship scan and query row count to keep response deterministic in mobile.
    private static final Integer MAX_RELATIONSHIPS_TO_SCAN = 60;
    private static final Integer FALLBACK_ROW_LIMIT = 200;

    public class RelatedListCount {
        @AuraEnabled public String relationshipLabel;
        @AuraEnabled public String relationshipName;
        @AuraEnabled public String childObjectApiName;
        @AuraEnabled public String referenceFieldApiName;
        @AuraEnabled public Integer recordCount;
    }

    public class Outlet360Response {
        @AuraEnabled public String outletName;
        @AuraEnabled public String outletCode;
        @AuraEnabled public String outletStatus;
        @AuraEnabled public String outletPhone;
        @AuraEnabled public String outletAddress;
        @AuraEnabled public List<RelatedListCount> relatedLists;
        @AuraEnabled public Integer totalRelationships;
        @AuraEnabled public Integer scannedRelationships;
        @AuraEnabled public Boolean isTruncated;
        @AuraEnabled public Decimal pastRevenue;
        @AuraEnabled public Integer ordersCount;
        @AuraEnabled public Integer totalOrdersCount;
        @AuraEnabled public Integer invoicesCount;
        @AuraEnabled public String ordersObjectApiName;
        @AuraEnabled public String invoicesObjectApiName;
        @AuraEnabled public List<BusinessRecord> recentOrders;
        @AuraEnabled public List<BusinessRecord> allOrders;
        @AuraEnabled public List<OrderProductRecord> orderProducts;
        @AuraEnabled public List<OrderProductRecord> allOrderProducts;
        @AuraEnabled public Integer orderProductsCount;
        @AuraEnabled public Integer totalOrderProductsCount;
        @AuraEnabled public List<CaseRecord> cases;
        @AuraEnabled public List<CaseRecord> allCases;
        @AuraEnabled public Integer casesCount;
        @AuraEnabled public Integer totalCasesCount;
        @AuraEnabled public List<AssetRecord> assets;
        @AuraEnabled public List<AssetRecord> allAssets;
        @AuraEnabled public Integer assetsCount;
        @AuraEnabled public Integer totalAssetsCount;
        @AuraEnabled public List<AssetRequestRecord> assetRequests;
        @AuraEnabled public List<AssetRequestRecord> allAssetRequests;
        @AuraEnabled public Integer assetRequestsCount;
        @AuraEnabled public Integer totalAssetRequestsCount;
        @AuraEnabled public List<BusinessRecord> recentInvoices;
        @AuraEnabled public Decimal pendingAmount;
        @AuraEnabled public Integer overdueCount;
        @AuraEnabled public Date lastPaymentDate;
        // Average of Payment_Score__c field from all related Payment records
        @AuraEnabled public Decimal paymentRating;
        // Average of Rating field from all related Visit records
        @AuraEnabled public Decimal visitRating;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String ownerEmail;
    }

    public class BusinessRecord {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date recordDate;
        @AuraEnabled public String status;
    }

    public class OrderProductRecord {
        @AuraEnabled public Id orderItemId;
        @AuraEnabled public Id orderId;
        @AuraEnabled public String orderName;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal totalPrice;
    }

    public class CaseRecord {
        @AuraEnabled public Id caseId;
        @AuraEnabled public Id orderId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String orderName;
        @AuraEnabled public String caseType;
        @AuraEnabled public String caseReason;
        @AuraEnabled public String solutionRequired;
        @AuraEnabled public String ownerName;
        @AuraEnabled public Decimal totalPrice;
    }

    public class AssetRecord {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String name;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String productName;
        @AuraEnabled public String status;
        @AuraEnabled public String outletName;
        @AuraEnabled public Date lastAuditDate;
        @AuraEnabled public String lastCondition;
    }

    public class AssetRequestRecord {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestNumber;
        @AuraEnabled public String productName;
        @AuraEnabled public String requestType;
        @AuraEnabled public String status;
        @AuraEnabled public Date requestedInstallationDate;
        @AuraEnabled public Datetime createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static Outlet360Response getOutlet360Summary(Id recordId, String objectApiName) {
        try {
            if (recordId == null) {
                throw new AuraHandledException('recordId is required.');
            }

            String resolvedObjectApiName = objectApiName;
            if (String.isBlank(resolvedObjectApiName)) {
                resolvedObjectApiName = recordId.getSObjectType().getDescribe().getName();
            }

            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
            Schema.SObjectType parentType = globalDescribe.get(resolvedObjectApiName);
            if (parentType == null) {
                resolvedObjectApiName = recordId.getSObjectType().getDescribe().getName();
                parentType = globalDescribe.get(resolvedObjectApiName);
            }
            if (parentType == null) {
                throw new AuraHandledException('Unable to resolve parent object.');
            }

            Schema.DescribeSObjectResult parentDescribe = parentType.getDescribe();
            List<Schema.ChildRelationship> childRelationships = parentDescribe.getChildRelationships();

            Outlet360Response response = new Outlet360Response();
            response.relatedLists = new List<RelatedListCount>();
            response.outletName = null;
            response.outletCode = null;
            response.outletStatus = null;
            response.outletPhone = null;
            response.outletAddress = null;
            response.totalRelationships = childRelationships.size();
            response.scannedRelationships = 0;
            response.isTruncated = false;
            response.pastRevenue = 0;
            response.ordersCount = 0;
            response.totalOrdersCount = 0;
            response.invoicesCount = 0;
            response.recentOrders = new List<BusinessRecord>();
            response.allOrders = new List<BusinessRecord>();
            response.orderProducts = new List<OrderProductRecord>();
            response.allOrderProducts = new List<OrderProductRecord>();
            response.orderProductsCount = 0;
            response.totalOrderProductsCount = 0;
            response.cases = new List<CaseRecord>();
            response.allCases = new List<CaseRecord>();
            response.casesCount = 0;
            response.totalCasesCount = 0;
            response.assets = new List<AssetRecord>();
            response.allAssets = new List<AssetRecord>();
            response.assetsCount = 0;
            response.totalAssetsCount = 0;
            response.assetRequests = new List<AssetRequestRecord>();
            response.allAssetRequests = new List<AssetRequestRecord>();
            response.assetRequestsCount = 0;
            response.totalAssetRequestsCount = 0;
            response.recentInvoices = new List<BusinessRecord>();
            response.pendingAmount = 0;
            response.overdueCount = 0;
            response.lastPaymentDate = null;
            // Initialize payment and visit ratings to 0
            response.paymentRating = 0;
            response.visitRating = 0;

            Integer scanned = 0;
            // Discover related lists dynamically so this works across managed/non-managed schemas.
            for (Schema.ChildRelationship childRel : childRelationships) {
                if (scanned >= MAX_RELATIONSHIPS_TO_SCAN) {
                    response.isTruncated = true;
                    break;
                }

                try {
                    Schema.SObjectType childType = childRel.getChildSObject();
                    Schema.SObjectField referenceField = childRel.getField();
                    if (childType == null || referenceField == null) {
                        continue;
                    }

                    Schema.DescribeSObjectResult childDescribe = childType.getDescribe();
                    Schema.DescribeFieldResult fieldDescribe = referenceField.getDescribe();
                    if (!childDescribe.isQueryable() || !fieldDescribe.isAccessible()) {
                        continue;
                    }

                    String childObjectApiName = childDescribe.getName();
                    String referenceFieldApiName = fieldDescribe.getName();
                    String relationshipName = childRel.getRelationshipName();
                    String label = String.isBlank(relationshipName)
                        ? childDescribe.getLabelPlural()
                        : relationshipName;

                    Integer rowCount = queryCountSafely(childObjectApiName, referenceFieldApiName, recordId);

                    scanned++;

                    if (rowCount > 0) {
                        RelatedListCount item = new RelatedListCount();
                        item.relationshipLabel = label;
                        item.relationshipName = relationshipName;
                        item.childObjectApiName = childObjectApiName;
                        item.referenceFieldApiName = referenceFieldApiName;
                        item.recordCount = rowCount;
                        response.relatedLists.add(item);
                    }
                } catch (Exception ex) {
                    // Ignore unsupported child relationships and continue scanning.
                    continue;
                }
            }

            response.scannedRelationships = scanned;
            sortRelatedLists(response.relatedLists);
            populateOutletHeader(response, recordId, resolvedObjectApiName, globalDescribe);
            // Populate business sections (orders/invoices/revenue) after generic related-list summary.
            populateBusinessSummary(response, recordId, globalDescribe);
            // Populate cases associated with the outlet
            populateCases(response, recordId, globalDescribe);
            // Populate assets associated with the outlet
            populateAssets(response, recordId);
            // Populate asset requests associated with the outlet
            populateAssetRequests(response, recordId);
            // Populate payment summary.
            populatePaymentSummary(response, recordId, globalDescribe);
            // Calculate payment rating: average of Payment_Score__c from Payment records
            response.paymentRating = calculatePaymentRating(recordId, globalDescribe);
            // Calculate visit rating: average of Rating field from Visit records
            response.visitRating = calculateVisitRating(recordId, globalDescribe);
            return response;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to load Outlet 360 summary. ' + ex.getMessage());
        }
    }

    private static void sortRelatedLists(List<RelatedListCount> items) {
        if (items == null || items.size() < 2) {
            return;
        }

        for (Integer i = 1; i < items.size(); i++) {
            RelatedListCount current = items[i];
            Integer j = i - 1;

            while (j >= 0 && shouldMoveBefore(items[j], current)) {
                items[j + 1] = items[j];
                j--;
            }

            items[j + 1] = current;
        }
    }

    private static Boolean shouldMoveBefore(RelatedListCount left, RelatedListCount right) {
        Integer leftCount = left == null || left.recordCount == null ? 0 : left.recordCount;
        Integer rightCount = right == null || right.recordCount == null ? 0 : right.recordCount;

        if (leftCount < rightCount) {
            return true;
        }
        if (leftCount > rightCount) {
            return false;
        }

        String leftLabel = left == null || left.relationshipLabel == null ? '' : left.relationshipLabel.toLowerCase();
        String rightLabel = right == null || right.relationshipLabel == null ? '' : right.relationshipLabel.toLowerCase();
        return leftLabel.compareTo(rightLabel) > 0;
    }

    private static Integer queryCountSafely(String childObjectApiName, String referenceFieldApiName, Id recordId) {
        if (String.isBlank(childObjectApiName) || String.isBlank(referenceFieldApiName) || recordId == null) {
            return 0;
        }

        try {
            // Avoid aggregate functions because some objects in orgs don't support COUNT().
            List<SObject> rows = Database.query(
                'SELECT Id FROM ' + childObjectApiName +
                ' WHERE ' + referenceFieldApiName + ' = :recordId' +
                ' LIMIT ' + FALLBACK_ROW_LIMIT
            );
            return rows.size();
        } catch (Exception nonAggregateException) {
            return 0;
        }
    }

    private static void populateBusinessSummary(
        Outlet360Response response,
        Id recordId,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        if (response == null || recordId == null) {
            return;
        }

        // Use only standard Order object for Outlet 360 order insights.
        List<String> orderObjectCandidates = new List<String>{ 'Order' };
        for (String ordersObject : orderObjectCandidates) {
            if (!globalDescribe.containsKey(ordersObject)) {
                continue;
            }
            response.ordersObjectApiName = ordersObject;
            populateOrderSummary(response, recordId, ordersObject, globalDescribe);
            if ((response.totalOrdersCount != null && response.totalOrdersCount > 0) ||
                (response.ordersCount != null && response.ordersCount > 0)) {
                break;
            }
        }

        String invoicesObject = findObject(globalDescribe, new List<String>{ 'Invoice__c', 'Invoice__c' });
        response.invoicesObjectApiName = invoicesObject;
        if (!String.isBlank(invoicesObject)) {
            // populateInvoiceSummary(response, recordId, invoicesObject, globalDescribe);
        }
    }

    private static void populateOutletHeader(
        Outlet360Response response,
        Id recordId,
        String objectApiName,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        if (response == null || recordId == null || String.isBlank(objectApiName)) {
            return;
        }
        if (!globalDescribe.containsKey(objectApiName)) {
            return;
        }

        Schema.DescribeSObjectResult describeResult = globalDescribe.get(objectApiName).getDescribe();
        Map<String, Schema.SObjectField> fieldsMap = describeResult.fields.getMap();

        String nameField = firstExisting(fieldsMap, new List<String>{ 'Name' });
        String codeField = firstExisting(fieldsMap, new List<String>{ 'Outlet_Code__c', 'Outlet_Code__c' });
        String statusField = firstExisting(fieldsMap, new List<String>{ 'OutletStatus__c', 'OutletStatus__c', 'Status__c' });
        String phoneField = firstExisting(fieldsMap, new List<String>{ 'Phone', 'Phone__c' });
        String streetField = firstExisting(fieldsMap, new List<String>{ 'ShippingStreet', 'BillingStreet' });
        String cityField = firstExisting(fieldsMap, new List<String>{ 'ShippingCity', 'BillingCity' });
        String stateField = firstExisting(fieldsMap, new List<String>{ 'ShippingState', 'BillingState' });
        String postalField = firstExisting(fieldsMap, new List<String>{ 'ShippingPostalCode', 'BillingPostalCode' });
        String countryField = firstExisting(fieldsMap, new List<String>{ 'ShippingCountry', 'BillingCountry' });
        String ownerNameField  = firstExisting(fieldsMap, new List<String>{ 'Owner_Name__c' });
        String ownerEmailField = firstExisting(fieldsMap, new List<String>{ 'Owner_Email__c' });

        List<String> selectFields = new List<String>{ 'Id' };
        if (!String.isBlank(nameField)) selectFields.add(nameField);
        if (!String.isBlank(codeField)) selectFields.add(codeField);
        if (!String.isBlank(statusField)) selectFields.add(statusField);
        if (!String.isBlank(phoneField)) selectFields.add(phoneField);
        if (!String.isBlank(streetField)) selectFields.add(streetField);
        if (!String.isBlank(cityField)) selectFields.add(cityField);
        if (!String.isBlank(stateField)) selectFields.add(stateField);
        if (!String.isBlank(postalField)) selectFields.add(postalField);
        if (!String.isBlank(countryField)) selectFields.add(countryField);
        if (!String.isBlank(ownerNameField))  selectFields.add(ownerNameField);
        if (!String.isBlank(ownerEmailField)) selectFields.add(ownerEmailField);

        try {
            List<SObject> rows = Database.query(
                'SELECT ' + String.join(selectFields, ',') +
                ' FROM ' + objectApiName +
                ' WHERE Id = :recordId LIMIT 1'
            );
            if (rows.isEmpty()) return;

            SObject row = rows[0];
            response.outletName = !String.isBlank(nameField) ? String.valueOf(row.get(nameField)) : null;
            response.outletCode = !String.isBlank(codeField) ? String.valueOf(row.get(codeField)) : null;
            response.outletStatus = !String.isBlank(statusField) ? String.valueOf(row.get(statusField)) : null;
            response.outletPhone = !String.isBlank(phoneField) ? String.valueOf(row.get(phoneField)) : null;

            List<String> addressParts = new List<String>();
            if (!String.isBlank(streetField) && row.get(streetField) != null) addressParts.add(String.valueOf(row.get(streetField)));
            if (!String.isBlank(cityField) && row.get(cityField) != null) addressParts.add(String.valueOf(row.get(cityField)));
            if (!String.isBlank(stateField) && row.get(stateField) != null) addressParts.add(String.valueOf(row.get(stateField)));
            if (!String.isBlank(postalField) && row.get(postalField) != null) addressParts.add(String.valueOf(row.get(postalField)));
            if (!String.isBlank(countryField) && row.get(countryField) != null) addressParts.add(String.valueOf(row.get(countryField)));
            response.outletAddress = addressParts.isEmpty() ? null : String.join(addressParts, ', ');
            response.ownerName  = !String.isBlank(ownerNameField)  && row.get(ownerNameField)  != null ? String.valueOf(row.get(ownerNameField))  : null;
            response.ownerEmail = !String.isBlank(ownerEmailField) && row.get(ownerEmailField) != null ? String.valueOf(row.get(ownerEmailField)) : null;
        } catch (Exception ex) {
            // Header info is best-effort and should not break the page.
        }
    }

    private static void populateOrderSummary(
        Outlet360Response response,
        Id recordId,
        String objectApiName,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        Schema.SObjectType orderType = globalDescribe.get(objectApiName);
        if (orderType == null) return;

        Map<String, Schema.SObjectField> fieldsMap = orderType.getDescribe().fields.getMap();
        String accountField = firstExisting(
            fieldsMap,
            new List<String>{ 'Franshise__c', 'Franshise', 'Franchise__c', 'Franchises__c', 'AccountId' }
        );
        if (String.isBlank(accountField)) return;

        String amountField = firstExisting(fieldsMap, new List<String>{ 'TotalAmount', 'Total_Price__c', 'Total_Price__c', 'Amount__c' });
        String dateField = firstExisting(fieldsMap, new List<String>{ 'EffectiveDate', 'Order_Date__c', 'Order_Date__c', 'CreatedDate' });
        String statusField = firstExisting(fieldsMap, new List<String>{ 'Status', 'Status__c', 'Status__c' });
        String nameField = firstExisting(fieldsMap, new List<String>{ 'OrderNumber', 'Name' });
        if (String.isBlank(nameField)) {
            nameField = 'Id';
        }

        Date sinceDate = Date.today().addDays(-90);
        List<String> selectFields = new List<String>{ 'Id', nameField, accountField };
        if (!String.isBlank(amountField)) selectFields.add(amountField);
        if (!String.isBlank(dateField) && dateField != 'CreatedDate') selectFields.add(dateField);
        if (!String.isBlank(statusField)) selectFields.add(statusField);

        String revenueSoql =
            'SELECT ' + String.join(selectFields, ',') +
            ' FROM ' + objectApiName +
            ' WHERE ' + accountField + ' = :recordId' +
            (!String.isBlank(dateField)
                ? (dateField == 'CreatedDate'
                    ? ' AND CreatedDate >= :sinceDate'
                    : ' AND ' + dateField + ' >= :sinceDate')
                : '') +
            ' ORDER BY ' + (!String.isBlank(dateField) ? dateField : 'CreatedDate') + ' DESC LIMIT 2000';

        Decimal revenue = 0;
        try {
            for (SObject row : Database.query(revenueSoql)) {
                if (!String.isBlank(amountField)) {
                    Object amountValue = row.get(amountField);
                    if (amountValue != null) {
                        revenue += Decimal.valueOf(String.valueOf(amountValue));
                    }
                }
            }
        } catch (Exception ex) {
            revenue = 0;
        }
        response.pastRevenue = revenue;

        String listSoql =
            'SELECT Id, ' + nameField +
            (!String.isBlank(amountField) ? (', ' + amountField) : '') +
            (!String.isBlank(dateField) ? (', ' + dateField) : '') +
            (!String.isBlank(statusField) ? (', ' + statusField) : '') +
            ' FROM ' + objectApiName +
            ' WHERE ' + accountField + ' = :recordId' +
            ' ORDER BY CreatedDate DESC LIMIT 5';

        try {
            List<SObject> recentRows = Database.query(listSoql);
            response.ordersCount = recentRows.size();
            for (SObject row : recentRows) {
                response.recentOrders.add(
                    toBusinessRecord(row, nameField, amountField, dateField, statusField)
                );
            }
        } catch (Exception ex) {
            response.ordersCount = 0;
        }

        try {
            response.totalOrdersCount = Database.countQuery(
                'SELECT COUNT() FROM ' + objectApiName + ' WHERE ' + accountField + ' = :recordId'
            );
        } catch (Exception ex) {
            response.totalOrdersCount = response.ordersCount;
        }

        String allOrdersSoql =
            'SELECT Id, ' + nameField +
            (!String.isBlank(amountField) ? (', ' + amountField) : '') +
            (!String.isBlank(dateField) ? (', ' + dateField) : '') +
            (!String.isBlank(statusField) ? (', ' + statusField) : '') +
            ' FROM ' + objectApiName +
            ' WHERE ' + accountField + ' = :recordId' +
            ' ORDER BY CreatedDate DESC LIMIT 200';

        List<Id> allOrderIds = new List<Id>();
        try {
            for (SObject row : Database.query(allOrdersSoql)) {
                response.allOrders.add(toBusinessRecord(row, nameField, amountField, dateField, statusField));
                allOrderIds.add((Id) row.get('Id'));
            }
        } catch (Exception ex) {
            response.allOrders = new List<BusinessRecord>();
        }

        populateOrderProducts(response, allOrderIds, objectApiName, globalDescribe);
    }

    // private static void populateInvoiceSummary(
    //     Outlet360Response response,
    //     Id recordId,
    //     String objectApiName,
    //     Map<String, Schema.SObjectType> globalDescribe
    // ) {
    //     Schema.SObjectType invoiceType = globalDescribe.get(objectApiName);
    //     if (invoiceType == null) return;

    //     Map<String, Schema.SObjectField> fieldsMap = invoiceType.getDescribe().fields.getMap();
    //     String accountField = firstExisting(
    //         fieldsMap,
    //         new List<String>{ 'Outlet__c', 'Outlet__c', 'Account__c', 'Account__c', 'Franchise__c', 'Franchise__c' }
    //     );
    //     if (String.isBlank(accountField)) return;

    //     String amountField = firstExisting(fieldsMap, new List<String>{ 'Total_Amount__c', 'Total_Amount__c', 'Amount__c', 'Amount__c' });
    //     String dateField = firstExisting(fieldsMap, new List<String>{ 'Invoice_Date__c', 'Invoice_Date__c', 'CreatedDate' });
    //     String statusField = firstExisting(fieldsMap, new List<String>{ 'Status__c', 'Status__c' });

    //     String listSoql =
    //         'SELECT Id, Name' +
    //         (!String.isBlank(amountField) ? (', ' + amountField) : '') +
    //         (!String.isBlank(dateField) ? (', ' + dateField) : '') +
    //         (!String.isBlank(statusField) ? (', ' + statusField) : '') +
    //         ' FROM ' + objectApiName +
    //         ' WHERE ' + accountField + ' = :recordId' +
    //         ' ORDER BY ' + (!String.isBlank(dateField) ? dateField : 'CreatedDate') + ' DESC LIMIT 5';

    //     try {
    //         List<SObject> recentRows = Database.query(listSoql);
    //         response.invoicesCount = recentRows.size();
    //         for (SObject row : recentRows) {
    //             response.recentInvoices.add(
    //                 toBusinessRecord(row, 'Name', amountField, dateField, statusField)
    //             );
    //         }
    //     } catch (Exception ex) {
    //         response.invoicesCount = 0;
    //     }
    // }

    private static void populateOrderProducts(
        Outlet360Response response,
        List<Id> orderIds,
        String orderObjectApiName,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        if (response == null || orderIds == null || orderIds.isEmpty()) {
            return;
        }

        if (orderObjectApiName == 'Order' && globalDescribe.containsKey('OrderItem')) {
            Map<String, Schema.SObjectField> oiFields = globalDescribe.get('OrderItem').getDescribe().fields.getMap();
            String productNameExpr = 'PricebookEntry.Product2.Name';
            String orderNameExpr = 'Order.OrderNumber';
            String quantityField = firstExisting(oiFields, new List<String>{ 'Quantity' });
            String unitPriceField = firstExisting(oiFields, new List<String>{ 'UnitPrice' });
            String totalPriceField = firstExisting(oiFields, new List<String>{ 'TotalPrice' });

            String soql =
                'SELECT Id, OrderId, ' + orderNameExpr + ', ' + productNameExpr +
                (!String.isBlank(quantityField) ? (', ' + quantityField) : '') +
                (!String.isBlank(unitPriceField) ? (', ' + unitPriceField) : '') +
                (!String.isBlank(totalPriceField) ? (', ' + totalPriceField) : '') +
                ' FROM OrderItem' +
                ' WHERE OrderId IN :orderIds' +
                ' ORDER BY CreatedDate DESC LIMIT 5';

            try {
                List<SObject> rows = Database.query(soql);
                response.orderProductsCount = rows.size();
                for (SObject row : rows) {
                    OrderProductRecord item = new OrderProductRecord();
                    item.orderItemId = (Id) row.get('Id');
                    item.orderId = (Id) row.get('OrderId');
                    SObject orderObj = row.getSObject('Order');
                    item.orderName = orderObj != null ? String.valueOf(orderObj.get('OrderNumber')) : null;
                    SObject pricebookEntry = row.getSObject('PricebookEntry');
                    SObject product = pricebookEntry != null ? pricebookEntry.getSObject('Product2') : null;
                    item.productName = product != null ? String.valueOf(product.get('Name')) : null;
                    item.quantity = !String.isBlank(quantityField) ? toDecimal(row.get(quantityField)) : 0;
                    item.unitPrice = !String.isBlank(unitPriceField) ? toDecimal(row.get(unitPriceField)) : 0;
                    item.totalPrice = !String.isBlank(totalPriceField) ? toDecimal(row.get(totalPriceField)) : 0;
                    response.orderProducts.add(item);
                }
            } catch (Exception ex) {
                response.orderProductsCount = 0;
            }

            // Query all order products for modal/view all
            String allProductsSoql =
                'SELECT Id, OrderId, ' + orderNameExpr + ', ' + productNameExpr +
                (!String.isBlank(quantityField) ? (', ' + quantityField) : '') +
                (!String.isBlank(unitPriceField) ? (', ' + unitPriceField) : '') +
                (!String.isBlank(totalPriceField) ? (', ' + totalPriceField) : '') +
                ' FROM OrderItem' +
                ' WHERE OrderId IN :orderIds' +
                ' ORDER BY CreatedDate DESC LIMIT 200';

            try {
                List<SObject> allRows = Database.query(allProductsSoql);
                response.totalOrderProductsCount = allRows.size();
                for (SObject row : allRows) {
                    OrderProductRecord item = new OrderProductRecord();
                    item.orderItemId = (Id) row.get('Id');
                    item.orderId = (Id) row.get('OrderId');
                    SObject orderObj = row.getSObject('Order');
                    item.orderName = orderObj != null ? String.valueOf(orderObj.get('OrderNumber')) : null;
                    SObject pricebookEntry = row.getSObject('PricebookEntry');
                    SObject product = pricebookEntry != null ? pricebookEntry.getSObject('Product2') : null;
                    item.productName = product != null ? String.valueOf(product.get('Name')) : null;
                    item.quantity = !String.isBlank(quantityField) ? toDecimal(row.get(quantityField)) : 0;
                    item.unitPrice = !String.isBlank(unitPriceField) ? toDecimal(row.get(unitPriceField)) : 0;
                    item.totalPrice = !String.isBlank(totalPriceField) ? toDecimal(row.get(totalPriceField)) : 0;
                    response.allOrderProducts.add(item);
                }
            } catch (Exception ex) {
                response.orderProducts = new List<OrderProductRecord>();
            }
            return;
        }

        // String customLineItemObject = findObject(globalDescribe, new List<String>{ 'Order_Line_Item__c', 'Order_Line_Item__c' });
        // if (String.isBlank(customLineItemObject)) {
        //     return;
        // }

        // Map<String, Schema.SObjectField> lineFields = globalDescribe.get(customLineItemObject).getDescribe().fields.getMap();
        // String orderLookupField = firstExisting(lineFields, new List<String>{ 'Order__c', 'Order__c' });
        // if (String.isBlank(orderLookupField)) {
        //     return;
        // }
        // String productLookupField = firstExisting(lineFields, new List<String>{ 'Product__c', 'Product__c' });
        // if (String.isBlank(productLookupField)) {
        //     return;
        // }
        // String productRelExpr = productLookupField == 'Product__c' ? 'Product__r.Name' : 'Product__r.Name';
        // String orderRelExpr = orderLookupField == 'Order__c' ? 'Order__r.Name' : 'Order__r.Name';
        // String quantityField = firstExisting(lineFields, new List<String>{ 'Quantity__c', 'Quantity__c' });
        // String unitPriceField = firstExisting(lineFields, new List<String>{ 'Unit_Price__c', 'Unit_Price__c' });
        // String totalPriceField = firstExisting(lineFields, new List<String>{ 'Total_Price__c', 'Total_Price__c' });

        // String soql =
        //     'SELECT Id, ' + orderLookupField + ', ' + orderRelExpr + ', ' + productRelExpr +
        //     (!String.isBlank(quantityField) ? (', ' + quantityField) : '') +
        //     (!String.isBlank(unitPriceField) ? (', ' + unitPriceField) : '') +
        //     (!String.isBlank(totalPriceField) ? (', ' + totalPriceField) : '') +
        //     ' FROM ' + customLineItemObject +
        //     ' WHERE ' + orderLookupField + ' IN :orderIds' +
        //     ' ORDER BY CreatedDate DESC LIMIT 200';

        // try {
        //     List<SObject> rows = Database.query(soql);
        //     for (SObject row : rows) {
        //         OrderProductRecord item = new OrderProductRecord();
        //         item.orderItemId = (Id) row.get('Id');
        //         item.orderId = (Id) row.get(orderLookupField);
        //         String orderRelName = orderLookupField == 'Order__c' ? 'Order__r' : 'Order__r';
        //         String productRelName = productLookupField == 'Product__c' ? 'Product__r' : 'Product__r';
        //         SObject orderObj = row.getSObject(orderRelName);
        //         SObject productObj = row.getSObject(productRelName);
        //         item.orderName = orderObj != null ? String.valueOf(orderObj.get('Name')) : null;
        //         item.productName = productObj != null ? String.valueOf(productObj.get('Name')) : null;
        //         item.quantity = !String.isBlank(quantityField) ? toDecimal(row.get(quantityField)) : 0;
        //         item.unitPrice = !String.isBlank(unitPriceField) ? toDecimal(row.get(unitPriceField)) : 0;
        //         item.totalPrice = !String.isBlank(totalPriceField) ? toDecimal(row.get(totalPriceField)) : 0;
        //         response.orderProducts.add(item);
        //     }
        // } catch (Exception ex) {
        //     response.orderProducts = new List<OrderProductRecord>();
        // }
    }

    private static void populateCases(
        Outlet360Response response,
        Id recordId,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        if (response == null || recordId == null) {
            return;
        }

        // Check if Case object exists in the org
        if (!globalDescribe.containsKey('Case')) {
            return;
        }

        try {
            // Query recent cases (5 most recent)
            List<Case> recentCaseRows = [
                SELECT Id, CaseNumber, Type, Reason, Solution_Required__c, Total_Price__c,
                       Order__c, Order__r.OrderNumber, OwnerId, Owner.Name, AccountId
                FROM Case
                WHERE AccountId = :recordId
                ORDER BY CreatedDate DESC
                LIMIT 5
            ];

            response.casesCount = recentCaseRows.size();

            // Build recent case records
            for (Case caseRecord : recentCaseRows) {
                response.cases.add(buildCaseRecord(caseRecord));
            }

            // Query all cases for modal/view all
            List<Case> allCaseRows = [
                SELECT Id, CaseNumber, Type, Reason, Solution_Required__c, Total_Price__c,
                       Order__c, Order__r.OrderNumber, OwnerId, Owner.Name, AccountId
                FROM Case
                WHERE AccountId = :recordId
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];

            response.totalCasesCount = allCaseRows.size();

            // Build all case records
            for (Case caseRecord : allCaseRows) {
                response.allCases.add(buildCaseRecord(caseRecord));
            }
        } catch (Exception ex) {
            // Case data is best-effort and should not break the page
            System.debug('Error loading cases: ' + ex.getMessage());
            response.cases = new List<CaseRecord>();
            response.allCases = new List<CaseRecord>();
        }
    }

    private static CaseRecord buildCaseRecord(Case caseRecord) {
        CaseRecord item = new CaseRecord();
        item.caseId = caseRecord.Id;
        item.caseNumber = caseRecord.CaseNumber;

        // If case has an Order reference, use the Order Number; otherwise use Case Number
        if (caseRecord.Order__c != null && caseRecord.Order__r != null &&
            String.isNotBlank(caseRecord.Order__r.OrderNumber)) {
            item.orderName = caseRecord.Order__r.OrderNumber;
        } else {
            item.orderName = '--';
        }

        item.caseType = caseRecord.Type != null ? String.valueOf(caseRecord.Type) : '';
        item.caseReason = caseRecord.Reason != null ? String.valueOf(caseRecord.Reason) : '';
        item.solutionRequired = caseRecord.Solution_Required__c != null
            ? String.valueOf(caseRecord.Solution_Required__c)
            : '';
        item.ownerName = caseRecord.Owner != null && String.isNotBlank(caseRecord.Owner.Name)
            ? caseRecord.Owner.Name
            : '';
        item.totalPrice = caseRecord.Total_Price__c != null ? caseRecord.Total_Price__c : 0;

        return item;
    }

    private static void populateAssets(Outlet360Response response, Id recordId) {
        if (response == null || recordId == null) {
            return;
        }

        try {
            Set<Id> plannedOrActiveAssetIds = new Set<Id>();
            for (Asset_Allocation__c allocation : [
                SELECT Asset__c
                FROM Asset_Allocation__c
                WHERE Account__c = :recordId
                AND Allocation_Status__c IN ('Planned', 'Active')
                AND Asset__c != null
                ORDER BY CreatedDate DESC
                LIMIT 200
            ]) {
                plannedOrActiveAssetIds.add(allocation.Asset__c);
            }

            List<Asset__c> assetRows = [
                SELECT Id, Name, Serial_Number__c, Asset_Status__c,
                       Current_Account__r.Name,
                       Product__r.Name,
                       (SELECT Condition__c, Visit__r.Visit_Date__c
                        FROM AssetAuditsByAsset__r
                        ORDER BY CreatedDate DESC
                        LIMIT 1)
                FROM Asset__c
                WHERE Current_Account__c = :recordId
                OR Id IN :plannedOrActiveAssetIds
                ORDER BY Name ASC
                LIMIT 200
            ];

            response.totalAssetsCount = assetRows.size();
            response.assetsCount = Math.min(assetRows.size(), 5);

            Integer index = 0;
            for (Asset__c assetRow : assetRows) {
                AssetRecord item = buildAssetRecord(assetRow);
                response.allAssets.add(item);
                if (index < 5) {
                    response.assets.add(item);
                }
                index++;
            }
        } catch (Exception ex) {
            System.debug('Error loading assets: ' + ex.getMessage());
            response.assets = new List<AssetRecord>();
            response.allAssets = new List<AssetRecord>();
            response.assetsCount = 0;
            response.totalAssetsCount = 0;
        }
    }

    private static AssetRecord buildAssetRecord(Asset__c assetRow) {
        AssetRecord item = new AssetRecord();
        item.assetId = assetRow.Id;
        item.name = assetRow.Name;
        item.serialNumber = assetRow.Serial_Number__c;
        item.productName = assetRow.Product__r != null ? assetRow.Product__r.Name : null;
        item.status = assetRow.Asset_Status__c;
        item.outletName = assetRow.Current_Account__r != null ? assetRow.Current_Account__r.Name : null;

        if (assetRow.AssetAuditsByAsset__r != null && !assetRow.AssetAuditsByAsset__r.isEmpty()) {
            Asset_Audit__c latestAudit = assetRow.AssetAuditsByAsset__r[0];
            item.lastCondition = latestAudit.Condition__c;
            if (latestAudit.Visit__r != null) {
                item.lastAuditDate = latestAudit.Visit__r.Visit_Date__c;
            }
        }

        return item;
    }

    private static void populateAssetRequests(Outlet360Response response, Id recordId) {
        if (response == null || recordId == null) {
            return;
        }

        try {
            List<Asset_Request__c> requestRows = [
                SELECT Id, Name, Request_Type__c, Status__c, Requested_Installation_Date__c, CreatedDate,
                       Requested_Catalog_Item__r.Name
                FROM Asset_Request__c
                WHERE Account__c = :recordId
                ORDER BY CreatedDate DESC
                LIMIT 200
            ];

            response.totalAssetRequestsCount = requestRows.size();
            response.assetRequestsCount = Math.min(requestRows.size(), 5);

            Integer index = 0;
            for (Asset_Request__c requestRow : requestRows) {
                AssetRequestRecord item = buildAssetRequestRecord(requestRow);
                response.allAssetRequests.add(item);
                if (index < 5) {
                    response.assetRequests.add(item);
                }
                index++;
            }
        } catch (Exception ex) {
            System.debug('Error loading asset requests: ' + ex.getMessage());
            response.assetRequests = new List<AssetRequestRecord>();
            response.allAssetRequests = new List<AssetRequestRecord>();
            response.assetRequestsCount = 0;
            response.totalAssetRequestsCount = 0;
        }
    }

    private static AssetRequestRecord buildAssetRequestRecord(Asset_Request__c requestRow) {
        AssetRequestRecord item = new AssetRequestRecord();
        item.requestId = requestRow.Id;
        item.requestNumber = requestRow.Name;
        item.productName = requestRow.Requested_Catalog_Item__r != null
            ? requestRow.Requested_Catalog_Item__r.Name
            : null;
        item.requestType = requestRow.Request_Type__c;
        item.status = requestRow.Status__c;
        item.requestedInstallationDate = requestRow.Requested_Installation_Date__c;
        item.createdDate = requestRow.CreatedDate;
        return item;
    }

    private static void populatePaymentSummary(
        Outlet360Response response,
        Id recordId,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        if (response == null || recordId == null) {
            return;
        }

        // Check if Payment object exists in the org
        if (!globalDescribe.containsKey('Payment')) {
            return;
        }

        try {
            // Query Payment records linked to the account
            List<Payment> payments = [
                SELECT Id, Amount, Date, Outstanding_Amount__c, Payment_Status__c
                FROM Payment
                WHERE AccountId = :recordId
                ORDER BY Date DESC
                LIMIT 500
            ];

            if (payments.isEmpty()) {
                response.pendingAmount = 0;
                response.overdueCount = 0;
                response.lastPaymentDate = null;
                return;
            }

            Decimal pendingAmount = 0;
            Integer overdueCount = 0;
            Date lastPaymentDate = null;

            for (Payment payment : payments) {
                // Calculate pending amount (sum of outstanding amounts for Pending and Overdue status)
                if ((payment.Payment_Status__c == 'Pending' || payment.Payment_Status__c == 'Overdue') &&
                    payment.Outstanding_Amount__c != null) {
                    pendingAmount += payment.Outstanding_Amount__c;
                }

                // Count overdue payments
                if (payment.Payment_Status__c == 'Overdue') {
                    overdueCount++;
                }

                // Get the most recent payment date (only for paid payments)
                //&& payment.Payment_Status__c == 'Paid'
                if (lastPaymentDate == null  && payment.Date != null) {
                    lastPaymentDate = ((Datetime) payment.Date).date();
                }
            }

            response.pendingAmount = pendingAmount;
            response.overdueCount = overdueCount;
            response.lastPaymentDate = lastPaymentDate;
        } catch (Exception ex) {
            // Payment data is best-effort and should not break the page
            response.pendingAmount = 0;
            response.overdueCount = 0;
            response.lastPaymentDate = null;
        }
    }

    private static BusinessRecord toBusinessRecord(
        SObject row,
        String nameField,
        String amountField,
        String dateField,
        String statusField
    ) {
        BusinessRecord item = new BusinessRecord();
        item.recordId = (Id) row.get('Id');
        item.name = !String.isBlank(nameField) ? String.valueOf(row.get(nameField)) : String.valueOf(row.get('Id'));
        item.amount = 0;
        item.recordDate = null;
        item.status = null;

        if (!String.isBlank(amountField)) {
            Object amountValue = row.get(amountField);
            if (amountValue != null) {
                item.amount = Decimal.valueOf(String.valueOf(amountValue));
            }
        }

        if (!String.isBlank(dateField)) {
            Object dateValue = row.get(dateField);
            if (dateValue instanceof Date) {
                item.recordDate = (Date) dateValue;
            } else if (dateValue instanceof Datetime) {
                item.recordDate = ((Datetime) dateValue).date();
            }
        }

        if (!String.isBlank(statusField)) {
            Object statusValue = row.get(statusField);
            if (statusValue != null) {
                item.status = String.valueOf(statusValue);
            }
        }
        return item;
    }

    private static Decimal toDecimal(Object value) {
        if (value == null) return 0;
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception ex) {
            return 0;
        }
    }

    private static String findObject(Map<String, Schema.SObjectType> globalDescribe, List<String> candidates) {
        if (globalDescribe == null || candidates == null) return null;
        for (String name : candidates) {
            if (globalDescribe.containsKey(name)) return name;
        }
        return null;
    }

    /**
     * Calculate the average Payment Score from all Payment records linked to the account
     * Payment Score is a numeric field that rates payment quality
     * @param recordId The Account record ID
     * @param globalDescribe Map of all SObject types in the org
     * @return Decimal Average payment score, or 0 if no payments found
     */
    private static Decimal calculatePaymentRating(
        Id recordId,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        if (recordId == null || globalDescribe == null) {
            return 0;
        }

        // Check if Payment object exists in the org
        if (!globalDescribe.containsKey('Payment')) {
            return 0;
        }

        try {
            // Query all Payment records with Payment_Score__c field
            // Payment_Score__c is a number field that rates payment quality (0-5 scale)
            List<AggregateResult> paymentAggregates = [
                SELECT AVG(Payment_Score__c) avgScore
                FROM Payment
                WHERE AccountId = :recordId
                    AND Payment_Score__c != null
            ];

            if (paymentAggregates.isEmpty() || paymentAggregates[0].get('avgScore') == null) {
                return 0;
            }

            Decimal avgPaymentScore = (Decimal) paymentAggregates[0].get('avgScore');
            return avgPaymentScore != null ? avgPaymentScore : 0;
        } catch (Exception ex) {
            // Payment rating calculation is best-effort; failure should not break the page
            return 0;
        }
    }

    /**
     * Calculate the average Rating from all Visit records linked to the account
     * Rating is a numeric field that rates visit quality/effectiveness
     * @param recordId The Account record ID
     * @param globalDescribe Map of all SObject types in the org
     * @return Decimal Average visit rating, or 0 if no visits found
     */
    private static Decimal calculateVisitRating(
        Id recordId,
        Map<String, Schema.SObjectType> globalDescribe
    ) {
        if (recordId == null || globalDescribe == null) {
            return 0;
        }

        // Check if Visit object exists in the org
        if (!globalDescribe.containsKey('Visit')) {
            return 0;
        }

        try {
            // Query all Visit records with Rating field
            // Rating is a number field that rates visit quality/effectiveness
            List<AggregateResult> visitAggregates = [
                SELECT AVG(Rating__c) avgRating
                FROM Visit__c
                WHERE Outlet1__c = :recordId
                    AND Rating__c != null
            ];

            if (visitAggregates.isEmpty() || visitAggregates[0].get('avgRating') == null) {
                return 0;
            }

            Decimal avgVisitRating = (Decimal) visitAggregates[0].get('avgRating');
            return avgVisitRating != null ? avgVisitRating : 0;
        } catch (Exception ex) {
            // Visit rating calculation is best-effort; failure should not break the page
            return 0;
        }
    }

    private static String firstExisting(Map<String, Schema.SObjectField> fieldsMap, List<String> candidates) {
        if (fieldsMap == null || candidates == null) return null;
        for (String apiName : candidates) {
            if (apiName == 'CreatedDate' || fieldsMap.containsKey(apiName)) {
                return apiName;
            }
        }
        return null;
    }

    /**
     * Creates a new Contact linked to the given Account (the outlet record).
     * accountId comes from the LWC recordId and is never shown in the UI form.
     * Salutation and LastName are mandatory; FirstName, MobilePhone and Email are optional.
     */
    @AuraEnabled
    public static Id createContact(
        Id     accountId,
        String salutation,
        String firstName,
        String lastName,
        String phone,
        String email
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required to create a contact.');
        }
        if (String.isBlank(salutation)) {
            throw new AuraHandledException('Salutation is required.');
        }
        if (String.isBlank(lastName)) {
            throw new AuraHandledException('Last Name is required.');
        }

        try {
            Contact c = new Contact();
            c.AccountId   = accountId;
            c.Salutation  = salutation;
            c.FirstName   = String.isBlank(firstName) ? null : firstName.trim();
            c.LastName    = lastName.trim();
            c.MobilePhone = String.isBlank(phone) ? null : phone.trim();
            c.Email       = String.isBlank(email) ? null : email.trim();
            insert c;
            return c.Id;
        } catch (DmlException dmlEx) {
            throw new AuraHandledException(dmlEx.getDmlMessage(0));
        } catch (Exception ex) {
            throw new AuraHandledException('Unable to create contact: ' + ex.getMessage());
        }
    }
}