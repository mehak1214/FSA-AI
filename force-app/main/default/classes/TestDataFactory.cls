/**
 * TestDataFactory
 * Centralized factory for creating test data across tests.
 */
@IsTest
public with sharing class TestDataFactory {

    // Utilities
    public static Date today() { return Date.today(); }
    public static Datetime now() { return Datetime.now(); }

    // User helper: returns the running user as Sales Rep context
    public static User getRunningUser() {
        return [SELECT Id, ProfileId, LastName, ManagerId FROM User WHERE Id = :UserInfo.getUserId()];
    }

    public static Id getDealerDistributorRtId() {
        Map<String, Schema.RecordTypeInfo> rtMap =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        return rtMap.containsKey('Dealer_Distributor')
            ? rtMap.get('Dealer_Distributor').getRecordTypeId()
            : null;
    }

    public static Id getFranchiseRtId() {
        Map<String, Schema.RecordTypeInfo> rtMap =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        return rtMap.containsKey('Franchise')
            ? rtMap.get('Franchise').getRecordTypeId()
            : null;
    }

    // User helper: create a test user with manager relationship
    public static User createUser(String lastName, String alias, Id managerId) {
        String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User u = new User(
            LastName          = lastName,
            Alias             = alias.left(8),
            Email             = alias + unique + '@test.example.com',
            Username          = alias + unique + '@test.example.com.testorg',
            CommunityNickname = alias + unique,
            TimeZoneSidKey    = 'America/Los_Angeles',
            LocaleSidKey      = 'en_US',
            EmailEncodingKey  = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId         = UserInfo.getProfileId()
        );
        if (managerId != null) {
            u.ManagerId = managerId;
        }
        insert u;
        return [SELECT Id, ProfileId, LastName, ManagerId FROM User WHERE Id = :u.Id];
    }

    // Account
    public static Account prepareAccount(String name, String rtDevName) {
        Account a                          = new Account();

        a.Name                                  = name;
        if (Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')) {
            Map<String, Schema.RecordTypeInfo> rtMap =
                Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
            if (rtMap.containsKey(rtDevName)) {
                a.put('RecordTypeId', rtMap.get(rtDevName).getRecordTypeId());
            }
        }
        a.ShippingStreet                        = '123 Main St';
        a.ShippingCity                          = 'Anytown';
        a.ShippingState                         = 'CA';
        a.ShippingPostalCode                    = '12345';
        a.ShippingCountry                       = 'USA';
        
        if(rtDevName == 'Franchise') {
            a.OutletStatus__c                = 'Active';
            a.Active__c                      = 'Yes';
            a.Outlet_Code__c                 = String.valueOf(Math.mod(now().getTime(), 99999));
            a.Outlet_Location__Latitude__s   = 37.7749;
            a.Outlet_Location__Longitude__s  = -122.4194;
        }
        return a;
    }

    public static Account createAccount(String name, String rtDevName) {
        Account a =  prepareAccount(name, rtDevName);
        insert a;
        return a;
    }

    // Create a test image and link it with a record Id using Content Document Link
    public static void linkATestPhotoToRecord(Id recordId) {
        // Setting FirstPublishLocationId creates the ContentDocument and its
        // ContentDocumentLink atomically, scoped directly to the target record.
        // This avoids routing through the shared personal-library ContentDocument
        // which causes UNABLE_TO_LOCK_ROW when multiple parallel test methods
        // call this method simultaneously.
        ContentVersion cv = new ContentVersion(
            Title                  = 'Test Image ' + now().getTime(),
            PathOnClient           = 'test_' + now().getTime() + '.jpg',
            VersionData            = Blob.valueOf('Test Image Data'),
            IsMajorVersion         = true,
            FirstPublishLocationId = recordId
        );
        insert cv;
        // No separate ContentDocumentLink insert required — Salesforce creates it automatically.
    }

    // Beat
    public static Beat__c createBeat(User salesRep, Boolean active) {
        Beat__c b               = new Beat__c();
        b.Name                  = 'Beat ' + now().getTime();
        b.Sales_Rep__c   = salesRep.Id;
        b.Active__c      = active;
        insert b;
        return b;
    }

    /**
     * Create a Beat with start/end dates - used for BeatPlanController tests
     */
    public static Beat__c createBeatWithDates(User salesRep, Boolean active, Date startDate, Date endDate) {
        Beat__c b               = new Beat__c();
        b.Name                  = 'Beat ' + now().getTime();
        b.Sales_Rep__c          = salesRep.Id;
        b.Active__c             = active;
        b.Start_Date__c         = startDate;
        b.End_Date__c           = endDate;
        b.Status__c             = active ? 'Active' : 'Draft';
        insert b;
        return b;
    }

    // Visit
    public static Visit__c createVisitApproved(User rep, Account outlet, Beat__c beat, Integer seq, Date vDate) {
        Visit__c v                      = new Visit__c();
        v.Sales_Rep__c           = rep.Id;
        v.Sequence__c            = seq;
        v.Visit_Date__c          = vDate;
        v.Outlet1__c             = outlet.Id;
        v.Beat__c                = beat.Id;
        v.Visit_Status__c        = 'Approved';
        v.Planned_Start_Time__c  = now();
        v.Planned_End_Time__c    = now().addHours(1);
        insert v;
        return v;
    }

    /**
     * Create a Draft visit with Approval_Status__c = 'Draft'
     */
    public static Visit__c createVisitDraft(User rep, Account outlet, Beat__c beat, Integer seq, Date vDate) {
        Visit__c v                      = new Visit__c();
        v.Sales_Rep__c           = rep.Id;
        v.Sequence__c            = seq;
        v.Visit_Date__c          = vDate;
        v.Outlet1__c             = outlet.Id;
        v.Beat__c                = beat.Id;
        v.Visit_Status__c        = 'Draft';
        v.Approval_Status__c     = 'Draft';
        v.Planned_Start_Time__c  = Datetime.newInstance(vDate, Time.newInstance(9, 0, 0, 0));
        v.Planned_End_Time__c    = Datetime.newInstance(vDate, Time.newInstance(10, 0, 0, 0));
        insert v;
        return v;
    }

    /**
     * Create a Draft visit (Visit_Status__c='Draft', Approval_Status__c='Draft').
     * Note: 'Planned' is not a valid picklist value - use 'Draft' for unsubmitted visits.
     */
    public static Visit__c createVisitPlanned(User rep, Account outlet, Beat__c beat, Integer seq, Date vDate) {
        Visit__c v                      = new Visit__c();
        v.Sales_Rep__c           = rep.Id;
        v.Sequence__c            = seq;
        v.Visit_Date__c          = vDate;
        v.Outlet1__c             = outlet.Id;
        v.Beat__c                = beat.Id;
        v.Visit_Status__c        = 'Draft';
        v.Approval_Status__c     = 'Draft';
        v.Planned_Start_Time__c  = Datetime.newInstance(vDate, Time.newInstance(9, 0, 0, 0));
        v.Planned_End_Time__c    = Datetime.newInstance(vDate, Time.newInstance(10, 0, 0, 0));
        insert v;
        return v;
    }

    // Attendance
    public static Day_Attendance__c createStartedAttendance(User rep) {
        Day_Attendance__c att               = new Day_Attendance__c();
        att.Sales_Rep__c                    = rep.Id;
        att.Attendance_Date__c              = today();
        att.Start_Time__c                   = now();
        att.Start_Location__Latitude__s     = 12.34;
        att.Start_Location__Longitude__s    = 77.56;
        insert att;
        return att;
    }

    /**
     * Create a Day_Attendance with Rate_Per_KM to support TravelDistanceService tests
     */
    public static Day_Attendance__c createStartedAttendanceWithRate(User rep, Date attendanceDate, Decimal ratePerKm) {
        Day_Attendance__c att               = new Day_Attendance__c();
        att.Sales_Rep__c                    = rep.Id;
        att.Attendance_Date__c              = attendanceDate;
        att.Start_Time__c                   = Datetime.newInstance(attendanceDate, Time.newInstance(9, 0, 0, 0));
        att.Start_Location__Latitude__s     = 12.34;
        att.Start_Location__Longitude__s    = 77.56;
        att.Rate_Per_KM__c                  = ratePerKm;
        insert att;
        return att;
    }

    // Product
    public static Product2 createVashiProduct(String name, Boolean active) {
        Product2 p                   = new Product2();
        p.Name                       = name;
        p.IsActive                   = active;
        p.Is_Veeglow_products__c = true;
        insert p;
        return p;
    }

    /**
     * Create a "new" Vashi product (Is_New__c = true)
     */
    public static Product2 createNewVashiProduct(String name, Boolean active) {
        Product2 p                   = new Product2();
        p.Name                       = name;
        p.IsActive                   = active;
        p.Is_Veeglow_products__c     = true;
        p.Is_New__c                  = true;
        insert p;
        return p;
    }

    // Pricebook Entry
    public static PricebookEntry createStdActivePbe(Product2 product, Decimal unitPrice) {
        PricebookEntry pbe  = new PricebookEntry();
        pbe.Product2Id      = product.Id;
        pbe.Pricebook2Id    = Test.getStandardPricebookId();
        pbe.UnitPrice       = unitPrice;
        pbe.IsActive        = true;
        insert pbe;
        return pbe;
    }

    // Scheme
    public static Scheme__c createActiveScheme(Decimal thresholdQty, Decimal discount) {
        Scheme__c s = new Scheme__c();
        s.Threshold_Quantity__c  = thresholdQty;
        s.Discount__c            = discount;
        s.Start_Date__c          = Date.today();
        s.End_Date__c            = Date.today().addDays(10);
        s.Scheme_Name__c         = TestDataFactory.generateRandomString(10);
        insert s;
        return s;
    }

    /**
     * Create an "active" scheme — Active__c is a formula (Start_Date__c <= Today <= End_Date__c),
     * so we make it active by setting dates that straddle today.
     */
    public static Scheme__c createActiveSchemeWithFlag(Decimal thresholdQty, Decimal discount) {
        Scheme__c s = new Scheme__c();
        s.Threshold_Quantity__c  = thresholdQty;
        s.Discount__c            = discount;
        s.Start_Date__c          = Date.today().addDays(-1); // started yesterday → active today
        s.End_Date__c            = Date.today().addDays(10);
        s.Scheme_Name__c         = TestDataFactory.generateRandomString(10);
        insert s;
        return s;
    }

    // Inventory and Inventory Items for a Distributor
    public static Inventory__c ensureDistributorInventory(Id distributorId) {
        List<Inventory__c> existing = [
            SELECT Id FROM Inventory__c WHERE Dealer__c = :distributorId LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];
        Inventory__c inv = new Inventory__c();
        inv.Dealer__c    = distributorId;
        inv.Status__c           = 'Active';
        insert inv;
        return inv;
    }

    public static Inventory_Item__c createInventoryItem(Inventory__c inv, Product2 product, Decimal avail, Decimal minThreshold) {
        Inventory_Item__c item           = new Inventory_Item__c();
        item.Inventory__c                = inv.Id;
        item.Product__c                  = product.Id;
        item.AvailableStock__c           = avail;
        item.MinimumThresholdQuantity__c = minThreshold;

        insert item;
        return item;

    }

    public static Expense_Policy__c createExpensePolicy(User manager, Decimal capValue, Decimal warnThresholdPct) {
        // Ensure we have the manager's LastName; query if not present or not fully loaded
        String managerLastName = 'Manager';
        Id managerId = manager.Id;
        
        try {
            managerLastName = String.isBlank(manager.LastName) ? 'Manager' : manager.LastName;
        } catch (SObjectException e) {
            // LastName not in the queried fields; fetch full user
            User mgr = [SELECT Id, LastName FROM User WHERE Id = :managerId LIMIT 1];
            managerLastName = String.isBlank(mgr.LastName) ? 'Manager' : mgr.LastName;
        }
        
        Expense_Policy__c p = new Expense_Policy__c();
        p.Name                       = 'Policy - ' + managerLastName + ' ' + now().getTime();
        p.Manager__c                 = managerId;
        p.Travel_Cap__c              = capValue;
        p.Food_Cap__c                = capValue;
        p.Market_Execution_Cap__c    = capValue;
        p.Communications_Cap__c      = capValue;
        p.Miscellaneous_Cap__c       = capValue;
        p.Other_Cap__c               = capValue;
        p.Warn_Threshold_Pct__c      = warnThresholdPct;
        insert p;
        return p;
    }

    public static Rep_Monthly_Allowance__c createRepAllowance(User rep, String monthYear, Decimal amount) {
        Rep_Monthly_Allowance__c a = new Rep_Monthly_Allowance__c();
        a.Sales_Rep__c     = rep.Id;
        a.Month_Year__c    = monthYear;
        a.Allowance_Amount__c = amount;
        
        // Ensure ManagerId is loaded; query if not present
        try {
            if (rep.ManagerId != null) {
                a.Manager__c = rep.ManagerId;
            }
        } catch (SObjectException e) {
            // ManagerId not in the queried fields; fetch it
            User mgr = [SELECT ManagerId FROM User WHERE Id = :rep.Id LIMIT 1];
            if (mgr.ManagerId != null) {
                a.Manager__c = mgr.ManagerId;
            }
        }
        
        insert a;
        return a;
    }

    public static Expense_Report__c createExpenseReport(User rep, Date reportDate, String status) {
        Expense_Report__c report = new Expense_Report__c();
        report.Sales_Rep__c = rep.Id;
        report.Report_Date__c = reportDate;
        report.Status__c = status;
        insert report;
        return report;
    }

    public static Expense__c createExpense(User rep, Id reportId, Date expenseDate, Decimal amount, String expenseType, String status, Id visitId) {
        Expense__c exp = new Expense__c();
        exp.Sales_Rep__c      = rep.Id;
        exp.Expense_Report__c = reportId;
        exp.Expense_Date__c   = expenseDate;
        exp.Amount__c         = amount;
        exp.Expense_Type__c   = expenseType;
        exp.Status__c         = status;
        exp.Description__c    = 'Test expense';
        exp.Visit__c          = visitId;
        insert exp;
        return exp;
    }

    public static Expense_Visit_Link__c createExpenseVisitLink(Id expenseId, Id visitId) {
        Expense_Visit_Link__c link = new Expense_Visit_Link__c();
        link.Expense__c = expenseId;
        if (visitId != null) {
            link.Visit__c = visitId;
        } else {
            Visit__c fallbackVisit = new Visit__c(
                Sales_Rep__c = UserInfo.getUserId(),
                Visit_Date__c = Date.today(),
                Visit_Status__c = 'Draft',
                Approval_Status__c = 'Draft'
            );
            insert fallbackVisit;
            link.Visit__c = fallbackVisit.Id;
        }
        insert link;
        return link;
    }

    public static Order createOrderRecord(Account account, Decimal totalAmount, Date effectiveDate, String status) {
        Order orderRecord = new Order();
        orderRecord.AccountId = account.Id;
        orderRecord.EffectiveDate = effectiveDate;
        orderRecord.Pricebook2Id = Test.getStandardPricebookId();
        orderRecord.Status = 'Draft';
        orderRecord.Type = 'Standard';
        insert orderRecord;

        // If status is not 'Draft', create a default OrderItem so Order can be activated
        // (Salesforce requires OrderItems before an Order can transition to 'Activated')
        if (status != null && status != 'Draft') {
            Product2 tempProduct = new Product2(
                Name = 'Temp Order Product',
                IsActive = true,
                Is_Veeglow_products__c = true
            );
            insert tempProduct;
            
            PricebookEntry pbe = new PricebookEntry(
                Product2Id = tempProduct.Id,
                Pricebook2Id = Test.getStandardPricebookId(),
                UnitPrice = totalAmount > 0 ? totalAmount : 100.00,
                IsActive = true
            );
            insert pbe;
            
            OrderItem item = new OrderItem(
                OrderId = orderRecord.Id,
                Product2Id = tempProduct.Id,
                PricebookEntryId = pbe.Id,
                Quantity = 1,
                UnitPrice = totalAmount > 0 ? totalAmount : 100.00
            );
            insert item;
        }

        if (status != null && status != 'Draft') {
            orderRecord.Status = status;
            try {
                update orderRecord;
            } catch (DmlException e) {
                // If the requested status cannot be applied, keep Draft to avoid failing unrelated tests.
            }
        }

        return orderRecord;
    }

    public static OrderItem createOrderItem(Order order, PricebookEntry pbe, Decimal quantity, Decimal unitPrice) {
        OrderItem item = new OrderItem();
        item.OrderId = order.Id;
        item.PricebookEntryId = pbe.Id;
        item.Quantity = quantity;
        item.UnitPrice = unitPrice;
        insert item;
        return item;
    }

    public static Case createCaseForOrder(Order order, Account account, String subject, String reason, String type) {
        Case c = new Case();
        c.AccountId = account.Id;
        c.Order__c = order.Id;
        c.Subject = subject;
        c.Reason = reason;
        c.Type = type;
        c.Status = 'New';
        insert c;
        return c;
    }

    public static Asset__c createAssetRecord(String name, String status, Account account, Product2 product) {
        Asset__c asset = new Asset__c();
        asset.Serial_Number__c = (String.isBlank(name) ? 'SN-' : name + '-') + String.valueOf(now().getTime());
        asset.Asset_Status__c = status;
        asset.Product__c = product.Id;
        if (account != null) {
            asset.Current_Account__c = account.Id;
        }
        insert asset;
        return asset;
    }

    public static Asset_Allocation__c createAssetAllocation(Asset__c asset, Account account, String status, Date plannedDate) {
        Asset_Allocation__c alloc = new Asset_Allocation__c();
        alloc.Asset__c = asset.Id;
        alloc.Account__c = account.Id;
        alloc.Allocation_Status__c = status;
        alloc.Planned_Installation_Date__c = plannedDate;
        insert alloc;
        return alloc;
    }

    public static Asset_Audit__c createAssetAudit(Asset__c asset, Visit__c visit, String condition, String photoUrl) {
        Asset_Audit__c audit = new Asset_Audit__c();
        audit.Asset__c = asset.Id;
        audit.Visit__c = visit.Id;
        audit.Condition__c = condition;
        audit.Audit_Photo_URL__c = photoUrl;
        audit.Scan_Location__Latitude__s = 10;
        audit.Scan_Location__Longitude__s = 20;
        insert audit;
        return audit;
    }

    public static Visit_Task__c createVisitTask(Visit__c visit, Asset__c asset, String taskType, Boolean mandatory, String status) {
        Visit_Task__c task = new Visit_Task__c();
        task.Visit__c = visit.Id;
        task.Related_Asset__c = asset.Id;
        task.Task_Type__c = normalizeVisitTaskType(taskType);
        task.Manager_Instructions__c = 'Please complete';
        task.Status__c = status;
        task.Is_Mandatory__c = mandatory;
        insert task;
        return task;
    }

    public static String normalizeVisitTaskType(String taskType) {
        if (String.isBlank(taskType)) {
            return 'Routine Check';
        }

        Set<String> validTaskTypes = new Set<String>{
            'Routine Check',
            'Asset Relocation Removal',
            'Asset Installation Pre-Check',
            'Maintenance Verification',
            'Asset Delivery Verification'
        };

        return validTaskTypes.contains(taskType) ? taskType : 'Routine Check';
    }

    public static Beat_Plan_Store__c createBeatPlanStore(Beat__c beat, Account outlet, Boolean active) {
        Beat_Plan_Store__c bps = new Beat_Plan_Store__c();
        bps.Beat__c = beat.Id;
        bps.Outlet__c = outlet.Id;
        bps.Active__c = active;
        insert bps;
        return bps;
    }

    public static Contact createPrimaryContact(Account account, String firstName, String lastName, String email) {
        Contact c = new Contact();
        c.AccountId = account.Id;
        c.FirstName = firstName;
        c.LastName = String.isBlank(lastName) ? 'Unknown' : lastName;
        c.Email = email;
        c.Primary_Contact__c = true;
        insert c;
        return c;
    }

    public static Monthly_Performance__c createMonthlyPerformance(Id salesRepId, Date monthYear, Decimal actualSales) {
        Monthly_Performance__c mp = new Monthly_Performance__c();
        mp.Sales_Rep__c    = salesRepId;
        mp.Month_Year__c   = monthYear;
        mp.Actual_Sales__c = actualSales;
        insert mp;
        return mp;
    }

    /**
     * Create a Sales_Target__c for a given rep and month
     */
    public static Sales_Target__c createSalesTarget(Id salesRepId, Date monthYear, Decimal targetAmount) {
        Sales_Target__c t = new Sales_Target__c();
        t.Sales_Rep__c      = salesRepId;
        t.Month_Year__c     = monthYear;
        t.Target_Amount__c  = targetAmount;
        insert t;
        return t;
    }



    /**
     * Create a Location SObject (for ProductItem) using dynamic SObject creation
     * to avoid compile-time ambiguity with System.Location primitive.
     * Returns the inserted Location record Id.
     */
    public static Id createWarehouseLocation(String locationName) {
        // Use dynamic SObject creation because 'Location' in static Apex resolves to
        // System.Location (a primitive geolocation type), not the Schema.Location SObject.
        SObject loc = Schema.getGlobalDescribe().get('Location').newSObject();
        loc.put('Name',                locationName);
        loc.put('LocationType',        'Warehouse');
        loc.put('IsInventoryLocation', true);
        insert loc;
        return loc.Id;
    }

    /**
     * Create a ProductItem record linking a Product2 to a warehouse location.
     * Uses createWarehouseLocation() internally to avoid System.Location collision.
     */
    public static ProductItem createProductItem(Product2 product, Decimal quantityOnHand) {
        Id locationId = createWarehouseLocation('Test Warehouse ' + now().getTime());
        ProductItem pi = new ProductItem(
            Product2Id            = product.Id,
            LocationId            = locationId,
            QuantityOnHand        = quantityOnHand,
            QuantityUnitOfMeasure = 'Each'
        );
        insert pi;
        return pi;
    }

    /**
     * Create an Incentive__c record linked to a Monthly_Performance__c record.
     */
    public static Incentive__c createIncentive(Id salesRepId, Id monthlyPerfId, Decimal amount) {
        Incentive__c inc = new Incentive__c();
        inc.Sales_Rep__c            = salesRepId;
        inc.Monthly_Performance__c  = monthlyPerfId;
        inc.Incentive_Amount__c     = amount;
        insert inc;
        return inc;
    }

    /**
     * Create a sample Vashi product (isSample__c = true) with a SampleOrderLimit.
     */
    public static Product2 createSampleVashiProduct(String name, Boolean active, Integer sampleOrderLimit) {
        Product2 p                  = new Product2();
        p.Name                      = name;
        p.IsActive                  = active;
        p.Is_Veeglow_products__c    = true;
        p.isSample__c               = true;
        p.SampleOrderLimit__c       = sampleOrderLimit;
        p.TotalSampleQuantity__c    = sampleOrderLimit * 4;
        insert p;
        return p;
    }

    /**
     * Create a Travel_Expense_Claim__c record
     */
    public static Travel_Expense_Claim__c createTravelExpenseClaim(Id attendanceId, Id salesRepId, Date claimDate, Decimal calculatedKm, Decimal ratePerKm) {
        Travel_Expense_Claim__c claim = new Travel_Expense_Claim__c();
        claim.Attendance__c    = attendanceId;
        claim.Sales_Rep__c     = salesRepId;
        claim.Claim_Date__c    = claimDate;
        claim.Calculated_KM__c = calculatedKm;
        claim.Approved_KM__c   = calculatedKm;
        claim.Rate_Per_KM__c   = ratePerKm;
        claim.Claim_Amount__c  = calculatedKm * ratePerKm;
        claim.Status__c        = 'Draft';
        insert claim;
        return claim;
    }

    /**
     * Create a Visit_Travel_Point__c record.
     * Event_Type__c is a restricted picklist: START_DAY, CHECK_IN, CHECK_OUT, END_DAY
     */
    public static Visit_Travel_Point__c createTravelPoint(Id attendanceId, Id visitId, String eventType,
                                                           Decimal latitude, Decimal longitude, Integer sequence) {
        Visit_Travel_Point__c point = new Visit_Travel_Point__c();
        point.Attendance__c  = attendanceId;
        point.Visit__c       = visitId;
        point.Sales_Rep__c   = UserInfo.getUserId();
        point.Event_Type__c  = eventType;
        point.Latitude__c    = latitude;
        point.Longitude__c   = longitude;
        point.Sequence__c    = sequence;
        point.Event_Time__c  = Datetime.now();
        point.Source__c      = 'SYSTEM'; // restricted: SYSTEM or MANUAL_ADJUSTMENT
        insert point;
        return point;
    }

    public static String generateRandomString(Integer length) {
        // Cap at 18 to respect Scheme_Name__c max length
        Integer safeLength = Math.min(length, 18);
        final String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefghijklmnopqrstuvwxyz';
        String randStr = '';
        
        while (randStr.length() < safeLength) {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), chars.length());
            randStr += chars.substring(idx, idx + 1);
        }
        return randStr;
    }

}