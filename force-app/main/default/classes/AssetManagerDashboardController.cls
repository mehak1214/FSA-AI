public with sharing class AssetManagerDashboardController {

    // ─── Summary counts ────────────────────────────────────────────────────────
    // Returns every integer the dashboard needs in one callout so the component
    // can render all stat cards and the pipeline in a single round-trip.

    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getDashboardCounts() {
        Map<String, Integer> counts = new Map<String, Integer>();

        // ── Blocked / issue counts (existing) ─────────────────────────────────
        counts.put('blockedTasks', [
            SELECT COUNT() FROM Visit_Task__c
            WHERE Status__c = 'Blocked/Retailer Refused'
        ]);

        counts.put('mandatoryBlockedTasks', [
            SELECT COUNT() FROM Visit_Task__c
            WHERE Status__c = 'Blocked/Retailer Refused'
            AND Is_Mandatory__c = true
        ]);

        // Bug 7 fix: AggregateResult GROUP BY Asset__c instead of an unbounded
        // row-by-row loop that could hit the 50,000-record SOQL governor limit.
        Set<Id> issueAssetIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Asset__c aid
            FROM Asset_Audit__c
            WHERE Condition__c IN ('Damaged', 'Needs Repair', 'Missing')
            AND   CreatedDate  =  LAST_N_DAYS:30
            AND   Asset__c    !=  null
            GROUP BY Asset__c
        ]) {
            issueAssetIds.add((Id) ar.get('aid'));
        }
        for (AggregateResult ar : [
            SELECT Id aid
            FROM Asset__c
            WHERE Asset_Status__c = 'Under Repair'
            GROUP BY Id
        ]) {
            issueAssetIds.add((Id) ar.get('aid'));
        }
        counts.put('assetsWithIssues', issueAssetIds.size());

        counts.put('damagedAssets', [
            SELECT COUNT() FROM Asset_Audit__c
            WHERE Condition__c = 'Damaged'
            AND CreatedDate = LAST_N_DAYS:30
        ]);

        counts.put('needsRepairAssets', [
            SELECT COUNT() FROM Asset_Audit__c
            WHERE Condition__c = 'Needs Repair'
            AND CreatedDate = LAST_N_DAYS:30
        ]);

        // ── Asset pipeline stage counts (new) ──────────────────────────────────
        counts.put('inWarehouse', [
            SELECT COUNT() FROM Asset__c WHERE Asset_Status__c = 'In Warehouse'
        ]);
        counts.put('pendingPreparation', [
            SELECT COUNT() FROM Asset__c WHERE Asset_Status__c = 'Pending Preparation'
        ]);
        counts.put('readyForDispatch', [
            SELECT COUNT() FROM Asset__c WHERE Asset_Status__c = 'Ready for Dispatch'
        ]);
        counts.put('inTransit', [
            SELECT COUNT() FROM Asset__c WHERE Asset_Status__c = 'In Transit'
        ]);
        counts.put('activeDeployed', [
            SELECT COUNT() FROM Asset__c
            WHERE Asset_Status__c IN ('Active', 'Deployed')
        ]);
        counts.put('underRepair', [
            SELECT COUNT() FROM Asset__c WHERE Asset_Status__c = 'Under Repair'
        ]);

        // ── Overdue deployments (new) ──────────────────────────────────────────
        counts.put('overdueDeployments', [
            SELECT COUNT() FROM Asset_Allocation__c
            WHERE Planned_Installation_Date__c < TODAY
            AND   Allocation_Status__c = 'Planned'
        ]);

        // ── Pending mandatory tasks (new) ──────────────────────────────────────
        counts.put('pendingMandatoryTasks', [
            SELECT COUNT() FROM Visit_Task__c
            WHERE Status__c = 'Pending'
            AND   Is_Mandatory__c = true
        ]);

        // ── Active/Deployed assets with no audit in the last 30 days (new) ─────
        Set<Id> recentlyAuditedIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Asset__c aid
            FROM Asset_Audit__c
            WHERE CreatedDate = LAST_N_DAYS:30
            AND   Asset__c   != null
            GROUP BY Asset__c
        ]) {
            recentlyAuditedIds.add((Id) ar.get('aid'));
        }
        counts.put('noRecentAuditCount', [
            SELECT COUNT() FROM Asset__c
            WHERE Asset_Status__c = 'Deployed'
            AND   Id NOT IN :recentlyAuditedIds
        ]);

        return counts;
    }

    // ─── Blocked tasks list (existing) ────────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Visit_Task__c> getBlockedTasks() {
        return [
            SELECT Id, Name, Task_Type__c, Status__c, Exception_Reason__c,
                   Is_Mandatory__c,
                   Visit__r.Name,
                   Visit__r.Outlet1__r.Name,
                   Visit__r.Sales_Rep__r.Name
            FROM Visit_Task__c
            WHERE Status__c = 'Blocked/Retailer Refused'
            ORDER BY Is_Mandatory__c DESC, CreatedDate DESC
            LIMIT 10
        ];
    }

    // ─── Assets with issues list (existing + Bug 7 fix) ───────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Asset__c> getAssetsWithIssues() {
        // Bug 7 fix: AggregateResult GROUP BY instead of unbounded loop.
        Set<Id> auditAssetIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Asset__c aid
            FROM Asset_Audit__c
            WHERE Condition__c IN ('Damaged', 'Needs Repair', 'Missing')
            AND   CreatedDate  =  LAST_N_DAYS:30
            AND   Asset__c    !=  null
            GROUP BY Asset__c
        ]) {
            auditAssetIds.add((Id) ar.get('aid'));
        }

        return [
            SELECT Id, Name, Asset_Status__c,
                   Current_Account__r.Name,
                   Product__r.Name,
                   (SELECT Condition__c, CreatedDate
                    FROM AssetAuditsByAsset__r
                    ORDER BY CreatedDate DESC LIMIT 1)
            FROM Asset__c
            WHERE Asset_Status__c = 'Under Repair'
            OR Id IN :auditAssetIds
            ORDER BY Asset_Status__c ASC
            LIMIT 10
        ];
    }

    // ─── Reps in field today (existing) ───────────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static List<Map<String, Object>> getRepsInField() {
        List<Visit__c> todayVisits = [
            SELECT Id, Sales_Rep__c, Sales_Rep__r.Name,
                   Sales_Rep__r.FirstName, Sales_Rep__r.LastName,
                   Visit_Status__c
            FROM Visit__c
            WHERE Visit_Date__c = TODAY
            AND   Sales_Rep__c != null
            ORDER BY Sales_Rep__r.Name ASC
        ];

        Map<Id, Map<String, Object>> repMap = new Map<Id, Map<String, Object>>();

        for (Visit__c v : todayVisits) {
            if (!repMap.containsKey(v.Sales_Rep__c)) {
                String initials = '';
                if (v.Sales_Rep__r.FirstName != null && v.Sales_Rep__r.FirstName.length() > 0) {
                    initials += v.Sales_Rep__r.FirstName.substring(0, 1);
                }
                if (v.Sales_Rep__r.LastName != null && v.Sales_Rep__r.LastName.length() > 0) {
                    initials += v.Sales_Rep__r.LastName.substring(0, 1);
                }
                repMap.put(v.Sales_Rep__c, new Map<String, Object>{
                    'repId'     => v.Sales_Rep__c,
                    'repName'   => v.Sales_Rep__r.Name,
                    'initials'  => initials.toUpperCase(),
                    'total'     => 0,
                    'completed' => 0
                });
            }
            Map<String, Object> repData = repMap.get(v.Sales_Rep__c);
            repData.put('total', (Integer)repData.get('total') + 1);
            if (v.Visit_Status__c == 'Completed') {
                repData.put('completed', (Integer)repData.get('completed') + 1);
            }
        }

        return repMap.values();
    }

    // ─── Overdue deployments list (new) ───────────────────────────────────────
    // Allocations whose Planned_Installation_Date__c has passed but the asset
    // has still not left the Planned stage, ordered oldest-first so the most
    // urgent records appear at the top.

    @AuraEnabled(cacheable=true)
    public static List<Asset_Allocation__c> getOverdueDeployments() {
        return [
            SELECT Id, Name,
                   Asset__r.Name, Asset__r.Asset_Status__c, Asset__r.Serial_Number__c,
                   Account__r.Name,
                   Planned_Installation_Date__c
            FROM Asset_Allocation__c
            WHERE Planned_Installation_Date__c < TODAY
            AND   Allocation_Status__c = 'Planned'
            ORDER BY Planned_Installation_Date__c ASC
            LIMIT 10
        ];
    }

    // ─── Pending mandatory tasks list (new) ───────────────────────────────────
    // All Pending + Mandatory tasks ordered by visit date so the most urgent
    // (earliest scheduled visit) surfaces at the top.

    @AuraEnabled(cacheable=true)
    public static List<Visit_Task__c> getPendingMandatoryTasks() {
        return [
            SELECT Id, Name, Task_Type__c, Status__c, Is_Mandatory__c,
                   Visit__r.Name, Visit__r.Visit_Date__c,
                   Visit__r.Outlet1__r.Name,
                   Visit__r.Sales_Rep__r.Name,
                   Related_Asset__r.Name
            FROM Visit_Task__c
            WHERE Status__c       = 'Pending'
            AND   Is_Mandatory__c = true
            ORDER BY Visit__r.Visit_Date__c ASC
            LIMIT 10
        ];
    }

    // ─── Active/Deployed assets with no audit in last 30 days (new) ───────────
    // Builds the exclusion set with AggregateResult GROUP BY so the NOT IN
    // list stays within governor limits even in a high-volume org.

    @AuraEnabled(cacheable=true)
    public static List<Asset__c> getAssetsWithNoRecentAudit() {
        Set<Id> recentlyAuditedIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Asset__c aid
            FROM Asset_Audit__c
            WHERE CreatedDate = LAST_N_DAYS:30
            AND   Asset__c   != null
            GROUP BY Asset__c
        ]) {
            recentlyAuditedIds.add((Id) ar.get('aid'));
        }

        return [
            SELECT Id, Name, Asset_Status__c, Serial_Number__c,
                   Current_Account__r.Name,
                   Product__r.Name
            FROM Asset__c
            WHERE Asset_Status__c = 'Deployed'
            AND   Id NOT IN :recentlyAuditedIds
            ORDER BY Name ASC
            LIMIT 10
        ];
    }
}