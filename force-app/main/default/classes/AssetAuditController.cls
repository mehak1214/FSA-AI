public with sharing class AssetAuditController {
    public class AssetAuditContext {
        @AuraEnabled public Id assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String assetStatus;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String productName;
        @AuraEnabled public String outletName;
        @AuraEnabled public Id visitId;
        @AuraEnabled public String visitName;
        @AuraEnabled public Date visitDate;
        @AuraEnabled public Boolean canAudit;
        @AuraEnabled public Boolean hasAuditToday;
        @AuraEnabled public Boolean auditTodayByCurrentUser;
        @AuraEnabled public Id todayAuditId;
        @AuraEnabled public String todayAuditCreatedByName;
        @AuraEnabled public String todayAuditMessage;
        @AuraEnabled public String condition;
        @AuraEnabled public String auditPhotoUrl;
    }

    @AuraEnabled(cacheable=false)
    public static AssetAuditContext getAssetAuditContext(Id assetId, Id visitId) {
        if (assetId == null) {
            throw new AuraHandledException('Asset Id is required.');
        }

        Asset__c assetRecord = [
            SELECT Id, Name, Asset_Status__c, Serial_Number__c,
                   Current_Account__r.Name,
                   Product__r.Name
            FROM Asset__c
            WHERE Id = :assetId
            LIMIT 1
        ];

        Visit__c visitRecord = null;
        if (visitId != null) {
            List<Visit__c> visits = [
                SELECT Id, Name, Visit_Date__c
                FROM Visit__c
                WHERE Id = :visitId
                LIMIT 1
            ];
            if (!visits.isEmpty()) {
                visitRecord = visits[0];
            }
        }

        String outletName = assetRecord.Current_Account__r != null ? assetRecord.Current_Account__r.Name : null;
        if (String.isBlank(outletName)) {
            List<Asset_Allocation__c> allocations = [
                SELECT Account__r.Name
                FROM Asset_Allocation__c
                WHERE Asset__c = :assetId
                AND Allocation_Status__c IN ('Planned', 'Active')
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (!allocations.isEmpty() && allocations[0].Account__r != null) {
                outletName = allocations[0].Account__r.Name;
            }
        }

        AssetAuditContext response = new AssetAuditContext();
        response.assetId = assetRecord.Id;
        response.assetName = assetRecord.Name;
        response.assetStatus = assetRecord.Asset_Status__c;
        response.serialNumber = assetRecord.Serial_Number__c;
        response.productName = assetRecord.Product__r != null ? assetRecord.Product__r.Name : null;
        response.outletName = outletName;
        response.visitId = visitRecord != null ? visitRecord.Id : null;
        response.visitName = visitRecord != null ? visitRecord.Name : null;
        response.visitDate = visitRecord != null ? visitRecord.Visit_Date__c : null;
        response.canAudit = visitRecord != null;
        response.hasAuditToday = false;
        response.auditTodayByCurrentUser = false;

        List<Asset_Audit__c> todaysAudits = [
            SELECT Id, Condition__c,
                   Audit_Photo_URL__c, CreatedById, CreatedBy.Name
            FROM Asset_Audit__c
            WHERE Asset__c = :assetId
            AND CreatedDate = TODAY
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!todaysAudits.isEmpty()) {
            Asset_Audit__c latestAudit = todaysAudits[0];
            response.hasAuditToday = true;
            response.todayAuditId = latestAudit.Id;
            response.todayAuditCreatedByName = latestAudit.CreatedBy != null ? latestAudit.CreatedBy.Name : null;
            response.auditTodayByCurrentUser = latestAudit.CreatedById == UserInfo.getUserId();
            response.condition = latestAudit.Condition__c;
            response.auditPhotoUrl = latestAudit.Audit_Photo_URL__c;
            if (response.auditTodayByCurrentUser) {
                response.todayAuditMessage = 'Audit already completed today by you. You can edit and update it.';
            } else {
                response.todayAuditMessage = 'Audit already completed today by ' +
                    response.todayAuditCreatedByName +
                    '. You can still create your own audit.';
            }
        }

        if (!response.hasAuditToday) {
            response.todayAuditMessage = 'No audit has been captured for this asset today.';
        }

        return response;
    }

    @AuraEnabled
    public static Id saveAssetAudit(
        Id visitId,
        Id assetId,
        Id auditId,
        String condition,
        Decimal latitude,
        Decimal longitude
    ) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required to submit an asset audit.');
        }
        if (assetId == null) {
            throw new AuraHandledException('Asset Id is required to submit an asset audit.');
        }
        if (String.isBlank(condition)) {
            throw new AuraHandledException('Condition is required.');
        }

        Id allocationId = null;
        List<Asset_Allocation__c> allocations = [
            SELECT Id
            FROM Asset_Allocation__c
            WHERE Asset__c = :assetId
            AND Allocation_Status__c IN ('Active', 'Planned')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        if (!allocations.isEmpty()) {
            allocationId = allocations[0].Id;
        }

        Asset_Audit__c auditRecord;
        Boolean isUpdate = auditId != null;
        if (auditId != null) {
            auditRecord = [
                SELECT Id, CreatedById
                FROM Asset_Audit__c
                WHERE Id = :auditId
                LIMIT 1
            ];
            if (auditRecord.CreatedById != UserInfo.getUserId()) {
                throw new AuraHandledException('You can only edit your own audit record.');
            }
        } else {
            auditRecord = new Asset_Audit__c();
        }

        if (!isUpdate) {
            auditRecord.Visit__c = visitId;
            auditRecord.Asset__c = assetId;
            auditRecord.Asset_Allocation__c = allocationId;
        }
        auditRecord.Condition__c = condition;
        if (latitude != null) {
            auditRecord.Scan_Location__Latitude__s = latitude;
        }
        if (longitude != null) {
            auditRecord.Scan_Location__Longitude__s = longitude;
        }

        upsert auditRecord;
        return auditRecord.Id;
    }

    @AuraEnabled
    public static String uploadAssetAuditPhoto(
        Id auditId,
        String base64Data,
        String contentType,
        String fileName
    ) {
        if (auditId == null) {
            throw new AuraHandledException('Audit Id is required before uploading a photo.');
        }
        if (String.isBlank(base64Data)) {
            throw new AuraHandledException('Photo data is required.');
        }

        Blob body = EncodingUtil.base64Decode(base64Data);
        String resolvedName = String.isBlank(fileName) ? 'Asset_Audit_Photo.jpg' : fileName;

        ContentVersion version = new ContentVersion(
            Title = resolvedName,
            PathOnClient = resolvedName,
            VersionData = body
        );
        insert version;

        version = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            LIMIT 1
        ];

        insert new ContentDocumentLink(
            LinkedEntityId = auditId,
            ContentDocumentId = version.ContentDocumentId,
            ShareType = 'V'
        );

        String downloadUrl = '/sfc/servlet.shepherd/version/download/' + version.Id;
        update new Asset_Audit__c(
            Id = auditId,
            Audit_Photo_URL__c = downloadUrl
        );

        return downloadUrl;
    }
}