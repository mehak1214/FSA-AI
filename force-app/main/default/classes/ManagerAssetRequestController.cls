public without sharing class ManagerAssetRequestController {

    @AuraEnabled(cacheable=true)
    public static List<Asset_Request__c> getAssetRequestsForManager() {
        Id currentUserId = UserInfo.getUserId();

        return [
            SELECT
                Id,
                Name,
                Status__c,
                Request_Type__c,
                Requested_Installation_Date__c,
                Power_Requirement_Met__c,
                Space_Cleared_Dimensions__c,
                Retailer_Consent_Obtained__c,
                Competitor_Asset_Details__c,
                Manager_Decision_Notes__c,
                Site_Readiness_Photo__c,
                CreatedDate,
                CreatedById,
                CreatedBy.Name,
                Account__c,
                Account__r.Name,
                Requested_Catalog_Item__c,
                Requested_Catalog_Item__r.Name
            FROM Asset_Request__c
            WHERE CreatedBy.ManagerId = :currentUserId
            AND Status__c IN ('Pending Approval', 'Approved', 'Rejected')
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];
    }

    @AuraEnabled
    public static String approveAssetRequest(Id requestId, String comments) {
        return updateAssetRequestStatus(requestId, 'Approved', comments, false);
    }

    @AuraEnabled
    public static String rejectAssetRequest(Id requestId, String comments) {
        return updateAssetRequestStatus(requestId, 'Rejected', comments, true);
    }

    private static String updateAssetRequestStatus(
        Id requestId,
        String targetStatus,
        String comments,
        Boolean requireComments
    ) {
        if (requestId == null) {
            throw new AuraHandledException('Asset request Id is required.');
        }
        if (String.isBlank(targetStatus)) {
            throw new AuraHandledException('Target status is required.');
        }
        if (requireComments && String.isBlank(comments)) {
            throw new AuraHandledException('Rejection comment is mandatory.');
        }

        Asset_Request__c requestRecord = [
            SELECT Id, Status__c, CreatedBy.ManagerId, Manager_Decision_Notes__c
            FROM Asset_Request__c
            WHERE Id = :requestId
            LIMIT 1
            FOR UPDATE
        ];

        if (requestRecord.CreatedBy.ManagerId != UserInfo.getUserId()) {
            throw new AuraHandledException('You are not authorized to process this asset request.');
        }
        if (requestRecord.Status__c != 'Pending Approval') {
            throw new AuraHandledException('Only pending asset requests can be processed.');
        }

        requestRecord.Status__c = targetStatus;
        requestRecord.Manager_Decision_Notes__c = String.isBlank(comments)
            ? null
            : comments.trim();
        update requestRecord;

        return 'SUCCESS';
    }
}