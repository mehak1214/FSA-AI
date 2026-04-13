/**
 * ManagerExpenseController
 * Apex controller for the Manager Expense Approval LWC components.
 *
 * Responsibilities:
 *  - Fetch Expense Reports pending the current user's approval (via ProcessInstanceWorkitem)
 *  - Fetch detail: Expense__c children for the report
 *  - Approve / Reject an Expense Report through the Approval Process
 *  - Bulk update Expense__c Status__c (no approval process on child records)
 */
public with sharing class ManagerExpenseController {

    // ─────────────────────────────────────────────
    // WRAPPERS
    // ─────────────────────────────────────────────
    public class ExpenseReportWrapper {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public String  reportDate;
        @AuraEnabled public String  status;
        @AuraEnabled public Decimal totalAmount;
        @AuraEnabled public String  salesRepId;
        @AuraEnabled public String  salesRepName;
        @AuraEnabled public String  rejectionReason;
        @AuraEnabled public String  workitemId;
        @AuraEnabled public Integer expenseCount;
        @AuraEnabled public Integer submittedCount;
        @AuraEnabled public Integer breachCount;    // expenses with Policy_Breach__c = true
    }

    public class LinkedVisitWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String outletName;
    }

    public class ExpenseFileWrapper {
        @AuraEnabled public String documentId;
        @AuraEnabled public String versionId;
        @AuraEnabled public String title;
        @AuraEnabled public String extension;
        @AuraEnabled public String fileType;
        @AuraEnabled public Long   fileSize;
    }

    public class ExpenseLineWrapper {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String  expenseType;
        @AuraEnabled public String  expenseDate;
        @AuraEnabled public String  status;
        @AuraEnabled public String  description;
        @AuraEnabled public String  visitId;
        @AuraEnabled public String  visitName;
        @AuraEnabled public String  rejectionReason;
        @AuraEnabled public Boolean policyBreach;
        @AuraEnabled public String  policyBreachType;
        @AuraEnabled public Decimal policyCapAtTime;
        @AuraEnabled public Decimal policyBreachAmount;
        @AuraEnabled public Decimal allowanceAtTime;
        @AuraEnabled public Decimal allowanceUsedAtTime;
        @AuraEnabled public List<LinkedVisitWrapper>  linkedVisits;
        @AuraEnabled public List<ExpenseFileWrapper>  files;
    }

    public class ReportDetailWrapper {
        @AuraEnabled public ExpenseReportWrapper     report;
        @AuraEnabled public List<ExpenseLineWrapper> expenses;
    }

    // ─────────────────────────────────────────────
    // GET PENDING APPROVAL REPORTS
    // ─────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ExpenseReportWrapper> getPendingApprovalReports() {

        // Find all users who report directly to the current logged-in user
        String currentUserId = UserInfo.getUserId();
        List<User> directReports = [
            SELECT Id FROM User
            WHERE  ManagerId = :currentUserId
            AND    IsActive   = true
        ];

        // If the current user manages nobody, return empty list rather than
        // accidentally exposing all reports
        if (directReports.isEmpty()) {
            return new List<ExpenseReportWrapper>();
        }

        Set<Id> repIds = new Set<Id>();
        for (User u : directReports) repIds.add(u.Id);

        // Query Submitted reports only for those reps
        List<Expense_Report__c> reports = [
            SELECT Id, Name, Report_Date__c, Status__c, Total_Amount__c,
                   Sales_Rep__c, Sales_Rep__r.Name,
                   Rejection_Reason__c,
                   (SELECT Id, Status__c, Policy_Breach__c FROM Expenses__r)
            FROM   Expense_Report__c
            WHERE  Status__c    = 'Submitted'
            AND    Sales_Rep__c IN :repIds
            ORDER BY Report_Date__c DESC
        ];

        List<ExpenseReportWrapper> result = new List<ExpenseReportWrapper>();
        for (Expense_Report__c r : reports) {
            // Skip reports that have no child expense lines — nothing to review
            if (r.Expenses__r == null || r.Expenses__r.isEmpty()) continue;

            ExpenseReportWrapper w = new ExpenseReportWrapper();
            w.id              = r.Id;
            w.name            = r.Name;
            w.reportDate      = r.Report_Date__c != null ? String.valueOf(r.Report_Date__c) : null;
            w.status          = r.Status__c;
            w.totalAmount     = r.Total_Amount__c;
            w.salesRepId      = r.Sales_Rep__c;
            w.salesRepName    = r.Sales_Rep__r != null ? r.Sales_Rep__r.Name : null;
            w.rejectionReason = r.Rejection_Reason__c;
            w.workitemId      = null;   // no approval process workitem
            w.expenseCount    = r.Expenses__r != null ? r.Expenses__r.size() : 0;
            w.submittedCount  = 0;
            w.breachCount     = 0;
            if (r.Expenses__r != null) {
                for (Expense__c e : r.Expenses__r) {
                    if (e.Status__c == 'Submitted') w.submittedCount++;
                    if (e.Policy_Breach__c)         w.breachCount++;
                }
            }
            result.add(w);
        }
        return result;
    }

    // ─────────────────────────────────────────────
    // GET REPORT DETAIL
    // ─────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static ReportDetailWrapper getReportDetail(String reportId) {

        Expense_Report__c report = [
            SELECT Id, Name, Report_Date__c, Status__c, Total_Amount__c,
                   Sales_Rep__c, Sales_Rep__r.Name,
                   Rejection_Reason__c
            FROM   Expense_Report__c
            WHERE  Id = :reportId
            LIMIT  1
        ];

        List<Expense__c> expenses = [
            SELECT Id, Name, Amount__c, Expense_Type__c, Expense_Date__c,
                   Status__c, Description__c, Visit__c, Visit__r.Name,
                   Rejection_Reason__c,
                   Policy_Breach__c, Policy_Breach_Type__c,
                   Policy_Cap_At_Time__c, Policy_Breach_Amount__c,
                   Allowance_At_Time__c, Allowance_Used_At_Time__c
            FROM   Expense__c
            WHERE  Expense_Report__c = :reportId
            ORDER BY Expense_Date__c ASC, CreatedDate ASC
        ];

        // Collect expense IDs for bulk linked-visits + files queries
        Set<Id> expenseIds = new Map<Id, Expense__c>(expenses).keySet();

        // Linked visits via junction object
        List<Expense_Visit_Link__c> links = [
            SELECT Expense__c, Visit__c, Visit__r.Name, Visit__r.Outlet1__r.Name
            FROM   Expense_Visit_Link__c
            WHERE  Expense__c IN :expenseIds
        ];
        Map<Id, List<LinkedVisitWrapper>> visitsByExpense = new Map<Id, List<LinkedVisitWrapper>>();
        for (Expense_Visit_Link__c lnk : links) {
            if (!visitsByExpense.containsKey(lnk.Expense__c)) {
                visitsByExpense.put(lnk.Expense__c, new List<LinkedVisitWrapper>());
            }
            LinkedVisitWrapper vw = new LinkedVisitWrapper();
            vw.id         = lnk.Visit__c;
            vw.name       = lnk.Visit__r.Name;
            vw.outletName = lnk.Visit__r.Outlet1__r != null ? lnk.Visit__r.Outlet1__r.Name : null;
            visitsByExpense.get(lnk.Expense__c).add(vw);
        }

        // Files via ContentDocumentLink
        List<ContentDocumentLink> cdls = [
            SELECT LinkedEntityId, ContentDocumentId,
                   ContentDocument.LatestPublishedVersionId,
                   ContentDocument.Title,
                   ContentDocument.FileExtension,
                   ContentDocument.FileType,
                   ContentDocument.ContentSize
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId IN :expenseIds
        ];
        Map<Id, List<ExpenseFileWrapper>> filesByExpense = new Map<Id, List<ExpenseFileWrapper>>();
        for (ContentDocumentLink cdl : cdls) {
            Id expId = cdl.LinkedEntityId;
            if (!filesByExpense.containsKey(expId)) {
                filesByExpense.put(expId, new List<ExpenseFileWrapper>());
            }
            ExpenseFileWrapper fw = new ExpenseFileWrapper();
            fw.documentId  = cdl.ContentDocumentId;
            fw.versionId   = cdl.ContentDocument.LatestPublishedVersionId;
            fw.title       = cdl.ContentDocument.Title;
            fw.extension   = cdl.ContentDocument.FileExtension;
            fw.fileType    = cdl.ContentDocument.FileType;
            fw.fileSize    = cdl.ContentDocument.ContentSize;
            filesByExpense.get(expId).add(fw);
        }

        // Build report wrapper
        ExpenseReportWrapper rw = new ExpenseReportWrapper();
        rw.id              = report.Id;
        rw.name            = report.Name;
        rw.reportDate      = report.Report_Date__c != null ? String.valueOf(report.Report_Date__c) : null;
        rw.status          = report.Status__c;
        rw.totalAmount     = report.Total_Amount__c;
        rw.salesRepId      = report.Sales_Rep__c;
        rw.salesRepName    = report.Sales_Rep__r != null ? report.Sales_Rep__r.Name : null;
        rw.rejectionReason = report.Rejection_Reason__c;
        rw.workitemId      = null;
        rw.expenseCount    = expenses.size();
        rw.submittedCount  = 0;

        // Build expense line wrappers
        List<ExpenseLineWrapper> expWrappers = new List<ExpenseLineWrapper>();
        for (Expense__c e : expenses) {
            ExpenseLineWrapper ew = new ExpenseLineWrapper();
            ew.id                  = e.Id;
            ew.name                = e.Name;
            ew.amount              = e.Amount__c;
            ew.expenseType         = e.Expense_Type__c;
            ew.expenseDate         = e.Expense_Date__c != null ? String.valueOf(e.Expense_Date__c) : null;
            ew.status              = e.Status__c;
            ew.description         = e.Description__c;
            ew.visitId             = e.Visit__c;
            ew.visitName           = e.Visit__r != null ? e.Visit__r.Name : null;
            ew.rejectionReason     = e.Rejection_Reason__c;
            ew.policyBreach        = e.Policy_Breach__c;
            ew.policyBreachType    = e.Policy_Breach_Type__c;
            ew.policyCapAtTime     = e.Policy_Cap_At_Time__c;
            ew.policyBreachAmount  = e.Policy_Breach_Amount__c;
            ew.allowanceAtTime     = e.Allowance_At_Time__c;
            ew.allowanceUsedAtTime = e.Allowance_Used_At_Time__c;
            ew.linkedVisits        = visitsByExpense.containsKey(e.Id) ? visitsByExpense.get(e.Id) : new List<LinkedVisitWrapper>();
            ew.files               = filesByExpense.containsKey(e.Id)  ? filesByExpense.get(e.Id)  : new List<ExpenseFileWrapper>();
            expWrappers.add(ew);
            if (e.Status__c == 'Submitted') rw.submittedCount++;
        }

        ReportDetailWrapper detail = new ReportDetailWrapper();
        detail.report   = rw;
        detail.expenses = expWrappers;
        return detail;
    }

    // ─────────────────────────────────────────────
    // APPROVE / REJECT EXPENSE REPORT
    // action: 'Approve' or 'Reject'
    // ─────────────────────────────────────────────
    @AuraEnabled
    public static void processReportApproval(String workitemId, String action, String comments) {
        if (String.isBlank(workitemId)) {
            throw new AuraHandledException('No pending approval workitem found for this report.');
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
    }

    // ─────────────────────────────────────────────
    // BULK UPDATE EXPENSE STATUS
    // scope:     'All' | 'Submitted'
    // newStatus: 'Approved' | 'Rejected'
    // ─────────────────────────────────────────────
    @AuraEnabled
    public static void bulkUpdateExpenseStatus(String reportId, String scope, String newStatus, String rejectionReason) {

        List<Expense__c> expenses = [
            SELECT Id, Status__c
            FROM   Expense__c
            WHERE  Expense_Report__c = :reportId
        ];

        List<Expense__c> toUpdate  = new List<Expense__c>();
        List<Expense__c> toAudit   = new List<Expense__c>();  // snapshot old statuses before update
        for (Expense__c e : expenses) {
            Boolean include = (scope == 'All') ||
                              (scope == 'Submitted' && e.Status__c == 'Submitted');
            if (include) {
                toAudit.add(new Expense__c(Id = e.Id, Status__c = e.Status__c)); // preserve old status
                Expense__c upd = new Expense__c(Id = e.Id, Status__c = newStatus);
                if (newStatus == 'Rejected' && String.isNotBlank(rejectionReason)) {
                    upd.Rejection_Reason__c = rejectionReason;
                }
                toUpdate.add(upd);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
            ExpenseAuditLogger.logBulkExpenseStatusChange(toAudit, newStatus, reportId, rejectionReason);
            syncReportStatus(reportId);
        }
    }

    // ─────────────────────────────────────────────
    // UPDATE SINGLE EXPENSE STATUS
    // ─────────────────────────────────────────────
    @AuraEnabled
    public static void updateExpenseStatus(String expenseId, String newStatus, String rejectionReason) {
        Expense__c exp = [SELECT Id, Status__c, Expense_Report__c FROM Expense__c WHERE Id = :expenseId LIMIT 1];
        String oldStatus = exp.Status__c;
        exp.Status__c = newStatus;
        if (newStatus == 'Rejected' && String.isNotBlank(rejectionReason)) {
            exp.Rejection_Reason__c = rejectionReason;
        }
        update exp;
        // Audit log
        if (newStatus == 'Approved') {
            ExpenseAuditLogger.logExpenseApproved(exp.Id, exp.Expense_Report__c);
        } else if (newStatus == 'Rejected') {
            ExpenseAuditLogger.logExpenseRejected(exp.Id, exp.Expense_Report__c, rejectionReason);
        }
        syncReportStatus(exp.Expense_Report__c);
    }

    // ─────────────────────────────────────────────
    // SYNC REPORT STATUS based on child expense statuses
    //   Any Submitted → Report = 'Submitted'
    //   No Submitted, but has non-Draft → Report = 'Completed'
    //   All Draft → Report stays 'Draft'
    // ─────────────────────────────────────────────
    private static void syncReportStatus(Id reportId) {
        if (reportId == null) return;

        List<Expense__c> expenses = [
            SELECT Status__c
            FROM   Expense__c
            WHERE  Expense_Report__c = :reportId
        ];

        Boolean hasSubmitted = false;
        Boolean hasNonDraft  = false;
        for (Expense__c e : expenses) {
            if (e.Status__c == 'Submitted') { hasSubmitted = true; break; }
            if (e.Status__c != 'Draft')       hasNonDraft  = true;
        }

        String newStatus;
        if (hasSubmitted)     newStatus = 'Submitted';
        else if (hasNonDraft) newStatus = 'Completed';
        else                  return; // all Draft — leave as is

        Expense_Report__c report = [SELECT Id, Status__c FROM Expense_Report__c WHERE Id = :reportId LIMIT 1];
        if (report.Status__c != newStatus) {
            String oldStatus = report.Status__c;
            report.Status__c = newStatus;
            update report;
            ExpenseAuditLogger.logReportStatusChanged(reportId, oldStatus, newStatus);
        }
    }
}