public with sharing class ManagerVisitApprovalView {

    /**
     * Returns visits where current user is part of approval routing:
     * - currently assigned approver (pending work items)
     * - historical approver (approved/rejected steps)
     */
    @AuraEnabled(cacheable=true)
    public static List<Visit__c> getVisitsForManager() {
        Id currentUserId = UserInfo.getUserId();
        String visitPrefix = Visit__c.SObjectType.getDescribe().getKeyPrefix();
        Set<Id> visitIds = new Set<Id>();

        for (ProcessInstanceWorkitem wi : [
            SELECT ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE ActorId = :currentUserId
            AND ProcessInstance.TargetObjectId != null
        ]) {
            Id targetId = wi.ProcessInstance.TargetObjectId;
            if (String.valueOf(targetId).startsWith(visitPrefix)) {
                visitIds.add(targetId);
            }
        }

        for (ProcessInstanceStep st : [
            SELECT ProcessInstance.TargetObjectId
            FROM ProcessInstanceStep
            WHERE ActorId = :currentUserId
            AND StepStatus IN ('Approved', 'Rejected')
            AND ProcessInstance.TargetObjectId != null
        ]) {
            Id targetId = st.ProcessInstance.TargetObjectId;
            if (String.valueOf(targetId).startsWith(visitPrefix)) {
                visitIds.add(targetId);
            }
        }

        if (visitIds.isEmpty()) {
            return new List<Visit__c>();
        }

        return [
            SELECT
                Id,
                Name,
                Visit_Date__c,
                Visit_Status__c,
                Approval_Status__c,
                Planned_Start_Time__c,
                Planned_End_Time__c,
                Sales_Rep__c,
                Sales_Rep__r.Name,
                Outlet1__c,
                Outlet1__r.Name,
                Beat__c,
                Beat__r.Name,
                Is_Completed__c,
                Actual_Duration__c,
                Check_In_Time__c,
                Check_Out_Time__c,
                Check_In_Location__c,
                Check_Out_Location__c
            FROM Visit__c
            WHERE Id IN :visitIds
            ORDER BY Visit_Date__c DESC
            LIMIT 200
        ];
    }

    @AuraEnabled
    public static String approveVisit(Id visitId) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }

        Id workitemId = getCurrentUserWorkitemId(visitId, UserInfo.getUserId());
        if (workitemId == null) {
            throw new AuraHandledException('No pending approval work item found for current user.');
        }

        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setWorkitemId(workitemId);
        req.setAction('Approve');
        req.setComments('Approved via Manager Visit View.');

        Approval.ProcessResult result = Approval.process(req);
        if (result == null || !result.isSuccess()) {
            throw new AuraHandledException('Approval action failed.');
        }
        return 'SUCCESS';
    }

    @AuraEnabled
    public static String rejectVisit(Id visitId, String comments) {
        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (String.isBlank(comments)) {
            throw new AuraHandledException('Rejection comment is mandatory.');
        }

        Id workitemId = getCurrentUserWorkitemId(visitId, UserInfo.getUserId());
        if (workitemId == null) {
            throw new AuraHandledException('No pending approval work item found for current user.');
        }

        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setWorkitemId(workitemId);
        req.setAction('Reject');
        req.setComments(comments.trim());

        Approval.ProcessResult result = Approval.process(req);
        if (result == null || !result.isSuccess()) {
            throw new AuraHandledException('Rejection action failed.');
        }
        return 'SUCCESS';
    }

    private static Boolean isCurrentApprover(Id visitId, Id userId) {
        Integer pendingCount = [
            SELECT COUNT()
            FROM ProcessInstanceWorkitem
            WHERE ActorId = :userId
            AND ProcessInstance.TargetObjectId = :visitId
        ];
        return pendingCount > 0;
    }

    private static Id getCurrentUserWorkitemId(Id visitId, Id userId) {
        List<ProcessInstanceWorkitem> items = [
            SELECT Id
            FROM ProcessInstanceWorkitem
            WHERE ActorId = :userId
            AND ProcessInstance.TargetObjectId = :visitId
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return items.isEmpty() ? null : items[0].Id;
    }
}