public with sharing class AssetManagerAuditController {

    @AuraEnabled(cacheable=true)
    public static List<Asset_Audit__c> getAudits(
        String conditionFilter,
        String dateRange
    ) {
        String baseQuery =
            'SELECT Id, Name, Condition__c, Audit_Photo_URL__c, ' +
            'Scan_Location__Latitude__s, Scan_Location__Longitude__s, ' +
            'Asset__r.Name, Asset__r.Asset_Status__c, Asset__r.Serial_Number__c, ' +
            'Asset__r.Current_Account__r.Name, ' +
            'Visit__r.Name, Visit__r.Outlet1__r.Name, Visit__r.Visit_Date__c, ' +
            'Visit__r.Sales_Rep__r.Name, ' +
            'Asset_Allocation__r.Name, ' +
            'CreatedDate ' +
            'FROM Asset_Audit__c WHERE Id != null';

        if (String.isNotBlank(conditionFilter) && conditionFilter != 'All') {
            baseQuery += ' AND Condition__c = \'' + String.escapeSingleQuotes(conditionFilter) + '\'';
        }
        if (dateRange == 'today') {
            baseQuery += ' AND CreatedDate = TODAY';
        } else if (dateRange == 'week') {
            baseQuery += ' AND CreatedDate = LAST_N_DAYS:7';
        } else if (dateRange == 'month') {
            baseQuery += ' AND CreatedDate = LAST_N_DAYS:30';
        }

        baseQuery += ' ORDER BY CreatedDate DESC LIMIT 50';

        return Database.query(baseQuery);
    }

    @AuraEnabled
    public static void updateAssetStatus(String assetId, String newStatus) {
        Asset__c asset = new Asset__c(Id = assetId, Asset_Status__c = newStatus);
        update asset;
    }

    @AuraEnabled
    public static Visit_Task__c createFollowUpTask(
        String visitId,
        String assetId,
        String taskType,
        String instructions,
        Boolean isMandatory
    ) {
        Visit_Task__c task = new Visit_Task__c(
            Visit__c                = visitId,
            Task_Type__c            = taskType,
            Manager_Instructions__c = instructions,
            Related_Asset__c        = assetId,
            Status__c               = 'Pending',
            Is_Mandatory__c         = isMandatory != null ? isMandatory : true
        );
        insert task;
        return [
            SELECT Id, Name, Task_Type__c, Status__c, Is_Mandatory__c,
                   Visit__r.Name, Related_Asset__r.Name
            FROM Visit_Task__c
            WHERE Id = :task.Id
        ];
    }
}