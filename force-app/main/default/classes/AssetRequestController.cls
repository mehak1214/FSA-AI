public with sharing class AssetRequestController {
    public class CatalogProductOption {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public String family;
        @AuraEnabled public String imageUrl;
    }

    public class RequestSubmitResult {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String message;
    }

    public class AssetRequestDetail {
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestNumber;
        @AuraEnabled public String accountName;
        @AuraEnabled public String productName;
        @AuraEnabled public String productImageUrl;
        @AuraEnabled public String requestType;
        @AuraEnabled public String status;
        @AuraEnabled public Date requestedInstallationDate;
        @AuraEnabled public String powerRequirement;
        @AuraEnabled public String spaceCleared;
        @AuraEnabled public Boolean retailerConsentObtained;
        @AuraEnabled public String notes;
        @AuraEnabled public String managerDecisionNotes;
        @AuraEnabled public String siteReadinessPhotoUrl;
        @AuraEnabled public String assignedAssetName;
        @AuraEnabled public String assignedAssetSerialNumber;
        @AuraEnabled public String allocationName;
        @AuraEnabled public Datetime createdDate;
    }

    @AuraEnabled(cacheable=true)
    public static List<CatalogProductOption> getAvailableCatalogProducts() {
        Set<Id> productIds = new Set<Id>();

        for (Asset__c assetRecord : [
            SELECT Product__c
            FROM Asset__c
            WHERE Asset_Status__c = 'In Warehouse'
            AND Product__c != null
        ]) {
            productIds.add(assetRecord.Product__c);
        }

        List<CatalogProductOption> results = new List<CatalogProductOption>();
        if (productIds.isEmpty()) {
            return results;
        }

        Map<Id, String> productImageUrls = resolveProductImageUrls(productIds);

        for (Product2 productRecord : [
            SELECT Id, Name, ProductCode, Family, DisplayUrl, Image_URL__c, Product_Picture_ID_URL__c
            FROM Product2
            WHERE Id IN :productIds
            ORDER BY Name ASC
        ]) {
            CatalogProductOption option = new CatalogProductOption();
            option.productId = productRecord.Id;
            option.productName = productRecord.Name;
            option.productCode = productRecord.ProductCode;
            option.family = productRecord.Family;
            option.imageUrl = productImageUrls.containsKey(productRecord.Id)
                ? productImageUrls.get(productRecord.Id)
                : firstNonBlank(new List<String>{
                    productRecord.DisplayUrl,
                    (String)productRecord.get('Image_URL__c'),
                    (String)productRecord.get('Product_Picture_ID_URL__c')
                });
            results.add(option);
        }

        return results;
    }

    @AuraEnabled(cacheable=true)
    public static AssetRequestDetail getAssetRequestDetail(Id requestId) {
        if (requestId == null) {
            throw new AuraHandledException('Asset request Id is required.');
        }

        Asset_Request__c requestRecord = [
            SELECT Id, Name, CreatedDate, Request_Type__c, Status__c, Requested_Installation_Date__c,
                   Power_Requirement_Met__c, Space_Cleared_Dimensions__c, Retailer_Consent_Obtained__c,
                   Competitor_Asset_Details__c, Manager_Decision_Notes__c, Site_Readiness_Photo__c,
                   Account__r.Name, Requested_Catalog_Item__c, Requested_Catalog_Item__r.Name,
                   Assigned_Asset_Serial_Number__r.Name, Assigned_Asset_Serial_Number__r.Serial_Number__c,
                   Generated_Asset_Allocation__r.Name
            FROM Asset_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];

        AssetRequestDetail detail = new AssetRequestDetail();
        detail.requestId = requestRecord.Id;
        detail.requestNumber = requestRecord.Name;
        detail.accountName = requestRecord.Account__r != null ? requestRecord.Account__r.Name : null;
        detail.productName = requestRecord.Requested_Catalog_Item__r != null
            ? requestRecord.Requested_Catalog_Item__r.Name
            : null;
        if (requestRecord.get('Requested_Catalog_Item__c') != null) {
            Id productId = (Id)requestRecord.get('Requested_Catalog_Item__c');
            detail.productImageUrl = resolveProductImageUrls(new Set<Id>{ productId }).get(productId);
        }
        detail.requestType = requestRecord.Request_Type__c;
        detail.status = requestRecord.Status__c;
        detail.requestedInstallationDate = requestRecord.Requested_Installation_Date__c;
        detail.powerRequirement = requestRecord.Power_Requirement_Met__c;
        detail.spaceCleared = requestRecord.Space_Cleared_Dimensions__c;
        detail.retailerConsentObtained = requestRecord.Retailer_Consent_Obtained__c;
        detail.notes = requestRecord.Competitor_Asset_Details__c;
        detail.managerDecisionNotes = requestRecord.Manager_Decision_Notes__c;
        detail.siteReadinessPhotoUrl = requestRecord.Site_Readiness_Photo__c;
        detail.assignedAssetName = requestRecord.Assigned_Asset_Serial_Number__r != null
            ? requestRecord.Assigned_Asset_Serial_Number__r.Name
            : null;
        detail.assignedAssetSerialNumber = requestRecord.Assigned_Asset_Serial_Number__r != null
            ? requestRecord.Assigned_Asset_Serial_Number__r.Serial_Number__c
            : null;
        detail.allocationName = requestRecord.Generated_Asset_Allocation__r != null
            ? requestRecord.Generated_Asset_Allocation__r.Name
            : null;
        detail.createdDate = requestRecord.CreatedDate;
        return detail;
    }

    private static Map<Id, String> resolveProductImageUrls(Set<Id> productIds) {
        Map<Id, String> result = new Map<Id, String>();
        if (productIds == null || productIds.isEmpty()) {
            return result;
        }

        for (ContentDocumentLink link : [
            SELECT LinkedEntityId, ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :productIds
        ]) {
            if (!result.containsKey(link.LinkedEntityId) && link.ContentDocument.LatestPublishedVersionId != null) {
                result.put(
                    link.LinkedEntityId,
                    '/sfc/servlet.shepherd/version/download/' + link.ContentDocument.LatestPublishedVersionId
                );
            }
        }

        return result;
    }

    private static String firstNonBlank(List<String> values) {
        if (values == null) {
            return null;
        }

        for (String value : values) {
            if (String.isNotBlank(value)) {
                return value;
            }
        }
        return null;
    }

    @AuraEnabled
    public static RequestSubmitResult createRequest(
        Id visitId,
        Id accountId,
        String type,
        Id productId,
        Boolean socketAvailable,
        Boolean counterSpaceAvailable,
        Boolean retailerConsentObtained,
        String requestedInstallationDate,
        String notes,
        String photoBase64,
        String photoContentType,
        String photoFileName
    ) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (accountId == null) {
            throw new AuraHandledException('Store account is required.');
        }
        if (productId == null) {
            throw new AuraHandledException('Please select an asset type.');
        }
        if (String.isBlank(photoBase64)) {
            throw new AuraHandledException('Site-readiness photo is required.');
        }

        Visit__c visitRecord = [
            SELECT Id, Name, Outlet1__c
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

        if (visitRecord.Outlet1__c != accountId) {
            throw new AuraHandledException('This request must be submitted from the current visit store.');
        }

        Integer matchingInventoryCount = [
            SELECT COUNT()
            FROM Asset__c
            WHERE Asset_Status__c = 'In Warehouse'
            AND Product__c = :productId
        ];
        if (matchingInventoryCount == 0) {
            throw new AuraHandledException('This asset type is no longer available in warehouse inventory.');
        }

        Asset_Request__c requestRecord = new Asset_Request__c(
            Account__c = accountId,
            Requested_Catalog_Item__c = productId,
            Request_Type__c = resolveRequestType(type),
            Status__c = 'Pending Approval',
            Power_Requirement_Met__c = socketAvailable == true ? '5-Amp Available' : 'No Power Nearby',
            Space_Cleared_Dimensions__c = counterSpaceAvailable == true ? 'Yes - Countertop' : 'No - Pending',
            Retailer_Consent_Obtained__c = retailerConsentObtained == true,
            Requested_Installation_Date__c = String.isBlank(requestedInstallationDate)
                ? null
                : Date.valueOf(requestedInstallationDate),
            Competitor_Asset_Details__c = String.isBlank(notes) ? null : notes.trim()
        );
        insert requestRecord;

        if (String.isNotBlank(photoBase64)) {
            String resolvedPhotoUrl = uploadSiteReadinessPhoto(
                requestRecord.Id,
                photoBase64,
                photoContentType,
                photoFileName
            );
            update new Asset_Request__c(
                Id = requestRecord.Id,
                Site_Readiness_Photo__c = resolvedPhotoUrl
            );
        }

        RequestSubmitResult result = new RequestSubmitResult();
        result.requestId = requestRecord.Id;
        result.message = 'Request submitted — your manager will review it shortly.';
        return result;
    }

    private static String resolveRequestType(String requestedType) {
        if (requestedType == 'New Deployment') {
            return 'New Store/Empty Space';
        }
        if (requestedType == 'Competitor Takeover') {
            return 'Competitor Takeover';
        }
        if (requestedType == 'Upgrade/Refresh Old Asset') {
            return 'Upgrade/Refresh Old Asset';
        }
        return 'New Store/Empty Space';
    }

    private static String uploadSiteReadinessPhoto(
        Id requestId,
        String photoBase64,
        String photoContentType,
        String photoFileName
    ) {
        Blob body = EncodingUtil.base64Decode(photoBase64);
        String resolvedName = String.isBlank(photoFileName)
            ? 'Asset_Request_Site_Readiness.jpg'
            : photoFileName;

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
            LinkedEntityId = requestId,
            ContentDocumentId = version.ContentDocumentId,
            ShareType = 'V'
        );

        return '/sfc/servlet.shepherd/version/download/' + version.Id;
    }
}