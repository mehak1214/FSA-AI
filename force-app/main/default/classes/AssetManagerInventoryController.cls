public with sharing class AssetManagerInventoryController {

    // ─── Asset List ────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static List<Asset__c> getAssets(
        String statusFilter,
        String searchTerm,
        String outletId,
        Boolean overdueOnly,
        Boolean noAuditOnly
    ) {
        String q =
            'SELECT Id, Name, Asset_Status__c, Serial_Number__c, ' +
            'Current_Account__c, Current_Account__r.Name, ' +
            'Product__r.Name, Product__r.DisplayUrl, ' +
            '(SELECT Condition__c, CreatedDate, ' +
            '        Visit__r.Visit_Date__c ' +
            ' FROM AssetAuditsByAsset__r ' +
            ' ORDER BY CreatedDate DESC LIMIT 1) ' +
            'FROM Asset__c WHERE Id != null';

        if (String.isNotBlank(statusFilter) && statusFilter != 'All') {
            q += ' AND Asset_Status__c = \'' + String.escapeSingleQuotes(statusFilter) + '\'';
        }
        if (String.isNotBlank(searchTerm)) {
            String s = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            q += ' AND (Name LIKE \'' + s + '\' OR Serial_Number__c LIKE \'' + s + '\')';
        }
        if (String.isNotBlank(outletId)) {
            q += ' AND Current_Account__c = \'' + String.escapeSingleQuotes(outletId) + '\'';
        }
        if (overdueOnly == true) {
            q += ' AND Id IN (' +
                 'SELECT Asset__c FROM Asset_Allocation__c ' +
                 'WHERE Planned_Installation_Date__c < TODAY ' +
                 'AND Allocation_Status__c = \'Planned\' ' +
                 'AND Asset__c != null' +
                 ')';
        }
        if (noAuditOnly == true) {
            q += ' AND Asset_Status__c = \'Deployed\'';
            q += ' AND Id NOT IN (' +
                 'SELECT Asset__c FROM Asset_Audit__c ' +
                 'WHERE CreatedDate = LAST_N_DAYS:30 ' +
                 'AND Asset__c != null' +
                 ')';
        }

        q += ' ORDER BY Name ASC LIMIT 100';
        return Database.query(q);
    }

    // ─── Asset Detail (with last 5 audits) ─────────────────────────────────────

    @AuraEnabled(cacheable=false)
    public static Asset__c getAssetDetail(String assetId) {
        return [
            SELECT Id, Name, Asset_Status__c, Serial_Number__c,
                   Current_Account__c, Current_Account__r.Name,
                   Product__r.Name, Product__r.DisplayUrl,
                   (SELECT Id, Name, Condition__c, CreatedDate,
                           Visit__r.Name, Visit__r.Visit_Date__c,
                           Visit__r.Outlet1__r.Name,
                           Visit__r.Sales_Rep__r.Name
                    FROM AssetAuditsByAsset__r
                    ORDER BY CreatedDate DESC
                    LIMIT 5),
                   (SELECT Id, Name, Allocation_Status__c,
                           Account__c, Account__r.Name,
                           Planned_Installation_Date__c,
                           Deployment_Start_Date__c,
                           Deployed_Date__c,
                           Deployment_End_Date__c,
                           Logistics_Handover_Date__c,
                           Is_Current_Location__c,
                           CreatedDate
                    FROM Allocations__r
                    ORDER BY CreatedDate DESC
                    LIMIT 3),
                   (SELECT Id, Name, Task_Type__c, Status__c,
                           Is_Mandatory__c,
                           Manager_Instructions__c,
                           Visit__c, Visit__r.Visit_Date__c,
                           Visit__r.Sales_Rep__r.Name,
                           Visit__r.Outlet1__r.Name,
                           CreatedDate
                    FROM VisitTasksByAsset__r
                    ORDER BY CreatedDate DESC
                    LIMIT 3)
            FROM Asset__c
            WHERE Id = :assetId
        ];
    }

    // ─── Lookups ────────────────────────────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Account> getOutlets() {
        return [
            SELECT Id, Name
            FROM Account
            WHERE OutletStatus__c = 'Active' 
                  AND RecordType.DeveloperName = 'Franchise' 
            ORDER BY Name ASC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Product2> getProducts() {
        return [
            SELECT Id, Name
            FROM Product2
            WHERE IsActive = true
            AND Is_Asset__c = true
            ORDER BY Name ASC
            LIMIT 200
        ];
    }

    @AuraEnabled
    public static Id createAsset(
        String serialNumber,
        String productId,
        String purchaseDateStr,
        Decimal assetValue,
        String assetStatus
    ) {
        if (String.isBlank(productId)) {
            throw new AuraHandledException('Product is required.');
        }

        Asset__c asset = new Asset__c(
            Serial_Number__c = String.isBlank(serialNumber) ? null : serialNumber.trim(),
            Product__c = productId,
            Purchase_Date__c = String.isBlank(purchaseDateStr) ? null : Date.valueOf(purchaseDateStr),
            Asset_Value__c = assetValue,
            Asset_Status__c = String.isBlank(assetStatus) ? 'In Warehouse' : assetStatus,
            Current_Account__c = null
        );
        insert asset;
        return asset.Id;
    }

    @AuraEnabled(cacheable=false)  // beat assignments change; cacheable=true would serve stale reps
    public static List<User> getSalesRepsForOutlet(String outletId) {
        Set<Id> beatIds = new Set<Id>();
        for (Beat_Plan_Store__c bps : [
            SELECT Beat__c FROM Beat_Plan_Store__c
            WHERE Outlet__c = :outletId
            AND Active__c = true
            AND Beat__c != null
        ]) {
            beatIds.add(bps.Beat__c);
        }
        if (beatIds.isEmpty()) return new List<User>();

        Set<Id> repIds = new Set<Id>();
        for (Beat__c b : [
            SELECT Sales_Rep__c FROM Beat__c
            WHERE Id IN :beatIds
            AND Active__c = true
            AND Sales_Rep__c != null
        ]) {
            repIds.add(b.Sales_Rep__c);
        }
        if (repIds.isEmpty()) return new List<User>();

        return [
            SELECT Id, Name FROM User
            WHERE Id IN :repIds
            AND IsActive = true
            ORDER BY Name ASC
        ];
    }

    // ─── Deploy ─────────────────────────────────────────────────────────────────
    // 1. Close any currently Active allocation for this asset (defensive cleanup).
    // 2. Create a new Asset_Allocation__c — status Planned, Deployment_Start_Date__c
    //    intentionally left NULL (asset has not physically departed the warehouse yet;
    //    date is stamped in VisitTaskController when the pre-check task is completed).
    // 3. Set Asset__c.Asset_Status__c = 'Pending Preparation'.
    // 4. Create an Installation Pre-Check visit task for the rep on the task date.
    //    taskDateStr is the date used to look up / create the visit — it is separate
    //    from deployDateStr (the physical deployment date stored on the allocation).
    //    If the rep already has an Approved visit for that outlet+date combo, the
    //    task is added to it; otherwise a new visit is created automatically.

    @AuraEnabled
    public static void deployAsset(
        String assetId,
        String outletId,
        String repId,
        String deployDateStr,
        String taskDateStr,
        String instructions
    ) {
        // Step 1 — close any Active allocation that is still open
        List<Asset_Allocation__c> activeAllocs = [
            SELECT Id FROM Asset_Allocation__c
            WHERE Asset__c             = :assetId
            AND   Allocation_Status__c = 'Active'
        ];
        if (!activeAllocs.isEmpty()) {
            for (Asset_Allocation__c a : activeAllocs) {
                a.Allocation_Status__c   = 'Completed/Removed';
                a.Deployment_End_Date__c = Date.today();
            }
            update activeAllocs;
        }

        // Step 2 — create the new allocation for the target outlet.
        // Deployment_Start_Date__c is intentionally left NULL here: the allocation is
        // still in 'Planned' status and the asset has not physically departed yet.
        // The date will be stamped (= today) when the Installation Pre-Check task is
        // completed and the asset advances to 'Ready for Dispatch' (see VisitTaskController).
        // Planned_Installation_Date__c records the intended installation date chosen by
        // the manager at deploy time.
        insert new Asset_Allocation__c(
            Asset__c                    = assetId,
            Account__c                  = outletId,
            Allocation_Status__c        = 'Planned',
            Planned_Installation_Date__c = String.isNotBlank(deployDateStr)
                ? Date.valueOf(deployDateStr)
                : null
        );

        // Step 3 — set asset to Pending Preparation; outlet link stays blank
        //           until the asset physically arrives and the task is completed
        update new Asset__c(
            Id                 = assetId,
            Asset_Status__c    = 'Pending Preparation',
            Current_Account__c = null
        );

        // Step 4 — create the Installation Pre-Check visit task (always mandatory).
        // Uses taskDateStr for the visit date — independent of the deployment date.
        if (String.isNotBlank(repId) && String.isNotBlank(taskDateStr)) {
            Date taskDate = Date.valueOf(taskDateStr);
            Id visitId = resolveVisitId(outletId, repId, taskDate);

            insert new Visit_Task__c(
                Visit__c                = visitId,
                Task_Type__c            = 'Asset Installation Pre-Check',
                Manager_Instructions__c = instructions,
                Related_Asset__c        = assetId,
                Status__c               = 'Pending',
                Is_Mandatory__c         = true
            );
        }
    }

    // ─── Recall ──────────────────────────────────────────────────────────────────
    // 1. Find the Active allocation → close it with Deployment_End_Date = today.
    // 2. Set Asset__c.Asset_Status__c = 'In Warehouse', clear Current_Account__c.
    // 3. Optionally create an Asset Relocation Removal task for the rep so they
    //    physically collect the asset from the outlet it is being recalled from.

    @AuraEnabled
    public static void recallAsset(
        String assetId,
        String repId,
        String recallDateStr,
        Boolean createTask,
        String instructions
    ) {
        // Need the current outlet before we clear it — read it first
        Asset__c current = [
            SELECT Id, Current_Account__c FROM Asset__c WHERE Id = :assetId LIMIT 1
        ];
        Id fromOutletId = current.Current_Account__c;

        // Step 1 — close both Active and Planned allocations.
        // Planned allocations can exist when an asset is recalled before the
        // pre-check task was completed, which would leave a dangling open record.
        List<Asset_Allocation__c> activeAllocs = [
            SELECT Id FROM Asset_Allocation__c
            WHERE Asset__c             = :assetId
            AND   Allocation_Status__c IN ('Active', 'Planned')
        ];
        if (!activeAllocs.isEmpty()) {
            for (Asset_Allocation__c a : activeAllocs) {
                a.Allocation_Status__c   = 'Completed/Removed';
                a.Deployment_End_Date__c = Date.today();
            }
            update activeAllocs;
        }

        // Step 2 — return asset to warehouse
        update new Asset__c(
            Id                 = assetId,
            Asset_Status__c    = 'In Warehouse',
            Current_Account__c = null
        );

        // Step 3 — optional removal task for the rep
        if (createTask == true
                && String.isNotBlank(repId)
                && String.isNotBlank(recallDateStr)
                && fromOutletId != null) {

            Date recallDate = Date.valueOf(recallDateStr);
            Id visitId = resolveVisitId(fromOutletId, repId, recallDate);

            insert new Visit_Task__c(
                Visit__c                = visitId,
                Task_Type__c            = 'Asset Relocation Removal',
                Manager_Instructions__c = instructions,
                Related_Asset__c        = assetId,
                Status__c               = 'Pending',
                Is_Mandatory__c         = true
            );
        }
    }

    // ─── Mark Delivered ──────────────────────────────────────────────────────────
    // Called when the manager clicks "Delivered" on an In Transit asset.
    // Transitions the asset and its in-flight allocation to Deployed in one atomic
    // operation and records today as the Deployed_Date__c on the allocation.

    @AuraEnabled
    public static void markDelivered(String assetId) {
        if (String.isBlank(assetId)) {
            throw new AuraHandledException('Asset ID is required.');
        }

        // Activate the in-flight allocation (Planned or Active), stamp the date,
        // and capture the destination account so we can write it to the asset.
        List<Asset_Allocation__c> allocs = [
            SELECT Id, Account__c
            FROM Asset_Allocation__c
            WHERE Asset__c             = :assetId
            AND   Allocation_Status__c IN ('Planned', 'Active')
            LIMIT 1
        ];

        Id destinationAccount = null;
        if (!allocs.isEmpty()) {
            destinationAccount = allocs[0].Account__c;
            update new Asset_Allocation__c(
                Id                   = allocs[0].Id,
                Allocation_Status__c = 'Active',
                Deployed_Date__c     = Date.today()
            );
        }

        // Advance the asset to Deployed and stamp the current account so the
        // asset always shows its store regardless of whether the pre-check
        // task flow was completed.
        update new Asset__c(
            Id                 = assetId,
            Asset_Status__c    = 'Deployed',
            Current_Account__c = destinationAccount
        );
    }

    // ─── Simple status updates (repair, return, scrap) ───────────────────────────

    @AuraEnabled
    public static void updateAllocationPlannedDate(String allocationId, String plannedInstallDateStr) {
        if (String.isBlank(allocationId)) {
            throw new AuraHandledException('Allocation ID is required.');
        }
        if (String.isBlank(plannedInstallDateStr)) {
            throw new AuraHandledException('Planned installation date is required.');
        }

        update new Asset_Allocation__c(
            Id = allocationId,
            Planned_Installation_Date__c = Date.valueOf(plannedInstallDateStr)
        );
    }

    @AuraEnabled
    public static void updateAssetStatus(String assetId, String newStatus) {
        Asset__c asset = new Asset__c(
            Id              = assetId,
            Asset_Status__c = newStatus
        );

        if (newStatus == 'In Warehouse' || newStatus == 'Scrapped') {
            asset.Current_Account__c = null;
        }

        update asset;

        // When the asset is handed off to logistics, stamp the handover datetime
        // on the current in-flight allocation so the timestamp is recorded precisely.
        if (newStatus == 'In Transit') {
            List<Asset_Allocation__c> allocs = [
                SELECT Id FROM Asset_Allocation__c
                WHERE Asset__c             = :assetId
                AND   Allocation_Status__c IN ('Planned', 'Active')
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!allocs.isEmpty()) {
                update new Asset_Allocation__c(
                    Id                        = allocs[0].Id,
                    Logistics_Handover_Date__c = DateTime.now()
                );
            }
        }
    }

    // ─── Private helpers ─────────────────────────────────────────────────────────

    // Reuse an existing Approved visit for the rep+outlet+date combo.
    // Visit_Status__c is the primary lifecycle field; Approval_Status__c is
    // the approval workflow field and can lag behind, causing duplicate visits
    // if used as the sole filter.
    private static Id resolveVisitId(String outletId, String repId, Date visitDate) {
        List<Visit__c> existing = [
            SELECT Id FROM Visit__c
            WHERE Sales_Rep__c  = :repId
            AND   Outlet1__c    = :outletId
            AND   Visit_Date__c = :visitDate
            AND   Visit_Status__c = 'Approved'
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        // Look up the beat for this rep+outlet combination.
        // Null is safe — Visit__c.Beat__c is not required.
        Id beatId = getBeatIdForRepAndOutlet(repId, outletId);

        Visit__c v = new Visit__c(
            Outlet1__c            = outletId,
            Sales_Rep__c          = repId,
            Visit_Date__c         = visitDate,
            Visit_Status__c       = 'Approved',
            Approval_Status__c    = 'Approved',
            Beat__c               = beatId,
            Planned_Start_Time__c = DateTime.newInstance(visitDate, Time.newInstance(7, 0, 0, 0)),
            Planned_End_Time__c   = DateTime.newInstance(visitDate, Time.newInstance(8, 0, 0, 0))
        );
        insert v;
        return v.Id;
    }

    // Finds the active Beat__c that covers the given outlet AND is assigned
    // to the given rep. Returns null silently if no match is found.
    private static Id getBeatIdForRepAndOutlet(String repId, String outletId) {
        // Step 1 — get all active beats that cover this outlet
        Set<Id> outletBeatIds = new Set<Id>();
        for (Beat_Plan_Store__c bps : [
            SELECT Beat__c FROM Beat_Plan_Store__c
            WHERE Outlet__c  = :outletId
            AND   Active__c  = true
            AND   Beat__c   != null
        ]) {
            outletBeatIds.add(bps.Beat__c);
        }
        if (outletBeatIds.isEmpty()) return null;

        // Step 2 — from those beats, find the one assigned to this rep
        List<Beat__c> beats = [
            SELECT Id FROM Beat__c
            WHERE Id           IN :outletBeatIds
            AND   Sales_Rep__c  = :repId
            AND   Active__c     = true
            LIMIT 1
        ];
        return beats.isEmpty() ? null : beats[0].Id;
    }
}