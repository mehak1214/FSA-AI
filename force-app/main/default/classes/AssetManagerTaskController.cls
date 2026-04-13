public with sharing class AssetManagerTaskController {

    @AuraEnabled(cacheable=true)
    public static List<Visit_Task__c> getTasks(
        String statusFilter,
        String taskTypeFilter,
        String repId,
        String dateRange
    ) {
        String baseQuery =
            'SELECT Id, Name, Task_Type__c, Status__c, Exception_Reason__c, ' +
            'Is_Mandatory__c, Manager_Instructions__c, ' +
            'Visit__r.Name, Visit__r.Outlet1__r.Name, Visit__r.Visit_Date__c, ' +
            'Visit__r.Sales_Rep__r.Name, Visit__r.Sales_Rep__c, ' +
            'Related_Asset__r.Name, Related_Asset__r.Asset_Status__c ' +
            'FROM Visit_Task__c WHERE Id != null';

        if (String.isNotBlank(statusFilter) && statusFilter != 'All') {
            baseQuery += ' AND Status__c = \'' + String.escapeSingleQuotes(statusFilter) + '\'';
        }
        if (String.isNotBlank(taskTypeFilter) && taskTypeFilter != 'All') {
            baseQuery += ' AND Task_Type__c = \'' + String.escapeSingleQuotes(taskTypeFilter) + '\'';
        }
        if (String.isNotBlank(repId)) {
            baseQuery += ' AND Visit__r.Sales_Rep__c = \'' + String.escapeSingleQuotes(repId) + '\'';
        }
        if (dateRange == 'today') {
            baseQuery += ' AND Visit__r.Visit_Date__c = TODAY';
        } else if (dateRange == 'week') {
            baseQuery += ' AND Visit__r.Visit_Date__c = LAST_N_DAYS:7';
        } else if (dateRange == 'month') {
            baseQuery += ' AND Visit__r.Visit_Date__c = LAST_N_DAYS:30';
        }

        baseQuery += ' ORDER BY Is_Mandatory__c DESC, CreatedDate DESC LIMIT 50';

        return Database.query(baseQuery);
    }

    @AuraEnabled(cacheable=true)
    public static List<Account> getRetailers() {
        return [
            SELECT Id, Name
            FROM Account
            WHERE Id IN (
                SELECT Outlet__c FROM Beat_Plan_Store__c
                WHERE Active__c = true
                AND Outlet__c != null
            )
            AND OutletStatus__c = 'Active'
            AND RecordType.DeveloperName = 'Franchise'
            ORDER BY Name ASC
            LIMIT 200
        ];
    }

    @AuraEnabled(cacheable=false)  // beat assignments change; cacheable=true would serve stale reps
    public static List<User> getSalesRepsForOutlet(String outletId) {
        Set<Id> beatIds = new Set<Id>();
        for (Beat_Plan_Store__c bps : [
            SELECT Beat__c
            FROM Beat_Plan_Store__c
            WHERE Outlet__c = :outletId
            AND Active__c = true
            AND Beat__c != null
        ]) {
            beatIds.add(bps.Beat__c);
        }

        if (beatIds.isEmpty()) {
            return new List<User>();
        }

        Set<Id> repIds = new Set<Id>();
        for (Beat__c b : [
            SELECT Sales_Rep__c
            FROM Beat__c
            WHERE Id IN :beatIds
            AND Active__c = true
            AND Sales_Rep__c != null
        ]) {
            repIds.add(b.Sales_Rep__c);
        }

        if (repIds.isEmpty()) {
            return new List<User>();
        }

        return [
            SELECT Id, Name
            FROM User
            WHERE Id IN :repIds
            AND IsActive = true
            ORDER BY Name ASC
        ];
    }

    @AuraEnabled
    public static Visit_Task__c createVisitAndTask(
        String retailerId,
        String repId,
        String taskDateStr,
        String taskType,
        String instructions,
        Boolean isMandatory,
        String relatedAssetId
    ) {
        Date taskDate = Date.valueOf(taskDateStr);

        // Check whether the rep already has an Approved visit for this outlet on this date.
        // Use Visit_Status__c (primary lifecycle field) — Approval_Status__c can lag
        // behind and cause duplicate visits if used as the sole filter.
        List<Visit__c> existingVisits = [
            SELECT Id
            FROM Visit__c
            WHERE Sales_Rep__c    = :repId
            AND   Outlet1__c      = :retailerId
            AND   Visit_Date__c   = :taskDate
            AND   Visit_Status__c = 'Approved'
            LIMIT 1
        ];

        Id visitId;
        if (!existingVisits.isEmpty()) {
            // Reuse the existing approved visit
            visitId = existingVisits[0].Id;
        } else {
            // No matching visit found — create a new approved visit.
            // Populate Beat__c from the rep+outlet assignment; null is safe if not found.
            Id beatId = getBeatIdForRepAndOutlet(repId, retailerId);

            Visit__c visit = new Visit__c(
                Outlet1__c              = retailerId,
                Sales_Rep__c            = repId,
                Visit_Date__c           = taskDate,
                Visit_Status__c         = 'Approved',
                Approval_Status__c      = 'Approved',
                Beat__c                 = beatId,
                Planned_Start_Time__c   = DateTime.newInstance(taskDate, Time.newInstance(7, 0, 0, 0)),
                Planned_End_Time__c     = DateTime.newInstance(taskDate, Time.newInstance(8, 0, 0, 0))
            );
            insert visit;
            visitId = visit.Id;
        }

        Visit_Task__c task = new Visit_Task__c(
            Visit__c                = visitId,
            Task_Type__c            = taskType,
            Manager_Instructions__c = instructions,
            Is_Mandatory__c         = isMandatory != null ? isMandatory : false,
            Status__c               = 'Pending',
            Related_Asset__c        = relatedAssetId
        );
        insert task;

        return [
            SELECT Id, Name, Task_Type__c, Status__c, Is_Mandatory__c,
                   Visit__r.Name, Visit__r.Outlet1__r.Name,
                   Visit__r.Visit_Date__c, Visit__r.Sales_Rep__r.Name,
                   Related_Asset__r.Name
            FROM Visit_Task__c
            WHERE Id = :task.Id
        ];
    }

    @AuraEnabled
    public static void updateTaskStatus(
        String taskId,
        String status,
        String exceptionReason
    ) {
        Visit_Task__c task = new Visit_Task__c(Id = taskId, Status__c = status);
        if (String.isNotBlank(exceptionReason)) {
            task.Exception_Reason__c = exceptionReason;
        }
        update task;
    }

    @AuraEnabled(cacheable=true)
    public static List<Asset__c> getDeployedAssets() {
        return [
            SELECT Id, Name, Asset_Status__c,
                   Current_Account__r.Name,
                   Product__r.Name
            FROM Asset__c
            WHERE Asset_Status__c = 'Deployed'
            ORDER BY Name ASC
            LIMIT 200
        ];
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
            WHERE Id          IN :outletBeatIds
            AND   Sales_Rep__c = :repId
            AND   Active__c    = true
            LIMIT 1
        ];
        return beats.isEmpty() ? null : beats[0].Id;
    }
}