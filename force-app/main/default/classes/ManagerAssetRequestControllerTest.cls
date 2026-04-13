@IsTest
private class ManagerAssetRequestControllerTest {

    private static User buildUser(String lastName, String alias) {
        String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
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
    }

    @TestSetup
    static void setup() {
        User managerUser = buildUser('MGR_AssetRequest', 'mgrasset');
        insert managerUser;

        User repUser = buildUser('REP_AssetRequest', 'repasset');
        repUser.ManagerId = managerUser.Id;
        insert repUser;

        User otherManager = buildUser('MGR_OtherAsset', 'mgrother');
        insert otherManager;

        User otherRep = buildUser('REP_OtherAsset', 'repother');
        otherRep.ManagerId = otherManager.Id;
        insert otherRep;
    }

    private static User getManager() {
        return [SELECT Id FROM User WHERE LastName = 'MGR_AssetRequest' LIMIT 1];
    }

    private static User getRep() {
        return [SELECT Id FROM User WHERE LastName = 'REP_AssetRequest' LIMIT 1];
    }

    private static User getOtherManager() {
        return [SELECT Id FROM User WHERE LastName = 'MGR_OtherAsset' LIMIT 1];
    }

    private static User getOtherRep() {
        return [SELECT Id FROM User WHERE LastName = 'REP_OtherAsset' LIMIT 1];
    }

    private static Account createOutlet(String name) {
        Account outlet = new Account(Name = name);
        insert outlet;
        return outlet;
    }

    private static Asset_Request__c createAssetRequest(String statusValue, String suffix) {
        Account outlet = createOutlet('Asset Request Outlet ' + suffix);
        Asset_Request__c requestRecord = new Asset_Request__c(
            Account__c = outlet.Id,
            Request_Type__c = 'New Store/Empty Space',
            Status__c = statusValue,
            Competitor_Asset_Details__c = 'Notes ' + suffix
        );
        insert requestRecord;
        return requestRecord;
    }

    @IsTest
    static void testGetAssetRequestsForManager_returnsMatchingStatusesOnly() {
        User rep = getRep();
        User otherRep = getOtherRep();
        Asset_Request__c pendingRequest;
        Asset_Request__c approvedRequest;
        Asset_Request__c rejectedRequest;

        System.runAs(rep) {
            pendingRequest = createAssetRequest('Pending Approval', 'Pending');
            approvedRequest = createAssetRequest('Approved', 'Approved');
            rejectedRequest = createAssetRequest('Rejected', 'Rejected');
            createAssetRequest('Draft', 'Draft');
        }

        System.runAs(otherRep) {
            createAssetRequest('Pending Approval', 'OtherManager');
        }

        System.runAs(getManager()) {
            Test.startTest();
            List<Asset_Request__c> result = ManagerAssetRequestController.getAssetRequestsForManager();
            Test.stopTest();

            System.assertEquals(3, result.size(), 'Only this manager\'s pending/approved/rejected requests should be returned.');
            Set<Id> resultIds = new Set<Id>();
            for (Asset_Request__c row : result) {
                resultIds.add(row.Id);
            }
            System.assert(resultIds.contains(pendingRequest.Id), 'Pending request should be included.');
            System.assert(resultIds.contains(approvedRequest.Id), 'Approved request should be included.');
            System.assert(resultIds.contains(rejectedRequest.Id), 'Rejected request should be included.');
        }
    }

    @IsTest
    static void testApproveAssetRequest_success() {
        User rep = getRep();
        Asset_Request__c requestRecord;

        System.runAs(rep) {
            requestRecord = createAssetRequest('Pending Approval', 'Approve');
        }

        System.runAs(getManager()) {
            Test.startTest();
            String result = ManagerAssetRequestController.approveAssetRequest(requestRecord.Id, 'Looks good.');
            Test.stopTest();
            System.assertEquals('SUCCESS', result, 'Approve should return SUCCESS.');
        }

        Asset_Request__c updated = [
            SELECT Status__c, Manager_Decision_Notes__c
            FROM Asset_Request__c
            WHERE Id = :requestRecord.Id
        ];
        System.assertEquals('Approved', updated.Status__c, 'Status should be updated to Approved.');
        System.assertEquals('Looks good.', updated.Manager_Decision_Notes__c, 'Approval note should be saved.');
    }

    @IsTest
    static void testRejectAssetRequest_success() {
        User rep = getRep();
        Asset_Request__c requestRecord;

        System.runAs(rep) {
            requestRecord = createAssetRequest('Pending Approval', 'Reject');
        }

        System.runAs(getManager()) {
            Test.startTest();
            String result = ManagerAssetRequestController.rejectAssetRequest(requestRecord.Id, 'Please revisit site readiness.');
            Test.stopTest();
            System.assertEquals('SUCCESS', result, 'Reject should return SUCCESS.');
        }

        Asset_Request__c updated = [
            SELECT Status__c, Manager_Decision_Notes__c
            FROM Asset_Request__c
            WHERE Id = :requestRecord.Id
        ];
        System.assertEquals('Rejected', updated.Status__c, 'Status should be updated to Rejected.');
        System.assertEquals('Please revisit site readiness.', updated.Manager_Decision_Notes__c, 'Rejection note should be saved.');
    }

    @IsTest
    static void testRejectAssetRequest_blankComment_throws() {
        User rep = getRep();
        Asset_Request__c requestRecord;

        System.runAs(rep) {
            requestRecord = createAssetRequest('Pending Approval', 'BlankComment');
        }

        System.runAs(getManager()) {
            Test.startTest();
            try {
                ManagerAssetRequestController.rejectAssetRequest(requestRecord.Id, '   ');
                System.assert(false, 'Expected rejection comment validation error.');
            } catch (AuraHandledException ex) {
                System.assert(ex.getMessage().contains('Rejection comment is mandatory.'));
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testApproveAssetRequest_wrongManager_throws() {
        User rep = getRep();
        Asset_Request__c requestRecord;

        System.runAs(rep) {
            requestRecord = createAssetRequest('Pending Approval', 'WrongManager');
        }

        System.runAs(getOtherManager()) {
            Test.startTest();
            try {
                ManagerAssetRequestController.approveAssetRequest(requestRecord.Id, 'Attempted approval.');
                System.assert(false, 'Expected authorization error.');
            } catch (AuraHandledException ex) {
                System.assert(ex.getMessage().contains('not authorized'));
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testApproveAssetRequest_nonPending_throws() {
        User rep = getRep();
        Asset_Request__c requestRecord;

        System.runAs(rep) {
            requestRecord = createAssetRequest('Approved', 'AlreadyApproved');
        }

        System.runAs(getManager()) {
            Test.startTest();
            try {
                ManagerAssetRequestController.approveAssetRequest(requestRecord.Id, 'Another pass.');
                System.assert(false, 'Expected status validation error.');
            } catch (AuraHandledException ex) {
                System.assert(ex.getMessage().contains('Only pending asset requests can be processed.'));
            }
            Test.stopTest();
        }
    }
}