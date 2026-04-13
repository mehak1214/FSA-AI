/**
 * ManagerStoreController
 * Serves the managerStoreApproval LWC component.
 */
public with sharing class ManagerStoreController {

    // ─── Wrappers ─────────────────────────────────────────────────────────────

    public class StoreWrapper {
        @AuraEnabled public String  accountId;
        @AuraEnabled public String  accountName;
        @AuraEnabled public String  outletStatus;
        @AuraEnabled public String  businessType;
        @AuraEnabled public String  phone;
        @AuraEnabled public String  ownerName;
        @AuraEnabled public String  ownerEmail;
        @AuraEnabled public String  ownerSalutation;
        @AuraEnabled public String  ownerFirstName;
        @AuraEnabled public String  ownerLastName;
        @AuraEnabled public String  ownerTitle;
        @AuraEnabled public String  city;
        @AuraEnabled public String  state;
        @AuraEnabled public String  recordTypeLabel;
        @AuraEnabled public String  recordTypeDeveloperName;
        @AuraEnabled public String  submittedByName;
        @AuraEnabled public String  submittedDate;
        @AuraEnabled public String  processedDate;
        @AuraEnabled public String  workitemId;
        @AuraEnabled public String  rejectionReason;
        @AuraEnabled public String  shopActLicense;
        @AuraEnabled public String  billingStreet;
        @AuraEnabled public String  billingCity;
        @AuraEnabled public String  billingPostalCode;
        @AuraEnabled public String  billingState;
        @AuraEnabled public String  billingCountry;
        @AuraEnabled public String  shippingStreet;
        @AuraEnabled public String  shippingCity;
        @AuraEnabled public String  shippingPostalCode;
        @AuraEnabled public String  shippingState;
        @AuraEnabled public String  shippingCountry;
        @AuraEnabled public String  locationLatitude;
        @AuraEnabled public String  locationLongitude;
    }

    public class ApprovalSummaryWrapper {
        @AuraEnabled public Integer pendingCount;
        @AuraEnabled public Integer approvedTodayCount;
        @AuraEnabled public Integer rejectedThisWeekCount;
        @AuraEnabled public Integer totalActiveCount;
    }

    // ─── Pending Approval Queue ───────────────────────────────────────────────

    @AuraEnabled
    public static List<StoreWrapper> getPendingApprovalStores() {
        Id currentUserId = UserInfo.getUserId();

        List<ProcessInstanceWorkitem> workitems = [
            SELECT Id, ProcessInstance.TargetObjectId,
                   ProcessInstance.TargetObject.Name,
                   ProcessInstance.SubmittedById,
                   ProcessInstance.SubmittedBy.Name,
                   ProcessInstance.CreatedDate
            FROM ProcessInstanceWorkitem
            WHERE ActorId = :currentUserId
            AND   ProcessInstance.Status = 'Pending'
        ];

        if (workitems.isEmpty()) return new List<StoreWrapper>();

        Set<Id> accountIds = new Set<Id>();
        Map<Id, ProcessInstanceWorkitem> workitemByAccountId = new Map<Id, ProcessInstanceWorkitem>();
        for (ProcessInstanceWorkitem wi : workitems) {
            Id targetId = wi.ProcessInstance.TargetObjectId;
            if (targetId != null && targetId.getSObjectType() == Account.SObjectType) {
                accountIds.add(targetId);
                workitemByAccountId.put(targetId, wi);
            }
        }

        if (accountIds.isEmpty()) return new List<StoreWrapper>();

        List<Account> accounts = [
            SELECT Id, Name, OutletStatus__c, Type,
                   Phone, Owner_Name__c, Owner_Email__c,
                   BillingCity, BillingState,
                   BillingStreet, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingPostalCode,
                   ShippingState, ShippingCountry,
                   RecordType.Name, RecordType.DeveloperName,
                   Shop_Act_License_Number__c,
                   Rejection_Reason__c,
                   Outlet_Location__latitude__s,
                   Outlet_Location__longitude__s
            FROM Account
            WHERE Id IN :accountIds
            AND   RecordType.DeveloperName IN ('Franchise', 'Dealer_Distributor')
            ORDER BY Name ASC
        ];

        List<StoreWrapper> result = new List<StoreWrapper>();
        for (Account acc : accounts) {
            StoreWrapper w          = toStoreWrapper(acc);
            ProcessInstanceWorkitem wi = workitemByAccountId.get(acc.Id);
            w.workitemId            = wi.Id;
            w.submittedByName       = wi.ProcessInstance.SubmittedBy?.Name;
            w.submittedDate         = wi.ProcessInstance.CreatedDate != null
                ? String.valueOf(wi.ProcessInstance.CreatedDate.date())
                : null;
            result.add(w);
        }
        return result;
    }

    // ─── Processed Stores (Approved / Rejected by current user) ──────────────
    // Returns stores where the logged-in manager took an Approve or Reject
    // action via ProcessInstanceStep. Approved stores must be OutletStatus=Active,
    // Rejected stores must be OutletStatus=Rejected.

    @AuraEnabled
    public static List<StoreWrapper> getProcessedStores() {
        Id currentUserId = UserInfo.getUserId();

        // Fetch all steps where this manager was the actor
        List<ProcessInstanceStep> steps = [
            SELECT Id,
                   StepStatus,
                   CreatedDate,
                   Comments,
                   ProcessInstance.TargetObjectId,
                   ProcessInstance.SubmittedBy.Name,
                   ProcessInstance.CreatedDate
            FROM ProcessInstanceStep
            WHERE ActorId    = :currentUserId
            AND   StepStatus IN ('Approved', 'Rejected')
            AND   ProcessInstance.TargetObjectId != null
            ORDER BY CreatedDate DESC
        ];

        if (steps.isEmpty()) return new List<StoreWrapper>();

        // Keep only Account (001) records; one entry per account (most recent step)
        Map<Id, ProcessInstanceStep> latestStepByAccount = new Map<Id, ProcessInstanceStep>();
        for (ProcessInstanceStep s : steps) {
            Id targetId = s.ProcessInstance.TargetObjectId;
            if (targetId != null && targetId.getSObjectType() == Account.SObjectType) {
                if (!latestStepByAccount.containsKey(targetId)) {
                    latestStepByAccount.put(targetId, s);
                }
            }
        }

        if (latestStepByAccount.isEmpty()) return new List<StoreWrapper>();

        List<Account> accounts = [
            SELECT Id, Name, OutletStatus__c, Type,
                   Phone, Owner_Name__c, Owner_Email__c,
                   BillingCity, BillingState,
                   BillingStreet, BillingPostalCode, BillingCountry,
                   ShippingStreet, ShippingCity, ShippingPostalCode,
                   ShippingState, ShippingCountry,
                   RecordType.Name, RecordType.DeveloperName,
                   Shop_Act_License_Number__c,
                   Rejection_Reason__c,
                   Outlet_Location__latitude__s,
                   Outlet_Location__longitude__s
            FROM Account
            WHERE Id IN :latestStepByAccount.keySet()
            AND   RecordType.DeveloperName IN ('Franchise', 'Dealer_Distributor')
            AND   OutletStatus__c IN ('Active', 'Rejected')
            ORDER BY Name ASC
        ];

        List<StoreWrapper> result = new List<StoreWrapper>();
        for (Account acc : accounts) {
            ProcessInstanceStep step = latestStepByAccount.get(acc.Id);

            // Only include if the current status matches the manager's decision
            Boolean approvedMatch = step.StepStatus == 'Approved' && acc.OutletStatus__c == 'Active';
            Boolean rejectedMatch = step.StepStatus == 'Rejected' && acc.OutletStatus__c == 'Rejected';
            if (!approvedMatch && !rejectedMatch) continue;

            StoreWrapper w    = toStoreWrapper(acc);
            w.submittedByName = step.ProcessInstance.SubmittedBy?.Name;
            w.submittedDate   = step.ProcessInstance.CreatedDate != null
                ? String.valueOf(step.ProcessInstance.CreatedDate.date())
                : null;
            w.processedDate   = step.CreatedDate != null
                ? String.valueOf(step.CreatedDate.date())
                : null;
            // Prefer step comments for rejection reason (more reliable than field)
            if (step.StepStatus == 'Rejected' && String.isNotBlank(step.Comments)) {
                w.rejectionReason = step.Comments;
            }
            result.add(w);
        }
        return result;
    }

    // ─── Approval Summary KPIs ────────────────────────────────────────────────

    @AuraEnabled
    public static ApprovalSummaryWrapper getApprovalSummary() {
        Id currentUserId = UserInfo.getUserId();

        Integer pending = [
            SELECT COUNT() FROM ProcessInstanceWorkitem
            WHERE ActorId = :currentUserId
            AND   ProcessInstance.Status = 'Pending'
        ];

        Integer totalActive = [
            SELECT COUNT() FROM Account WHERE OutletStatus__c = 'Active'
        ];

        Date today       = Date.today();
        Date weekStart   = today.toStartOfWeek();
        DateTime todayStart  = DateTime.newInstance(today,     Time.newInstance(0,0,0,0));
        DateTime weekStartDT = DateTime.newInstance(weekStart, Time.newInstance(0,0,0,0));

        List<ProcessInstanceStep> steps = [
            SELECT StepStatus, CreatedDate
            FROM   ProcessInstanceStep
            WHERE  ActorId      = :currentUserId
            AND    StepStatus   IN ('Approved', 'Rejected')
            AND    CreatedDate >= :weekStartDT
        ];

        Integer approvedToday    = 0;
        Integer rejectedThisWeek = 0;
        for (ProcessInstanceStep s : steps) {
            if (s.StepStatus == 'Rejected') {
                rejectedThisWeek++;
            } else if (s.StepStatus == 'Approved' && s.CreatedDate >= todayStart) {
                approvedToday++;
            }
        }

        ApprovalSummaryWrapper s  = new ApprovalSummaryWrapper();
        s.pendingCount            = pending;
        s.approvedTodayCount      = approvedToday;
        s.rejectedThisWeekCount   = rejectedThisWeek;
        s.totalActiveCount        = totalActive;
        return s;
    }

    // ─── Approve / Reject via Approval Process ────────────────────────────────

    @AuraEnabled
    public static void processStoreApproval(String workitemId, String action, String comments) {
        if (String.isBlank(workitemId)) {
            throw new AuraHandledException('No pending approval workitem found.');
        }
        if (action != 'Approve' && action != 'Reject') {
            throw new AuraHandledException('Invalid action. Must be Approve or Reject.');
        }
        if (action == 'Reject' && String.isBlank(comments)) {
            throw new AuraHandledException('A rejection reason is required.');
        }

        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setWorkitemId(workitemId);
        req.setAction(action);
        if (String.isNotBlank(comments)) {
            req.setComments(comments);
        }

        Approval.ProcessResult result = Approval.process(req);
        if (!result.isSuccess()) {
            String msg = '';
            for (Database.Error err : result.getErrors()) {
                msg += err.getMessage() + ' ';
            }
            throw new AuraHandledException(msg.trim());
        }

        Id accountId = result.getEntityId();
        if (accountId != null) {
            String newStatus = (action == 'Approve') ? 'Active' : 'Rejected';
            Account acc = new Account(Id = accountId, OutletStatus__c = newStatus);
            if (action == 'Reject' && String.isNotBlank(comments)) {
                acc.Rejection_Reason__c = comments;
            }
            try { update acc; } catch (DmlException e) { /* best-effort */ }
        }
    }

    // ─── Account Files ────────────────────────────────────────────────────────

    public class FileWrapper {
        @AuraEnabled public String documentId;
        @AuraEnabled public String title;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public Long   contentSize;
        @AuraEnabled public String fileType;      // IMAGE | PDF | DOC | OTHER
        @AuraEnabled public String previewUrl;    // /sfc/servlet.shepherd/document/download/{docId}
    }

    @AuraEnabled
    public static List<FileWrapper> getAccountFiles(Id accountId) {
        if (accountId == null) return new List<FileWrapper>();

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId,
                   ContentDocument.Title,
                   ContentDocument.FileExtension,
                   ContentDocument.ContentSize,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :accountId
            WITH SECURITY_ENFORCED
            ORDER BY ContentDocument.CreatedDate DESC
        ];

        List<FileWrapper> result = new List<FileWrapper>();
        for (ContentDocumentLink cdl : links) {
            FileWrapper fw       = new FileWrapper();
            fw.documentId        = cdl.ContentDocumentId;
            fw.title             = cdl.ContentDocument.Title;
            fw.fileExtension     = (cdl.ContentDocument.FileExtension ?? '').toLowerCase();
            fw.contentSize       = cdl.ContentDocument.ContentSize;
            // Classify for icon rendering in LWC
            Set<String> imageExts = new Set<String>{ 'jpg','jpeg','png','gif','webp','bmp','svg' };
            Set<String> docExts   = new Set<String>{ 'doc','docx','xls','xlsx','ppt','pptx','txt','csv' };
            if (imageExts.contains(fw.fileExtension))     fw.fileType = 'IMAGE';
            else if (fw.fileExtension == 'pdf')           fw.fileType = 'PDF';
            else if (docExts.contains(fw.fileExtension))  fw.fileType = 'DOC';
            else                                           fw.fileType = 'OTHER';
            // Preview URL for inline rendering
            fw.previewUrl = '/sfc/servlet.shepherd/document/download/' + cdl.ContentDocumentId;
            result.add(fw);
        }
        return result;
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    private static StoreWrapper toStoreWrapper(Account acc) {
        StoreWrapper w              = new StoreWrapper();
        w.accountId                 = acc.Id;
        w.accountName               = acc.Name;
        w.outletStatus              = acc.OutletStatus__c;
        w.businessType              = acc.Type;
        w.phone                     = acc.Phone;
        w.ownerName                 = acc.Owner_Name__c;
        w.ownerEmail                = acc.Owner_Email__c;
        w.city                      = acc.BillingCity;
        w.state                     = acc.BillingState;
        w.recordTypeLabel           = acc.RecordType?.Name;
        w.recordTypeDeveloperName   = acc.RecordType?.DeveloperName;
        w.shopActLicense            = acc.Shop_Act_License_Number__c;
        w.billingStreet             = acc.BillingStreet;
        w.billingCity               = acc.BillingCity;
        w.billingPostalCode         = acc.BillingPostalCode;
        w.billingState              = acc.BillingState;
        w.billingCountry            = acc.BillingCountry;
        w.shippingStreet            = acc.ShippingStreet;
        w.shippingCity              = acc.ShippingCity;
        w.shippingPostalCode        = acc.ShippingPostalCode;
        w.shippingState             = acc.ShippingState;
        w.shippingCountry           = acc.ShippingCountry;
        w.rejectionReason           = acc.Rejection_Reason__c;
        if (acc.Outlet_Location__latitude__s  != null) {
            w.locationLatitude  = String.valueOf(acc.Outlet_Location__latitude__s);
            w.locationLongitude = String.valueOf(acc.Outlet_Location__longitude__s);
        }
        // Pull split owner fields from the primary Contact
        List<Contact> contacts = [
            SELECT Salutation, FirstName, LastName, Title
            FROM Contact
            WHERE AccountId          = :acc.Id
            AND   Primary_Contact__c = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!contacts.isEmpty()) {
            Contact c        = contacts[0];
            w.ownerSalutation = c.Salutation;
            w.ownerFirstName  = c.FirstName;
            w.ownerLastName   = c.LastName;
            w.ownerTitle      = c.Title;
        }
        return w;
    }
}