public with sharing class AccountRecordHubController {

    public class AccountListItem {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String phone;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String site;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String outletOwnerName;
        @AuraEnabled public String recordTypeDeveloperName;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public String outletStatus;
        @AuraEnabled public String outletPriority;
        @AuraEnabled public String visitFrequency;
        @AuraEnabled public String rejectionReason;
        @AuraEnabled public Datetime lastModifiedDate;
    }

    // Statuses visible to all users (public)
    private static final Set<String> PUBLIC_STATUSES = new Set<String>{ 'Active', 'Inactive' };

    @AuraEnabled(cacheable=true)
    public static List<AccountListItem> getAccountsByType(
        String recordTypeDeveloperName,
        String searchText,
        Integer maxRows,
        Long refreshToken
    ) {
        Set<String> allowedRecordTypes = new Set<String>{ 'Dealer_Distributor', 'Franchise' };
        String selectedType = String.isBlank(recordTypeDeveloperName)
            ? 'Dealer_Distributor'
            : recordTypeDeveloperName.trim();

        if (!allowedRecordTypes.contains(selectedType)) {
            throw new AuraHandledException('Unsupported record type filter.');
        }

        Integer safeLimit = (maxRows == null || maxRows <= 0) ? 200 : Math.min(maxRows, 500);
        String normalizedSearch = String.isBlank(searchText) ? null : '%' + searchText.trim() + '%';
        Id currentUserId = UserInfo.getUserId();

        // Active / Inactive  → visible to all users
        // Draft / Submitted / Rejected / Abandoned → visible only to the record's creator
        String query =
            'SELECT Id, Name, Phone, BillingCity, BillingState, Site, Owner.Name, Owner_Name__c, ' +
            'RecordType.DeveloperName, RecordType.Name, OutletStatus__c, Outlet_Priority__c, ' +
            'Visit_Frequency__c, Rejection_Reason__c, LastModifiedDate ' +
            'FROM Account ' +
            'WHERE RecordType.DeveloperName = :selectedType ' +
            'AND (OutletStatus__c IN :PUBLIC_STATUSES OR CreatedById = :currentUserId) ';

        if (normalizedSearch != null) {
            query +=
                'AND (Name LIKE :normalizedSearch ' +
                'OR Phone LIKE :normalizedSearch ' +
                'OR BillingCity LIKE :normalizedSearch ' +
                'OR Site LIKE :normalizedSearch) ';
        }

        query += 'ORDER BY Name ASC LIMIT :safeLimit';

        List<Account> accounts = Database.query(query);
        List<AccountListItem> items = new List<AccountListItem>();

        for (Account acc : accounts) {
            AccountListItem item = new AccountListItem();
            item.accountId               = acc.Id;
            item.accountName             = acc.Name;
            item.phone                   = acc.Phone;
            item.city                    = acc.BillingCity;
            item.state                   = acc.BillingState;
            item.site                    = acc.Site;
            item.ownerName               = acc.Owner != null ? acc.Owner.Name : null;
            item.outletOwnerName         = (String)acc.get('Owner_Name__c');
            item.recordTypeDeveloperName = (acc.RecordType != null) ? acc.RecordType.DeveloperName : null;
            item.recordTypeLabel         = (acc.RecordType != null) ? acc.RecordType.Name : null;
            item.outletStatus            = (String)acc.get('OutletStatus__c');
            item.outletPriority          = (String)acc.get('Outlet_Priority__c');
            item.visitFrequency          = (String)acc.get('Visit_Frequency__c');
            item.rejectionReason         = (String)acc.get('Rejection_Reason__c');
            item.lastModifiedDate        = acc.LastModifiedDate;
            items.add(item);
        }

        return items;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Id> getAccountRecordTypeIds() {
        Map<String, Id> output = new Map<String, Id>();
        List<RecordType> accountRecordTypes = [
            SELECT Id, DeveloperName
            FROM RecordType
            WHERE SObjectType = 'Account'
            AND IsActive = true
            AND DeveloperName IN ('Dealer_Distributor', 'Franchise')
        ];

        for (RecordType rt : accountRecordTypes) {
            output.put(rt.DeveloperName, rt.Id);
        }

        // Fallback to describe-based lookup in case query returns no rows in restricted contexts.
        if (output.isEmpty()) {
            Map<String, Schema.RecordTypeInfo> infosByDeveloperName =
                Account.SObjectType.getDescribe().getRecordTypeInfosByDeveloperName();
            if (infosByDeveloperName.containsKey('Dealer_Distributor')) {
                output.put('Dealer_Distributor', infosByDeveloperName.get('Dealer_Distributor').getRecordTypeId());
            }
            if (infosByDeveloperName.containsKey('Franchise')) {
                output.put('Franchise', infosByDeveloperName.get('Franchise').getRecordTypeId());
            }
        }

        return output;
    }
}