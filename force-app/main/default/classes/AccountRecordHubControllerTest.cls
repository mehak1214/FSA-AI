@IsTest
private class AccountRecordHubControllerTest {

    @TestSetup
    static void setupData() {

        Map<String, Id> rtByDevName = getRequiredRecordTypes();

        Boolean hasRecordTypes = Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId');

        Account dealerAlpha = new Account(
            Name = 'Dealer Alpha',
            Phone = '1111111111',
            BillingCity = 'Pune',
            BillingState = 'MH',
            Owner_Name__c = 'Dealer Owner A',
            OutletStatus__c = 'Active'
        );
        if (hasRecordTypes) {
            dealerAlpha.put('RecordTypeId', rtByDevName.get('Dealer_Distributor'));
        }

        Account dealerBeta = new Account(
            Name = 'Dealer Beta',
            Phone = '2222222222',
            BillingCity = 'Mumbai',
            BillingState = 'MH',
            Owner_Name__c = 'Dealer Owner B',
            OutletStatus__c = 'Inactive'
        );
        if (hasRecordTypes) {
            dealerBeta.put('RecordTypeId', rtByDevName.get('Dealer_Distributor'));
        }

        Account franchiseOne = new Account(
            Name = 'Franchise One',
            Phone = '3333333333',
            BillingCity = 'Delhi',
            BillingState = 'DL',
            Owner_Name__c = 'Franchise Owner',
            OutletStatus__c = 'Active'
        );
        if (hasRecordTypes) {
            franchiseOne.put('RecordTypeId', rtByDevName.get('Franchise'));
        }

        insert new List<Account>{dealerAlpha, dealerBeta, franchiseOne};
    }

    private static Map<String, Id> getRequiredRecordTypes() {

        if (!Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')) {
            return new Map<String, Id>();
        }

        Map<String, Schema.RecordTypeInfo> rtInfos =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();

        System.assert(
            rtInfos.containsKey('Dealer_Distributor'),
            'Dealer_Distributor record type must exist in package.'
        );

        System.assert(
            rtInfos.containsKey('Franchise'),
            'Franchise record type must exist in package.'
        );

        Map<String, Id> result = new Map<String, Id>();
        result.put(
            'Dealer_Distributor',
            rtInfos.get('Dealer_Distributor').getRecordTypeId()
        );
        result.put(
            'Franchise',
            rtInfos.get('Franchise').getRecordTypeId()
        );

        return result;
    }

    @IsTest
    static void testGetAccountRecordTypeIds() {

        Test.startTest();
        Map<String, Id> rtMap =
            AccountRecordHubController.getAccountRecordTypeIds();
        Test.stopTest();

        System.assertNotEquals(null, rtMap);
        if (!Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')) {
            System.assertEquals(0, rtMap.size());
        } else {
            System.assert(rtMap.containsKey('Dealer_Distributor'));
            System.assert(rtMap.containsKey('Franchise'));
        }
    }

    @IsTest
    static void testGetAccountsByType_DealerDistributor() {

        Test.startTest();
        List<AccountRecordHubController.AccountListItem> dealers =
            AccountRecordHubController.getAccountsByType(
                'Dealer_Distributor',
                null,
                200,
                DateTime.now().getTime()
            );
        Test.stopTest();

        if (!Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')) {
            System.assertEquals(3, dealers.size());
        } else {
            System.assertEquals(2, dealers.size());
            System.assertEquals('Dealer Alpha', dealers[0].accountName);
        }
    }

    @IsTest
    static void testGetAccountsByType_Franchise() {

        Test.startTest();
        List<AccountRecordHubController.AccountListItem> franchises =
            AccountRecordHubController.getAccountsByType(
                'Franchise',
                null,
                200,
                DateTime.now().getTime()
            );
        Test.stopTest();

        if (!Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')) {
            System.assertEquals(3, franchises.size());
        } else {
            System.assertEquals(1, franchises.size());
            System.assertEquals('Franchise One', franchises[0].accountName);
        }
    }

    @IsTest
    static void testInvalidRecordTypeThrowsException() {

        Boolean exceptionThrown = false;

        Test.startTest();
        try {
            AccountRecordHubController.getAccountsByType(
                'Invalid_Record_Type',
                null,
                50,
                DateTime.now().getTime()
            );
        } catch (AuraHandledException ex) {
            exceptionThrown = true;
        }
        Test.stopTest();

        System.assertEquals(true, exceptionThrown);
    }
}