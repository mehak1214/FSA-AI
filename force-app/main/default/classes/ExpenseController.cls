/**
 * ExpenseController
 * Apex controller for the Expense Management LWC components.
 *
 * Key design decision:
 *   Expense__c has a Master-Detail relationship to Expense_Report__c.
 *   Sales Reps never create Expense Reports manually.
 *   The system auto-creates (or reuses) exactly ONE Expense_Report__c
 *   per Sales Rep per calendar day, named by the auto-number format.
 *   This is handled inside createExpense() using a find-or-create pattern
 *   with a FOR UPDATE lock to prevent duplicate reports from concurrent saves.
 */
public with sharing class ExpenseController {

    // ─────────────────────────────────────────────
    // INNER WRAPPER – returned to LWC
    // ─────────────────────────────────────────────
    public class ExpenseWrapper {
        @AuraEnabled public String  id;
        @AuraEnabled public String  name;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String  expenseType;
        @AuraEnabled public String  expenseDate;
        @AuraEnabled public String  status;
        @AuraEnabled public String  description;
        @AuraEnabled public String  rejectionReason;
        @AuraEnabled public String  expenseReportId;
        @AuraEnabled public String  expenseReportName;
        @AuraEnabled public String  visitId;
        @AuraEnabled public String  visitName;
    }

    // ─────────────────────────────────────────────
    // GET EXPENSES  (today OR all, with optional type/status filter)
    // ─────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<ExpenseWrapper> getExpenses(
            Boolean todayOnly,
            String  filterType,
            String  filterStatus) {

        String userId = UserInfo.getUserId();

        String query =
            'SELECT Id, Name, Amount__c, Expense_Type__c, Expense_Date__c, ' +
            '       Status__c, Description__c, Rejection_Reason__c, ' +
            '       Expense_Report__c, Expense_Report__r.Name, ' +
            '       Visit__c, Visit__r.Name ' +
            'FROM   Expense__c ' +
            'WHERE  Sales_Rep__c = :userId ';

        if (todayOnly) {
            Date today = Date.today();
            query += 'AND Expense_Date__c = :today ';
        }
        if (String.isNotBlank(filterType) && filterType != 'All') {
            query += 'AND Expense_Type__c = :filterType ';
        }
        if (String.isNotBlank(filterStatus) && filterStatus != 'All') {
            query += 'AND Status__c = :filterStatus ';
        }

        query += 'ORDER BY Expense_Date__c DESC, CreatedDate DESC LIMIT 200';

        List<Expense__c> expenses = Database.query(query);

        List<ExpenseWrapper> result = new List<ExpenseWrapper>();
        for (Expense__c e : expenses) {
            ExpenseWrapper w    = new ExpenseWrapper();
            w.id                = e.Id;
            w.name              = e.Name;
            w.amount            = e.Amount__c;
            w.expenseType       = e.Expense_Type__c;
            w.expenseDate       = e.Expense_Date__c != null
                                     ? String.valueOf(e.Expense_Date__c) : null;
            w.status            = e.Status__c;
            w.description       = e.Description__c;
            w.rejectionReason   = e.Rejection_Reason__c;
            w.expenseReportId   = e.Expense_Report__c;
            w.expenseReportName = e.Expense_Report__r != null
                                     ? e.Expense_Report__r.Name : null;
            w.visitId           = e.Visit__c;
            w.visitName         = e.Visit__r != null ? e.Visit__r.Name : null;
            result.add(w);
        }
        return result;
    }

    // ─────────────────────────────────────────────
    // GET TODAY'S SUMMARY (total + count + report status)
    // ─────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getTodaySummary() {
        String userId = UserInfo.getUserId();
        Date   today  = Date.today();

        AggregateResult[] agg = [
            SELECT COUNT(Id) cnt, SUM(Amount__c) total
            FROM   Expense__c
            WHERE  Sales_Rep__c    = :userId
            AND    Expense_Date__c = :today
        ];

        Map<String, Object> summary = new Map<String, Object>();
        summary.put('count', (Integer) agg[0].get('cnt'));
        summary.put('total', (Decimal) agg[0].get('total'));

        // Also return today's report status so the UI knows whether
        // to show Submit / already submitted / no report yet
        List<Expense_Report__c> reports = [
            SELECT Id, Status__c
            FROM   Expense_Report__c
            WHERE  Sales_Rep__c   = :userId
            AND    Report_Date__c = :today
            LIMIT  1
        ];
        if (!reports.isEmpty()) {
            summary.put('reportId',     reports[0].Id);
            summary.put('reportStatus', reports[0].Status__c);
        } else {
            summary.put('reportId',     null);
            summary.put('reportStatus', null);
        }

        return summary;
    }

    // ─────────────────────────────────────────────
    // SUBMIT TODAY'S EXPENSE REPORT
    // Submits the Expense_Report__c for today through
    // the Approval Process and updates all Draft child
    // Expense__c records to Submitted status.
    // ─────────────────────────────────────────────
    @AuraEnabled
    public static void submitTodayReport() {
        String userId = UserInfo.getUserId();
        checkManagerAssigned(userId);
        Date   today  = Date.today();

        List<Expense_Report__c> reports = [
            SELECT Id, Status__c
            FROM   Expense_Report__c
            WHERE  Sales_Rep__c   = :userId
            AND    Report_Date__c = :today
            LIMIT  1
        ];

        if (reports.isEmpty()) {
            throw new AuraHandledException('No expense report found for today.');
        }

        Expense_Report__c report = reports[0];

        if (report.Status__c != 'Draft') {
            throw new AuraHandledException(
                'This report has already been submitted (status: ' + report.Status__c + ').'
            );
        }

        // Step 1: Update all Draft child expenses to Submitted
        List<Expense__c> draftExpenses = [
            SELECT Id
            FROM   Expense__c
            WHERE  Expense_Report__c = :report.Id
            AND    Status__c         = 'Draft'
        ];
        if (!draftExpenses.isEmpty()) {
            for (Expense__c e : draftExpenses) {
                e.Status__c = 'Submitted';
            }
            update draftExpenses;
        }

        // Step 2: Set the report status to Submitted directly (no Approval Process)
        report.Status__c = 'Submitted';
        update report;
        ExpenseAuditLogger.logReportSubmitted(report.Id, draftExpenses.size());
    }

    // ─────────────────────────────────────────────
    // FIND OR CREATE EXPENSE REPORT FOR A GIVEN DATE
    //
    // Rules:
    //  - Exactly one Expense_Report__c per (Sales_Rep__c, Report_Date__c)
    //  - Status defaults to 'Draft'
    //  - Uses FOR UPDATE to prevent race-condition duplicates when a rep
    //    saves two expenses at the same moment (e.g. double-tap)
    // ─────────────────────────────────────────────
    private static Id getOrCreateExpenseReport(String userId, Date reportDate) {

        // Lock any existing report for this rep+date
        List<Expense_Report__c> existing = [
            SELECT Id
            FROM   Expense_Report__c
            WHERE  Sales_Rep__c   = :userId
            AND    Report_Date__c = :reportDate
            LIMIT  1
            FOR UPDATE
        ];

        if (!existing.isEmpty()) {
            return existing[0].Id;
        }

        // None found – create one (Name is auto-number EXP_RPT-{00000})
        Expense_Report__c report = new Expense_Report__c();
        report.Sales_Rep__c   = userId;
        report.Report_Date__c = reportDate;
        report.Status__c      = 'Draft';
        insert report;
        return report.Id;
    }

    // ─────────────────────────────────────────────
    // GET VISITS FOR A GIVEN DATE (for current user)
    // ─────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getVisitsForDate(String expenseDate) {
        if (String.isBlank(expenseDate)) return new List<Map<String, String>>();

        String userId     = UserInfo.getUserId();
        Date   parsedDate = Date.valueOf(expenseDate);

        List<Visit__c> visits = [
            SELECT Id, Name, Outlet1__c, Outlet1__r.Name
            FROM   Visit__c
            WHERE  Visit_Date__c   = :parsedDate
            AND    Sales_Rep__c    = :userId
            AND    Visit_Status__c = 'Completed'
            ORDER BY Name ASC
        ];

        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Visit__c v : visits) {
            Map<String, String> row = new Map<String, String>();
            row.put('id',         v.Id);
            row.put('name',       v.Name);
            row.put('outletName', v.Outlet1__r != null ? v.Outlet1__r.Name : '');
            result.add(row);
        }
        return result;
    }

    // ─────────────────────────────────────────────
    // SAVE RESULT WRAPPER
    // Returned by createExpense and updateExpense so the LWC
    // can receive both the new record Id and any policy warning.
    // ─────────────────────────────────────────────
    public class SaveResult {
        @AuraEnabled public String  expenseId;
        @AuraEnabled public Boolean hasPolicyWarning = false;
        @AuraEnabled public String  warningMessage;
    }

    // ─────────────────────────────────────────────
    // CREATE EXPENSE
    // amount, expenseType, expenseDate, description + optional visitIds.
    // Expense Report resolved automatically.
    // Expense_Visit_Link__c junction records auto-created for each visitId.
    // ─────────────────────────────────────────────
    @AuraEnabled
    public static SaveResult createExpense(
            Decimal      amount,
            String       expenseType,
            String       expenseDate,
            String       description,
            List<String> visitIds) {

        String userId     = UserInfo.getUserId();
        Date   parsedDate = Date.valueOf(expenseDate);

        // Policy check — may throw (hard block) or return a warning
        ExpensePolicyService.PolicyCheckResult check =
            ExpensePolicyService.evaluate(userId, expenseType, amount, expenseDate, null);

        Id reportId = getOrCreateExpenseReport(userId, parsedDate);

        Expense__c exp        = new Expense__c();
        exp.Amount__c         = amount;
        exp.Expense_Type__c   = expenseType;
        exp.Expense_Date__c   = parsedDate;
        exp.Description__c    = description;
        exp.Sales_Rep__c      = userId;
        exp.Status__c         = 'Draft';
        exp.Expense_Report__c = reportId;

        // Stamp breach snapshot fields if policy was breached
        if (check.hasBreach) {
            exp.Policy_Breach__c          = true;
            exp.Policy_Breach_Type__c     = check.breachType;
            exp.Policy_Cap_At_Time__c     = check.capAtTime;
            exp.Policy_Breach_Amount__c   = check.breachAmount;
            exp.Allowance_At_Time__c      = check.allowanceAtTime;
            exp.Allowance_Used_At_Time__c = check.allowanceUsedAtTime;
        }

        insert exp;

        if (visitIds != null && !visitIds.isEmpty()) {
            List<Expense_Visit_Link__c> links = new List<Expense_Visit_Link__c>();
            for (String vid : visitIds) {
                if (String.isNotBlank(vid)) {
                    links.add(new Expense_Visit_Link__c(
                        Expense__c = exp.Id,
                        Visit__c   = vid
                    ));
                }
            }
            if (!links.isEmpty()) insert links;
        }

        SaveResult res        = new SaveResult();
        res.expenseId         = exp.Id;
        res.hasPolicyWarning  = check.hasBreach;
        res.warningMessage    = check.warningMessage;
        return res;
    }

    // ─────────────────────────────────────────────
    // ATTACH FILES TO EXPENSE
    // Called after createExpense returns the new expenseId.
    // Each file is a Map with keys: fileName, base64Data, mimeType
    // ─────────────────────────────────────────────
    @AuraEnabled
    public static void attachFilesToExpense(String expenseId, List<Map<String, String>> files) {
        if (String.isBlank(expenseId) || files == null || files.isEmpty()) return;

        List<ContentVersion> versions = new List<ContentVersion>();
        for (Map<String, String> f : files) {
            ContentVersion cv = new ContentVersion();
            cv.Title           = f.get('fileName');
            cv.PathOnClient    = f.get('fileName');
            cv.VersionData     = EncodingUtil.base64Decode(f.get('base64Data'));
            cv.IsMajorVersion  = true;
            versions.add(cv);
        }
        insert versions;

        // Re-query to get auto-generated ContentDocumentId
        List<ContentVersion> inserted = [
            SELECT Id, ContentDocumentId
            FROM   ContentVersion
            WHERE  Id IN :versions
        ];

        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (ContentVersion cv : inserted) {
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = cv.ContentDocumentId;
            cdl.LinkedEntityId    = expenseId;
            cdl.ShareType         = 'V';   // Viewer permission
            cdl.Visibility        = 'AllUsers';
            links.add(cdl);
        }
        insert links;
    }


    // ─────────────────────────────────────────────
    // GET LINKED VISITS (with names) FOR AN EXPENSE
    // Used by the view modal to display visit names.
    // ─────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getLinkedVisits(String expenseId) {
        if (String.isBlank(expenseId)) return new List<Map<String, String>>();
        List<Expense_Visit_Link__c> links = [
            SELECT Visit__c, Visit__r.Name, Visit__r.Outlet1__r.Name
            FROM   Expense_Visit_Link__c
            WHERE  Expense__c = :expenseId
        ];
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Expense_Visit_Link__c lnk : links) {
            Map<String, String> row = new Map<String, String>();
            row.put('id',         lnk.Visit__c);
            row.put('name',       lnk.Visit__r.Name);
            row.put('outletName', lnk.Visit__r.Outlet1__r != null
                                    ? lnk.Visit__r.Outlet1__r.Name : '');
            result.add(row);
        }
        return result;
    }

    // ─────────────────────────────────────────────
    // GET LINKED VISIT IDs FOR AN EXPENSE
    // Used by the edit modal to pre-select already-linked visits.
    // ─────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<String> getLinkedVisitIds(String expenseId) {
        if (String.isBlank(expenseId)) return new List<String>();
        List<Expense_Visit_Link__c> links = [
            SELECT Visit__c
            FROM   Expense_Visit_Link__c
            WHERE  Expense__c = :expenseId
        ];
        List<String> ids = new List<String>();
        for (Expense_Visit_Link__c lnk : links) {
            ids.add(lnk.Visit__c);
        }
        return ids;
    }

    // ─────────────────────────────────────────────
    // GET FILES FOR EXPENSE
    // Returns existing ContentDocument attachments so the
    // edit modal can display what's already uploaded.
    // ─────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getFilesForExpense(String expenseId) {
        if (String.isBlank(expenseId)) return new List<Map<String, String>>();

        List<ContentDocumentLink> links = [
            SELECT ContentDocument.Id,
                   ContentDocument.Title,
                   ContentDocument.FileExtension,
                   ContentDocument.ContentSize,
                   ContentDocument.FileType,
                   ContentDocument.LatestPublishedVersionId
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId = :expenseId
            ORDER BY ContentDocument.CreatedDate ASC
        ];

        List<Map<String, String>> result = new List<Map<String, String>>();
        for (ContentDocumentLink cdl : links) {
            Map<String, String> row = new Map<String, String>();
            row.put('documentId', cdl.ContentDocument.Id);
            row.put('versionId',  cdl.ContentDocument.LatestPublishedVersionId);
            row.put('title',      cdl.ContentDocument.Title);
            row.put('extension',  cdl.ContentDocument.FileExtension != null
                                    ? cdl.ContentDocument.FileExtension.toLowerCase() : '');
            row.put('fileType',   cdl.ContentDocument.FileType != null
                                    ? cdl.ContentDocument.FileType.toLowerCase() : '');
            row.put('size',       cdl.ContentDocument.ContentSize != null
                                    ? String.valueOf(cdl.ContentDocument.ContentSize) : '0');
            result.add(row);
        }
        return result;
    }

    // ─────────────────────────────────────────────
    // REMOVE FILE FROM EXPENSE
    // Deletes the ContentDocumentLink (and its ContentDocument)
    // so the file is detached and removed from Salesforce Files.
    // ─────────────────────────────────────────────
    @AuraEnabled
    public static void removeFileFromExpense(String documentId) {
        if (String.isBlank(documentId)) return;
        List<ContentDocument> docs = [
            SELECT Id FROM ContentDocument WHERE Id = :documentId LIMIT 1
        ];
        if (!docs.isEmpty()) delete docs;
    }

    @AuraEnabled
    public static void deleteExpense(String expenseId) {
        Expense__c exp = [
            SELECT Id, Status__c
            FROM   Expense__c
            WHERE  Id = :expenseId
            LIMIT  1
        ];
        if (exp.Status__c != 'Draft') {
            throw new AuraHandledException('Only Draft expenses can be deleted.');
        }
        delete exp;
    }

    // ─────────────────────────────────────────────
    // SUBMIT INDIVIDUAL EXPENSE (Draft → Submitted)
    // Also syncs the parent Expense Report status:
    //   - Any Submitted expense present  → Report = 'Submitted'
    //   - No Submitted expenses remain   → Report = 'Completed'
    //   - Only Draft expenses (initial)  → Report stays 'Draft'
    // ─────────────────────────────────────────────
    @AuraEnabled
    public static void submitExpense(String expenseId) {
        checkManagerAssigned(UserInfo.getUserId());
        Expense__c exp = [
            SELECT Id, Status__c, Expense_Report__c
            FROM   Expense__c
            WHERE  Id = :expenseId
            LIMIT  1
        ];
        if (exp.Status__c != 'Draft') {
            throw new AuraHandledException('Only Draft expenses can be submitted.');
        }
        exp.Status__c = 'Submitted';
        update exp;
        ExpenseAuditLogger.logExpenseSubmitted(exp.Id, exp.Expense_Report__c);
        syncReportStatus(exp.Expense_Report__c);
    }

    // ─────────────────────────────────────────────
    // RESUBMIT EXPENSE (Rejected → Draft)
    // Clears the rejection reason so the rep can edit and re-submit.
    // Policy check runs on re-submit (not here) when rep clicks Submit.
    // ─────────────────────────────────────────────
    @AuraEnabled
    public static void resubmitExpense(String expenseId) {
        Expense__c exp = [
            SELECT Id, Status__c, Expense_Report__c, Rejection_Reason__c
            FROM   Expense__c
            WHERE  Id = :expenseId
            AND    Sales_Rep__c = :UserInfo.getUserId()
            LIMIT  1
        ];
        if (exp.Status__c != 'Rejected') {
            throw new AuraHandledException('Only Rejected expenses can be resubmitted.');
        }
        exp.Status__c          = 'Draft';
        exp.Rejection_Reason__c = null;   // clear rejection so edit modal is clean
        update exp;
        ExpenseAuditLogger.logResubmit(exp.Id, exp.Expense_Report__c);
        syncReportStatus(exp.Expense_Report__c);
    }

    // ─────────────────────────────────────────────
    // ABANDON EXPENSE (Rejected → Abandoned)
    // Marks the expense as Abandoned — preserves record for audit trail.
    // The expense is excluded from future approval queues.
    // ─────────────────────────────────────────────
    @AuraEnabled
    public static void abandonExpense(String expenseId) {
        Expense__c exp = [
            SELECT Id, Status__c, Expense_Report__c
            FROM   Expense__c
            WHERE  Id = :expenseId
            AND    Sales_Rep__c = :UserInfo.getUserId()
            LIMIT  1
        ];
        if (exp.Status__c != 'Rejected') {
            throw new AuraHandledException('Only Rejected expenses can be abandoned.');
        }
        exp.Status__c = 'Abandoned';
        update exp;
        ExpenseAuditLogger.logAbandon(exp.Id, exp.Expense_Report__c);
        syncReportStatus(exp.Expense_Report__c);
    }

    // ─────────────────────────────────────────────
    // GUARD: ensure the current user has a manager assigned
    // Called before any submission to prevent orphaned reports
    // ─────────────────────────────────────────────
    private static void checkManagerAssigned(String userId) {
        User u = [SELECT ManagerId FROM User WHERE Id = :userId LIMIT 1];
        if (u.ManagerId == null) {
            throw new AuraHandledException(
                'Your manager is not configured. Please contact HR/Admin.'
            );
        }
    }

    // ─────────────────────────────────────────────
    // SYNC REPORT STATUS based on child expense statuses
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
            if (e.Status__c == 'Submitted') {
                hasSubmitted = true;
                break;
            }
            if (e.Status__c != 'Draft') {
                hasNonDraft = true;
            }
        }

        String newStatus;
        if (hasSubmitted) {
            newStatus = 'Submitted';
        } else if (hasNonDraft) {
            // All non-Draft expenses are Approved/Rejected/Paid — no Submitted remaining
            newStatus = 'Completed';
        } else {
            // All expenses are Draft — leave report as Draft
            return;
        }

        Expense_Report__c report = [
            SELECT Id, Status__c
            FROM   Expense_Report__c
            WHERE  Id = :reportId
            LIMIT  1
        ];
        if (report.Status__c != newStatus) {
            String oldStatus = report.Status__c;
            report.Status__c = newStatus;
            update report;
            ExpenseAuditLogger.logReportStatusChanged(reportId, oldStatus, newStatus);
        }
    }

    // ─────────────────────────────────────────────
    // UPDATE EXPENSE (Draft only)
    // Updates fields and re-links visits via Expense_Visit_Link__c.
    // Existing links are deleted and replaced with the new selection.
    // ─────────────────────────────────────────────
    @AuraEnabled
    public static SaveResult updateExpense(
            String       expenseId,
            Decimal      amount,
            String       expenseType,
            String       expenseDate,
            String       description,
            List<String> visitIds) {

        String userId  = UserInfo.getUserId();
        Date   newDate = Date.valueOf(expenseDate);

        Expense__c exp = [
            SELECT Id, Status__c, Expense_Date__c, Expense_Report__c
            FROM   Expense__c
            WHERE  Id = :expenseId
            LIMIT  1
        ];
        if (exp.Status__c != 'Draft') {
            throw new AuraHandledException('Only Draft expenses can be edited.');
        }

        // Capture original values BEFORE overwriting them on the sObject
        Date originalDate = exp.Expense_Date__c;
        Id   oldReportId  = exp.Expense_Report__c;

        // Policy check — may throw (hard block) or return a warning
        ExpensePolicyService.PolicyCheckResult check =
            ExpensePolicyService.evaluate(userId, expenseType, amount, expenseDate, expenseId);

        exp.Amount__c       = amount;
        exp.Expense_Type__c = expenseType;
        exp.Expense_Date__c = newDate;
        exp.Description__c  = description;

        // ── Re-assign Expense Report when the date has changed ──────────────
        // There is exactly one Expense_Report__c per (Sales_Rep, date).
        // If the user changed the expense date we must move this expense to
        // the report that matches the new date (creating that report first
        // if it doesn't exist yet).  The old report is left as-is; its
        // status is re-synced below so it reflects the remaining expenses.
        if (originalDate != newDate || oldReportId == null) {
            Id newReportId = getOrCreateExpenseReport(userId, newDate);
            if (newReportId != oldReportId) {
                exp.Expense_Report__c = newReportId;
            }
        }

        // Reset then re-stamp breach fields
        exp.Policy_Breach__c          = check.hasBreach;
        exp.Policy_Breach_Type__c     = check.breachType;
        exp.Policy_Cap_At_Time__c     = check.capAtTime;
        exp.Policy_Breach_Amount__c   = check.breachAmount;
        exp.Allowance_At_Time__c      = check.allowanceAtTime;
        exp.Allowance_Used_At_Time__c = check.allowanceUsedAtTime;

        update exp;

        // Sync old report status — it may now have fewer/no Draft expenses
        if (oldReportId != null && oldReportId != exp.Expense_Report__c) {
            syncReportStatus(oldReportId);
        }

        // Replace all visit links
        List<Expense_Visit_Link__c> existing = [
            SELECT Id FROM Expense_Visit_Link__c WHERE Expense__c = :expenseId
        ];
        if (!existing.isEmpty()) delete existing;

        if (visitIds != null && !visitIds.isEmpty()) {
            List<Expense_Visit_Link__c> newLinks = new List<Expense_Visit_Link__c>();
            for (String vid : visitIds) {
                if (String.isNotBlank(vid)) {
                    newLinks.add(new Expense_Visit_Link__c(
                        Expense__c = expenseId,
                        Visit__c   = vid
                    ));
                }
            }
            if (!newLinks.isEmpty()) insert newLinks;
        }

        SaveResult res        = new SaveResult();
        res.expenseId         = expenseId;
        res.hasPolicyWarning  = check.hasBreach;
        res.warningMessage    = check.warningMessage;
        return res;
    }
}