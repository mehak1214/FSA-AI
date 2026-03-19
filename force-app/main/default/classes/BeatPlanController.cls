public with sharing class BeatPlanController {

    // ─────────────────────────────────────────────────────────────────────────
    // INNER CLASSES
    // ─────────────────────────────────────────────────────────────────────────

    /** One visit card on the weekly calendar grid */
    public class VisitWrapper {
        @AuraEnabled public String  id                 { get; set; }
        @AuraEnabled public String  name               { get; set; }
        @AuraEnabled public String  beatId             { get; set; }  // Beat__c
        @AuraEnabled public String  beatName           { get; set; }  // Beat__r.Name
        @AuraEnabled public String  outletId           { get; set; }  // Outlet1__c
        @AuraEnabled public String  outletName         { get; set; }  // Outlet1__r.Name
        @AuraEnabled public String  outletPriority     { get; set; }  // Outlet1__r.Outlet_Priority__c
        @AuraEnabled public String  visitStatus        { get; set; }  // Visit_Status__c
        @AuraEnabled public String  approvalStatus     { get; set; }  // Approval_Status__c
        @AuraEnabled public Boolean isCompleted        { get; set; }  // Is_Completed__c
        @AuraEnabled public String  missedReason       { get; set; }  // Missed_Reason__c
        @AuraEnabled public String  missedRemarks      { get; set; }  // Missed_Remarks__c
        @AuraEnabled public Date    visitDate          { get; set; }  // Visit_Date__c
        @AuraEnabled public String  plannedStartTime   { get; set; }  // formatted Planned_Start_Time__c
        @AuraEnabled public String  plannedEndTime     { get; set; }  // formatted Planned_End_Time__c
        @AuraEnabled public String  checkInTime        { get; set; }  // formatted Check_In_Time__c
        @AuraEnabled public String  checkOutTime       { get; set; }  // formatted Check_Out_Time__c
        @AuraEnabled public Integer sequence           { get; set; }  // Sequence__c
        @AuraEnabled public String  dayOfWeek          { get; set; }  // derived: MON-SUN
        @AuraEnabled public String  colorClass         { get; set; }  // derived from visitStatus
        @AuraEnabled public String  startTime          { get; set; }  // HH:mm from UI draft form
        @AuraEnabled public String  endTime            { get; set; }  // HH:mm from UI draft form
        @AuraEnabled public String  notes              { get; set; }  // maps to Missed_Remarks__c
    }

    /** Header stats shown in the banner bar */
    public class WeekStats {
        @AuraEnabled public Integer totalVisits    { get; set; }
        @AuraEnabled public Integer completed      { get; set; }
        @AuraEnabled public Integer pending        { get; set; }
        @AuraEnabled public Integer missed         { get; set; }
        @AuraEnabled public String  weekLabel      { get; set; }
        @AuraEnabled public String  beatId         { get; set; }
        @AuraEnabled public String  beatName       { get; set; }
        @AuraEnabled public String  beatStatus     { get; set; }  // Status__c on Beat
        @AuraEnabled public Date    beatStartDate  { get; set; }
        @AuraEnabled public Date    beatEndDate    { get; set; }
    }

    /** Root object returned by getWeeklyVisits — consumed by LWC */
    public class WeekData {
        @AuraEnabled public WeekStats          stats  { get; set; }
        @AuraEnabled public List<VisitWrapper> visits { get; set; }
    }

    public class BeatOption {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String status { get; set; }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PUBLIC METHODS
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * getWeeklyVisits
     * Loads all Visit__c records for the week containing anchorDate.
     *
     * Flow:
     *   1. Find Beat__c where the rep is assigned and week overlaps.
     *   2. Query Visit__c children of that Beat for the date range,
     *      crossing to Outlet1__r (Account) for outlet details.
     *   3. Return WeekData (stats + visit list).
     *
     * @param anchorDate  Any date within the target week. Null = today.
     */
        @AuraEnabled(cacheable=false)
    public static WeekData getWeeklyVisits(Date anchorDate) {
        Date weekStart = mondayOf(anchorDate != null ? anchorDate : Date.today());
        Date weekEnd   = weekStart.addDays(6);

        // Step 1: Find beats for this rep that overlap the requested week.
        List<Beat__c> beats = [
            SELECT  Id,
                    Name,
                    Status__c,
                    Active__c,
                    Start_Date__c,
                    End_Date__c,
                    Sales_Rep__c
            FROM    Beat__c
            WHERE   Sales_Rep__c = :UserInfo.getUserId()
            AND     Start_Date__c <= :weekEnd
            AND     End_Date__c   >= :weekStart
            ORDER BY Active__c DESC, Start_Date__c DESC
            LIMIT   50
        ];

        // Step 2: Query this rep's visits for the week by Visit Date.
        // This keeps submitted/draft/approved records visible after component reload.
        List<Visit__c> records = [
            SELECT  Id,
                    Name,
                    Beat__c,
                    Beat__r.Name,
                    Beat__r.Status__c,
                    Beat__r.Start_Date__c,
                    Beat__r.End_Date__c,
                    Outlet1__c,
                    Outlet1__r.Name,
                    Outlet1__r.Outlet_Priority__c,
                    Sales_Rep__c,
                    Visit_Date__c,
                    Planned_Start_Time__c,
                    Planned_End_Time__c,
                    Check_In_Time__c,
                    Check_Out_Time__c,
                    Visit_Status__c,
                    Approval_Status__c,
                    Is_Completed__c,
                    Missed_Reason__c,
                    Missed_Remarks__c,
                    Sequence__c
            FROM    Visit__c
            WHERE   Visit_Date__c >= :weekStart
            AND     Visit_Date__c <= :weekEnd
            AND     (
                        Sales_Rep__c = :UserInfo.getUserId()
                        OR Beat__r.Sales_Rep__c = :UserInfo.getUserId()
                    )
            ORDER BY Visit_Date__c ASC,
                     Sequence__c   ASC NULLS LAST,
                     Planned_Start_Time__c ASC NULLS LAST
            LIMIT   200
        ];

        // Step 3: Build stats
        WeekStats stats     = new WeekStats();
        stats.totalVisits   = records.size();
        stats.completed     = 0;
        stats.pending       = 0;
        stats.missed        = 0;
        stats.weekLabel     = weekRangeLabel(weekStart, weekEnd);
        stats.beatId        = beats.isEmpty() ? null  : beats[0].Id;
        stats.beatName      = beats.isEmpty() ? null  : beats[0].Name;
        stats.beatStatus    = beats.isEmpty() ? null  : beats[0].Status__c;
        stats.beatStartDate = beats.isEmpty() ? null  : beats[0].Start_Date__c;
        stats.beatEndDate   = beats.isEmpty() ? null  : beats[0].End_Date__c;

        if (beats.isEmpty() && !records.isEmpty() && records[0].Beat__r != null) {
            stats.beatId        = records[0].Beat__c;
            stats.beatName      = records[0].Beat__r.Name;
            stats.beatStatus    = records[0].Beat__r.Status__c;
            stats.beatStartDate = records[0].Beat__r.Start_Date__c;
            stats.beatEndDate   = records[0].Beat__r.End_Date__c;
        }

        // Step 4: Map records -> VisitWrappers
        List<VisitWrapper> visits = new List<VisitWrapper>();

        for (Visit__c r : records) {
            VisitWrapper v      = new VisitWrapper();
            v.id                = r.Id;
            v.name              = r.Name;
            v.beatId            = r.Beat__c;
            v.beatName          = r.Beat__r != null ? r.Beat__r.Name : null;
            v.outletId          = r.Outlet1__c;
            v.outletName        = r.Outlet1__r != null ? r.Outlet1__r.Name : '-';
            v.outletPriority    = r.Outlet1__r != null ? r.Outlet1__r.Outlet_Priority__c : null;
            v.visitStatus       = r.Visit_Status__c;
            v.approvalStatus    = r.Approval_Status__c;
            v.isCompleted       = r.Is_Completed__c;
            v.missedReason      = r.Missed_Reason__c;
            v.missedRemarks     = r.Missed_Remarks__c;
            v.visitDate         = r.Visit_Date__c;
            v.plannedStartTime  = fmtDateTime(r.Planned_Start_Time__c);
            v.plannedEndTime    = fmtDateTime(r.Planned_End_Time__c);
            v.checkInTime       = fmtDateTime(r.Check_In_Time__c);
            v.checkOutTime      = fmtDateTime(r.Check_Out_Time__c);
            v.sequence          = r.Sequence__c != null ? Integer.valueOf(r.Sequence__c) : null;
            v.dayOfWeek         = dayLabel(r.Visit_Date__c);
            v.colorClass        = statusToColor(r.Visit_Status__c, r.Is_Completed__c, r.Approval_Status__c);

            String s = r.Visit_Status__c;
            if      (r.Is_Completed__c == true) stats.completed++;
            else if (s == 'Missed')                    stats.missed++;
            else                                       stats.pending++;

            visits.add(v);
        }

        WeekData data  = new WeekData();
        data.stats     = stats;
        data.visits    = visits;
        return data;
    }

    /**
     * submitBeatPlan
     * Transitions Beat__c.Status__c → 'Submitted'
     * and bulk-updates Planned visits for the selected week to 'Pending Approval'.
     *
     * @param beatId      Id of Beat__c to submit.
     * @param anchorDate  Any date in the week being submitted. Null = today.
     */
    @AuraEnabled
    public static String submitBeatPlanForWeek(String beatId, Date anchorDate) {
        if (String.isBlank(beatId)) {
            throw new AuraHandledException('Beat ID is required to submit.');
        }

        Date weekStart = mondayOf(anchorDate != null ? anchorDate : Date.today());
        Date weekEnd   = weekStart.addDays(6);

        Beat__c beat = [
            SELECT  Id, Status__c, Sales_Rep__c
            FROM    Beat__c
            WHERE   Id      = :beatId
            AND     Sales_Rep__c = :UserInfo.getUserId()
            LIMIT   1
        ];

        beat.Status__c = 'Submitted';
        update beat;

        // Bulk-update only this week's visits under this Beat that are still Planned
        List<Visit__c> toUpdate = [
            SELECT  Id, Approval_Status__c
            FROM    Visit__c
            WHERE   Beat__c            = :beatId
            AND     Visit_Date__c      >= :weekStart
            AND     Visit_Date__c      <= :weekEnd
            AND     Approval_Status__c = 'Planned'
        ];

        for (Visit__c v : toUpdate) {
            v.Approval_Status__c = 'Pending Approval';
        }

        if (!toUpdate.isEmpty()) update toUpdate;

        return 'SUCCESS';
    }

    @AuraEnabled
    public static String submitBeatPlan(String beatId) {
        return submitBeatPlanForWeek(beatId, Date.today());
    }

    /**
     * saveVisit
     * Upserts a single Visit__c.
     * Requires beatId (Beat__c) AND outletId (Outlet1__c).
     * Beat is NOT linked to Account directly — both lookups live on the Visit.
     *
     * @param visitJson  JSON of VisitWrapper.
     */
    @AuraEnabled
    public static String saveVisit(String visitJson) {
        VisitWrapper v = (VisitWrapper) JSON.deserialize(visitJson, VisitWrapper.class);
        if (v.visitDate != null && v.visitDate < Date.today()) {
            throw new AuraHandledException('Visit can only be created for today or future dates.');
        }

        Visit__c record = new Visit__c();

        if (String.isNotBlank(v.id)) {
            record.Id = v.id;
        }

        // Both lookups are on the Visit record
        record.Beat__c    = v.beatId;      // parent Beat
        record.Outlet1__c = v.outletId;    // Account (outlet)
        record.Sales_Rep__c = UserInfo.getUserId();

        if (v.visitDate    != null) record.Visit_Date__c    = v.visitDate;
        if (v.sequence     != null) record.Sequence__c      = v.sequence;
        if (v.visitDate != null && String.isNotBlank(v.startTime)) {
            record.Planned_Start_Time__c = parseDateTime(v.visitDate, v.startTime);
        }
        if (v.visitDate != null && String.isNotBlank(v.endTime)) {
            record.Planned_End_Time__c = parseDateTime(v.visitDate, v.endTime);
        }
        if (String.isNotBlank(v.notes)) {
            record.Missed_Remarks__c = v.notes;
        }

        record.Visit_Status__c     = String.isBlank(v.visitStatus) ? 'Planned' : v.visitStatus;
        record.Approval_Status__c  = String.isBlank(v.approvalStatus) ? 'Planned' : v.approvalStatus;

        upsert record;
        return record.Id;
    }

    /**
     * Creates all drafted visits and submits each to Visit_Approval_Process.
     * Entire transaction fails if any record fails validation or approval submission.
     */
    @AuraEnabled
    public static String createVisitsAndSubmitForApproval(List<String> draftVisitJsonList) {
        try {
            if (draftVisitJsonList == null || draftVisitJsonList.isEmpty()) {
                throw new AuraHandledException('No visits to submit.');
            }

            List<Visit__c> toInsert = new List<Visit__c>();

            for (String visitJson : draftVisitJsonList) {
                VisitWrapper v = (VisitWrapper) JSON.deserialize(visitJson, VisitWrapper.class);
                if (String.isBlank(v.beatId) || String.isBlank(v.outletId) || v.visitDate == null) {
                    throw new AuraHandledException('Beat, Outlet and Visit Date are required for all visits.');
                }
                if (v.visitDate < Date.today()) {
                    throw new AuraHandledException('Visit can only be created for today or future dates.');
                }
                if (String.isBlank(v.startTime) || String.isBlank(v.endTime)) {
                    throw new AuraHandledException('Start Time and End Time are required for all visits.');
                }

                Visit__c rec = new Visit__c();
                rec.Beat__c = v.beatId;
                rec.Outlet1__c = v.outletId;
                rec.Sales_Rep__c = UserInfo.getUserId();
                rec.OwnerId = UserInfo.getUserId();
                rec.Visit_Date__c = v.visitDate;
                rec.Planned_Start_Time__c = parseDateTime(v.visitDate, v.startTime);
                rec.Planned_End_Time__c = parseDateTime(v.visitDate, v.endTime);
                rec.Visit_Status__c = 'Draft';
                // Must match Visit_Approval_Process entry criteria.
                rec.Approval_Status__c = 'Draft';
                rec.Missed_Remarks__c = v.notes;
                if (v.sequence != null) rec.Sequence__c = v.sequence;
                toInsert.add(rec);
            }

            insert toInsert;

            String processDefinitionId = resolveVisitApprovalProcessId();
            if (String.isBlank(processDefinitionId)) {
                throw new AuraHandledException(
                    'No active Visit approval process found. Configure and activate a Visit approval process in this org.'
                );
            }

            // Helpful for debugging "No applicable approval process" errors when approver resolution fails.
            User submitter = [
                SELECT Id, ManagerId
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            for (Visit__c rec : toInsert) {
                try {
                    Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
                    req.setObjectId(rec.Id);
                    //req.setProcessDefinitionNameOrId(processDefinitionId);
                    req.setSkipEntryCriteria(false);
                    Approval.ProcessResult result = Approval.process(req);
                    if (result == null || !result.isSuccess()) {
                        throw new AuraHandledException('Visit approval submission failed for record ' + rec.Id + '.');
                    }
                } catch (DmlException submitEx) {
                    String statusCode = String.valueOf(submitEx.getDmlStatusCode(0));
                    String dmlMessage = submitEx.getDmlMessage(0);
                    String stackTrace = submitEx.getStackTraceString();
                    // Common failure: entry criteria not met OR approver can't be resolved from user hierarchy.
                    if (statusCode == 'NO_APPLICABLE_PROCESS') {
                        String detailMsg = 'Approval submit failed: No applicable approval process was found.';
                        detailMsg += ' Verify approval process "Visit_Approval_Process" is Active, entry criteria matches'
                                  + ' (Approval_Status__c=Draft AND Visit_Status__c=Draft), and the submitter has a Manager set.';
                        detailMsg += ' Submitter ManagerId=' + String.valueOf(submitter.ManagerId) + '.';
                        detailMsg += ' Visit Id=' + rec.Id + ', Approval_Status__c=' + rec.Approval_Status__c
                                  + ', Visit_Status__c=' + rec.Visit_Status__c + '.';
                        detailMsg += ' StatusCode=' + statusCode + ', DmlMessage=' + dmlMessage + '.';
                        if (String.isNotBlank(stackTrace)) {
                            detailMsg += ' StackTrace=' + stackTrace + '.';
                        }
                        throw new AuraHandledException(detailMsg);
                    }
                    String genericMsg = 'Visit approval submission failed: ' + dmlMessage
                                      + '. StatusCode=' + statusCode + '.';
                    if (String.isNotBlank(stackTrace)) {
                        genericMsg += ' StackTrace=' + stackTrace + '.';
                    }
                    throw new AuraHandledException(genericMsg);
                }
            }

            return 'SUCCESS';
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (DmlException dmlEx) {
            throw new AuraHandledException('Visit creation failed: ' + dmlEx.getDmlMessage(0));
        } catch (Exception ex) {
            throw new AuraHandledException('Visit submit failed: ' + ex.getMessage());
        }
    }

    /**
     * Resubmits a rejected Visit for approval by resetting statuses to Draft.
     */
    @AuraEnabled
    public static String resubmitRejectedVisit(String visitId) {
        if (String.isBlank(visitId)) {
            throw new AuraHandledException('Visit Id is required.');
        }

        Visit__c rec = [
            SELECT Id, Approval_Status__c, Visit_Status__c, Sales_Rep__c, OwnerId
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

        if (rec.Approval_Status__c != 'Rejected') {
            throw new AuraHandledException('Only Rejected visits can be resubmitted.');
        }

        rec.Approval_Status__c = 'Draft';
        rec.Visit_Status__c = 'Draft';
        if (rec.OwnerId == null || rec.OwnerId != UserInfo.getUserId()) {
            rec.OwnerId = UserInfo.getUserId();
        }
        if (rec.Sales_Rep__c == null) {
            rec.Sales_Rep__c = UserInfo.getUserId();
        }
        update rec;

        String processDefinitionId = resolveVisitApprovalProcessId();
        if (String.isBlank(processDefinitionId)) {
            throw new AuraHandledException(
                'No active Visit approval process found. Configure and activate a Visit approval process in this org.'
            );
        }

        try {
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(rec.Id);
            // Mirror the working initial submit flow and let Salesforce select the active process.
            req.setSkipEntryCriteria(false);
            Approval.ProcessResult result = Approval.process(req);
            if (result == null || !result.isSuccess()) {
                throw new AuraHandledException('Visit approval resubmission failed for record ' + rec.Id + '.');
            }
        } catch (DmlException submitEx) {
            String statusCode = String.valueOf(submitEx.getDmlStatusCode(0));
            String dmlMessage = submitEx.getDmlMessage(0);
            String detailMsg = 'Visit approval resubmission failed: ' + dmlMessage
                             + '. StatusCode=' + statusCode + '.';
            throw new AuraHandledException(detailMsg);
        }
        return 'SUCCESS';
    }


    /**
     * getBeatForWeek
     * Returns the active Beat__c Id for the current user and
     * week containing anchorDate. Used by LWC before opening "Add Visit".
     *
     * @param anchorDate  Any date within the target week.
     */
    @AuraEnabled(cacheable=false)
    public static String getBeatForWeek(Date anchorDate) {
        Date weekStart = mondayOf(anchorDate != null ? anchorDate : Date.today());
        Date weekEnd   = weekStart.addDays(6);

        List<Beat__c> beats = [
            SELECT  Id
            FROM    Beat__c
            WHERE   Sales_Rep__c  = :UserInfo.getUserId()
            AND     Active__c     = true
            AND     Start_Date__c <= :weekEnd
            AND     End_Date__c   >= :weekStart
            ORDER BY Start_Date__c DESC
            LIMIT   1
        ];

        return beats.isEmpty() ? null : beats[0].Id;
    }

    /**
     * getOutletsForBeat
     * Returns all Accounts assigned to a given Beat__c
     * via active Beat_Plan_Store__c records.
     *
     * @param beatId  Id of Beat__c.
     */
    @AuraEnabled(cacheable=true)
    public static List<Account> getOutletsForBeat(String beatId) {
        if (String.isBlank(beatId)) return new List<Account>();

        List<Beat_Plan_Store__c> links = [
            SELECT  Outlet__c,
                    Outlet__r.Name,
                    Outlet__r.OutletStatus__c,
                    Outlet__r.Outlet_Priority__c,
                    Outlet__r.Visit_Frequency__c,
                    Outlet__r.Outlet_Code__c,
                    Outlet__r.Phone
            FROM    Beat_Plan_Store__c
            WHERE   Beat__c   = :beatId
            AND     Active__c = true
            ORDER BY Outlet__r.Name ASC
            LIMIT   500
        ];

        Map<Id, Account> byId = new Map<Id, Account>();
        for (Beat_Plan_Store__c link : links) {
            if (link.Outlet__c == null || link.Outlet__r == null) continue;
            byId.put(link.Outlet__c, link.Outlet__r);
        }

        return new List<Account>(byId.values());
    }

    /**
     * Returns beats mapped to current sales rep for a given date.
     * Only beats whose date range includes the target date are returned.
     */
    @AuraEnabled(cacheable=true)
    public static List<BeatOption> getUserBeats(Date anchorDate) {
        Date targetDate = anchorDate != null ? anchorDate : Date.today();
        List<Beat__c> beats = [
            SELECT Id, Name, Status__c, Start_Date__c, End_Date__c
            FROM Beat__c
            WHERE Sales_Rep__c = :UserInfo.getUserId()
            AND   Active__c = true
            AND   Start_Date__c <= :targetDate
            AND   End_Date__c   >= :targetDate
            ORDER BY Name ASC
            LIMIT 500
        ];

        List<BeatOption> options = new List<BeatOption>();
        for (Beat__c b : beats) {
            BeatOption o = new BeatOption();
            o.id = b.Id;
            o.name = b.Name;
            o.status = b.Status__c;
            options.add(o);
        }
        return options;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // PRIVATE HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    /** Monday of the week containing d (Salesforce toStartOfWeek = Sunday, +1 day) */
    private static Date mondayOf(Date d) {
        DateTime dt = DateTime.newInstance(d, Time.newInstance(0, 0, 0, 0));
        Integer isoDay = Integer.valueOf(dt.format('u')); // 1=MON ... 7=SUN
        return d.addDays(1 - isoDay);
    }

    /** "Feb 11 – Feb 17" */
    private static String weekRangeLabel(Date s, Date e) {
    String startLabel = Datetime.newInstance(s, Time.newInstance(0,0,0,0)).format('MMM d');
	String endLabel   = Datetime.newInstance(e, Time.newInstance(0,0,0,0)).format('MMM d');
	return startLabel + ' – ' + endLabel;
}

    /**
     * Day-of-week label from a Date.
     * format('u') returns 1=MON … 7=SUN in Apex.
     */
    private static String dayLabel(Date d) {
        if (d == null) return 'MON';
        DateTime dt = DateTime.newInstance(d, Time.newInstance(0,0,0,0));
        Integer  u  = Integer.valueOf(dt.format('u'));
        String[] lbl = new String[]{'', 'MON','TUE','WED','THU','FRI','SAT','SUN'};
        return (u >= 1 && u <= 7) ? lbl[u] : 'MON';
    }

    /** Formats a DateTime field to "10:00 AM". Returns '' for null. */
    private static String fmtDateTime(DateTime dt) {
        if (dt == null) return '';
        return dt.format('h:mm a');
    }

    /**
     * Maps visit status to CSS color class for LWC card.
     * Planned (before DB submission in this flow) → card-planned   (grey)
     * Draft (after submit)                        → card-draft     (yellow)
     * Approved                                    → card-completed (green)
     */
    private static String statusToColor(String status, Boolean isCompleted, String approvalStatus) {
        if (approvalStatus == 'Approved') return 'card-completed';
        if (status == 'Draft')         return 'card-draft';
        if (isCompleted == true)       return 'card-completed';
        if (status == 'Missed')        return 'card-missed';
        if (status == 'In Progress' || status == 'In_Progress') return 'card-inprogress';
        return 'card-planned';
    }

    private static String resolveVisitApprovalProcessId() {
        String visitObjectApiName = 'Visit__c';

        List<ProcessDefinition> activeForObject = [
            SELECT Id, DeveloperName
            FROM ProcessDefinition
            WHERE TableEnumOrId = :visitObjectApiName
            AND State = 'Active'
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];

        for (ProcessDefinition pd : activeForObject) {
            if (pd.DeveloperName == 'Visit_Approval_Process') return pd.Id;
        }

        // Avoid silently choosing an unrelated approval process if the expected one isn't active/present.
        if (activeForObject.size() == 1) return activeForObject[0].Id;
        return null;
    }

    /**
     * Converts "HH:mm" time with a Date into a DateTime in org local timezone.
     */
    private static DateTime parseDateTime(Date d, String hhmm) {
        List<String> parts = hhmm.split(':');
        Integer h = Integer.valueOf(parts[0]);
        Integer m = Integer.valueOf(parts[1]);
        return DateTime.newInstance(d, Time.newInstance(h, m, 0, 0));
    }
}