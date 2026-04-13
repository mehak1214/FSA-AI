public with sharing class VisitController {

    /* =========================================================
       START DAY
    ========================================================= */
    @AuraEnabled
    public static Id startDay(String lat, String lon){

        if(String.isBlank(lat) || String.isBlank(lon)){
            throw new AuraHandledException('Location permission is required.');
        }

        Id userId = UserInfo.getUserId();
        Date today = Date.today();

        if(![
            SELECT Id
            FROM Day_Attendance__c
            WHERE Sales_Rep__c = :userId
            AND Attendance_Date__c = :today
            LIMIT 1
        ].isEmpty()){
            throw new AuraHandledException('Day already started.');
        }

        Day_Attendance__c att = new Day_Attendance__c(
            Sales_Rep__c = userId,
            Attendance_Date__c = today,
            Start_Time__c = System.now(),
            Start_Location__Latitude__s = Decimal.valueOf(lat),
            Start_Location__Longitude__s = Decimal.valueOf(lon)
        );

        insert att;

        return att.Id;
    }

    /* =========================================================
       TODAY ATTENDANCE
    ========================================================= */
    @AuraEnabled(cacheable=true)
    public static Day_Attendance__c getTodayAttendance(){

        List<Day_Attendance__c> att = [
            SELECT Id, Start_Time__c, End_Time__c
            FROM Day_Attendance__c
            WHERE Sales_Rep__c = :UserInfo.getUserId()
            AND Attendance_Date__c = :Date.today()
            LIMIT 1
        ];

        return att.isEmpty() ? null : att[0];
    }

    /* =========================================================
       DASHBOARD SNAPSHOT
    ========================================================= */
    @AuraEnabled(cacheable=true)
    public static DashboardSnapshot getDashboardSnapshot(String visitDate){

        Date targetDate = Date.today();

        if(!String.isBlank(visitDate)){
            try{
                targetDate = Date.valueOf(visitDate);
            }catch(Exception e){}
        }

        Id userId = UserInfo.getUserId();
        Integer monthNum = targetDate.month();
        Integer yearNum = targetDate.year();

        DashboardSnapshot snapshot = new DashboardSnapshot();

        List<String> monthNames = new List<String>{
            'January','February','March','April','May','June',
            'July','August','September','October','November','December'
        };

        snapshot.monthLabel = monthNames[monthNum-1];

        List<Sales_Target__c> targets = [
            SELECT Name, Target_Amount__c
            FROM Sales_Target__c
            WHERE Sales_Rep__c = :userId
            AND CALENDAR_MONTH(Month_Year__c) = :monthNum
            AND CALENDAR_YEAR(Month_Year__c) = :yearNum
            LIMIT 1
        ];

        if(!targets.isEmpty()){
            snapshot.salesTargetName = targets[0].Name;
            snapshot.targetAmount = targets[0].Target_Amount__c;
        }

        List<Monthly_Performance__c> perf = [
            SELECT Actual_Sales__c, Achievement__c,
                   Completed_Visits__c, Planned_Visits__c,
                   Visit_Completion__c, Performance_Rating__c
            FROM Monthly_Performance__c
            WHERE Sales_Rep__c = :userId
            AND CALENDAR_MONTH(Month_Year__c) = :monthNum
            AND CALENDAR_YEAR(Month_Year__c) = :yearNum
            LIMIT 1
        ];

        if(!perf.isEmpty()){
            Monthly_Performance__c row = perf[0];

            snapshot.actualSales = row.Actual_Sales__c;
            snapshot.achievementPercent = row.Achievement__c;
            snapshot.completedVisits = row.Completed_Visits__c;
            snapshot.plannedVisits = row.Planned_Visits__c;
            snapshot.visitCompletionPercent = row.Visit_Completion__c;
            snapshot.performanceRating = row.Performance_Rating__c;
            snapshot.incentiveAmount = (row.Actual_Sales__c == null) ? 0 : (row.Actual_Sales__c * 0.05);
        }

        // FIX: Populate schemeTitle/schemeDetail from active Scheme__c records.
        // These fields are declared on DashboardSnapshot but were never set.
        List<Scheme__c> schemes = [
            SELECT Scheme_Name__c, Discount__c
            FROM Scheme__c
            WHERE Start_Date__c <= :targetDate
            AND End_Date__c >= :targetDate
            LIMIT 1
        ];
        if (!schemes.isEmpty()) {
            snapshot.schemeTitle  = schemes[0].Scheme_Name__c;
            snapshot.schemeDetail = 'Discount: ' + schemes[0].Discount__c + '%';
        }

        return snapshot;
    }

    public class DashboardSnapshot{
        @AuraEnabled public String monthLabel;
        @AuraEnabled public String salesTargetName;
        @AuraEnabled public Decimal targetAmount;
        @AuraEnabled public Decimal actualSales;
        @AuraEnabled public Decimal achievementPercent;
        @AuraEnabled public Decimal completedVisits;
        @AuraEnabled public Decimal plannedVisits;
        @AuraEnabled public Decimal visitCompletionPercent;
        @AuraEnabled public String performanceRating;
        @AuraEnabled public Decimal incentiveAmount;
        @AuraEnabled public String schemeTitle;
        @AuraEnabled public String schemeDetail;
    }

    /* =========================================================
       TODAY BEATS
    ========================================================= */
    @AuraEnabled(cacheable=true)
    public static List<Beat__c> getTodayBeats(Date visitDate){

        if(visitDate == null){
            visitDate = Date.today();
        }

        Set<Id> beatIds = new Set<Id>();

        for(AggregateResult ar : [
            SELECT Beat__c beatId
            FROM Visit__c
            WHERE Sales_Rep__c = :UserInfo.getUserId()
            AND Visit_Date__c = :visitDate
            AND Beat__c != null
            GROUP BY Beat__c
        ]){
            beatIds.add((Id)ar.get('beatId'));
        }

        if(beatIds.isEmpty()){
            return new List<Beat__c>();
        }

        return [
            SELECT Id, Name, Active__c
            FROM Beat__c
            WHERE Id IN :beatIds
            AND Active__c = true
            ORDER BY Name
        ];
    }

    /* =========================================================
       DAY TIMELINE
    ========================================================= */
    @AuraEnabled(cacheable=true)
    public static List<Visit__c> getDayTimeline(Date visitDate){

        if(visitDate == null){
            visitDate = Date.today();
        }

        return [
            SELECT Id, Name, Visit_Status__c,
                   Planned_Start_Time__c, Planned_End_Time__c,
                   Sequence__c, Visit_Date__c,
                   Check_In_Time__c, Check_Out_Time__c,
                   Actual_Duration__c,
                   Outlet1__r.Name, Outlet1__r.Phone,
                   Outlet1__r.ShippingStreet, Outlet1__r.ShippingCity,
                   Outlet1__r.ShippingState, Outlet1__r.ShippingPostalCode,
                   Outlet1__r.ShippingCountry,
                   Outlet1__r.Outlet_Location__Latitude__s,
                   Outlet1__r.Outlet_Location__Longitude__s
            FROM Visit__c
            WHERE Sales_Rep__c = :UserInfo.getUserId()
            AND Visit_Date__c = :visitDate
            ORDER BY Planned_Start_Time__c
        ];
    }

    /* =========================================================
       VISITS BY BEAT
    ========================================================= */
    @AuraEnabled(cacheable=true)
    public static List<Visit__c> getVisitsByBeat(Id beatId, Date visitDate){

        if(visitDate == null){
            visitDate = Date.today();
        }

        return [
            SELECT Id, Name, Visit_Status__c,
                   Planned_Start_Time__c, Planned_End_Time__c,
                   Sequence__c,
                   Check_In_Time__c, Check_Out_Time__c,
                   Actual_Duration__c,
                   Outlet1__r.Name, Outlet1__r.Phone,
                   Outlet1__r.ShippingStreet, Outlet1__r.ShippingCity,
                   Outlet1__r.ShippingState, Outlet1__r.ShippingPostalCode,
                   Outlet1__r.ShippingCountry,
                   Outlet1__r.Outlet_Location__Latitude__s,
                   Outlet1__r.Outlet_Location__Longitude__s
            FROM Visit__c
            WHERE Sales_Rep__c = :UserInfo.getUserId()
            AND Visit_Date__c = :visitDate
            AND Beat__c = :beatId
            ORDER BY Sequence__c
        ];
    }

    /* =========================================================
       VISIT DETAIL
    ========================================================= */
    @AuraEnabled(cacheable=true)
    public static Visit__c getVisitDetail(Id visitId){

        if(visitId == null){
            return null;
        }

        return [
            SELECT Id, Name, Visit_Status__c,
                   Planned_Start_Time__c, Planned_End_Time__c,
                   Sequence__c,
                   Check_In_Time__c, Check_Out_Time__c,
                   Actual_Duration__c,
                   Meeting_Notes__c, rating__c, feedback__c,
                   Outlet1__r.Name, Outlet1__r.Phone,
                   Outlet1__r.ShippingStreet, Outlet1__r.ShippingCity,
                   Outlet1__r.ShippingState, Outlet1__r.ShippingPostalCode,
                   Outlet1__r.ShippingCountry,
                   Outlet1__r.Outlet_Location__Latitude__s,
                   Outlet1__r.Outlet_Location__Longitude__s
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];
    }

    /* =========================================================
       SAVE RATING & FEEDBACK
    ========================================================= */
    @AuraEnabled
    public static void saveRatingAndFeedback(Id visitId, Integer rating, String feedback){

        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (rating == null || rating < 1 || rating > 5) {
            throw new AuraHandledException('Rating must be between 1 and 5.');
        }
        if (String.isBlank(feedback)) {
            throw new AuraHandledException('Feedback is required.');
        }

        Visit__c v = [
            SELECT Id
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

        v.rating__c = rating;
        v.feedback__c = feedback;

        update v;
    }

    /* =========================================================
       SAVE MEETING NOTES
    ========================================================= */
    @AuraEnabled
    public static void saveMeetingNotes(Id visitId, String notes){

        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }

        Visit__c v = [
            SELECT Id
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

        // Clear the field completely if notes are empty or only contain empty array
        if (String.isBlank(notes) || notes == '[]') {
            v.Meeting_Notes__c = null;
        } else {
            v.Meeting_Notes__c = notes;
        }

        update v;
    }

    /* =========================================================
       CHECK IN VISIT
    ========================================================= */
    @AuraEnabled
    public static void checkInVisit(Id visitId, String lat, String lon){

        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (String.isBlank(lat) || String.isBlank(lon)) {
            throw new AuraHandledException('Location permission is required.');
        }

        List<Day_Attendance__c> attendance = [
            SELECT Id, End_Time__c
            FROM Day_Attendance__c
            WHERE Sales_Rep__c = :UserInfo.getUserId()
            AND Attendance_Date__c = :Date.today()
            LIMIT 1
        ];

        if (!attendance.isEmpty() && attendance[0].End_Time__c != null) {
            throw new AuraHandledException('Day has already ended.');
        }

        Visit__c v = [
            SELECT Id, Visit_Status__c
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

        if (v.Visit_Status__c != 'Approved') {
            throw new AuraHandledException('Only approved visits can be checked in.');
        }

        Boolean anotherInProgress = ![
            SELECT Id
            FROM Visit__c
            WHERE Sales_Rep__c = :UserInfo.getUserId()
            AND Visit_Date__c = :Date.today()
            AND Visit_Status__c = 'In Progress'
            AND Id != :visitId
            LIMIT 1
        ].isEmpty();

        if (anotherInProgress) {
            throw new AuraHandledException('Only one visit may be in progress at a time.');
        }

        v.Visit_Status__c = 'In Progress';
        v.Check_In_Time__c = System.now();
        v.Check_In_Location__Latitude__s = Decimal.valueOf(lat);
        v.Check_In_Location__Longitude__s = Decimal.valueOf(lon);

        update v;
    }

    /* =========================================================
       CHECK OUT VISIT
    ========================================================= */
    @AuraEnabled
    public static void checkOutVisit(Id visitId, String lat, String lon){

        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (String.isBlank(lat) || String.isBlank(lon)) {
            throw new AuraHandledException('Location permission is required.');
        }

        Visit__c v = [
            SELECT Id, Visit_Status__c, Rating__c, Feedback__c
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

        if (v.Visit_Status__c != 'In Progress') {
            throw new AuraHandledException('Visit must be in progress before checkout.');
        }
        if (v.Rating__c == null || String.isBlank(v.Feedback__c)) {
            throw new AuraHandledException('Rating and feedback are required before checkout.');
        }

        v.Visit_Status__c = 'Completed';
        v.Check_Out_Time__c = System.now();
        v.Check_Out_Location__Latitude__s = Decimal.valueOf(lat);
        v.Check_Out_Location__Longitude__s = Decimal.valueOf(lon);

        update v;
    }

    /* =========================================================
       END DAY
    ========================================================= */
    @AuraEnabled
    public static void endDay(String lat, String lon){

        if (String.isBlank(lat) || String.isBlank(lon)) {
            throw new AuraHandledException('Location permission is required.');
        }

        List<Day_Attendance__c> attendance = [
            SELECT Id, End_Time__c
            FROM Day_Attendance__c
            WHERE Sales_Rep__c = :UserInfo.getUserId()
            AND Attendance_Date__c = :Date.today()
            LIMIT 1
        ];

        if (attendance.isEmpty()) {
            throw new AuraHandledException('Day has not been started.');
        }

        Day_Attendance__c att = attendance[0];
        if (att.End_Time__c != null) {
            throw new AuraHandledException('Day already ended.');
        }

        att.End_Time__c = System.now();
        att.End_Location__Latitude__s = Decimal.valueOf(lat);
        att.End_Location__Longitude__s = Decimal.valueOf(lon);

        update att;
    }

    /* =========================================================
       VISIT PHOTO UPLOAD
    ========================================================= */
    @AuraEnabled
    public static Id uploadVisitPhoto(Id visitId, String base64Data, String contentType){

        if (visitId == null) {
            throw new AuraHandledException('Visit Id is required.');
        }
        if (String.isBlank(base64Data)) {
            throw new AuraHandledException('Photo data is required.');
        }
        if (String.isBlank(contentType)) {
            contentType = 'image/jpeg';
        }

        Blob body;
        try {
            body = EncodingUtil.base64Decode(base64Data);
        } catch (Exception ex) {
            throw new AuraHandledException('Invalid base64 data.');
        }

        Visit__c v = [
            SELECT Name
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

        String fileName = 'Visit_Photo_' + v.Name + '.jpg';

        // FIX: Use FirstPublishLocationId to atomically link the ContentVersion
        // directly to the Visit record. This eliminates the separate
        // ContentDocumentLink insert, which caused UNABLE_TO_LOCK_ROW errors
        // and permission failures in concurrent test runs.
        ContentVersion cv = new ContentVersion(
            Title                  = fileName,
            PathOnClient           = fileName,
            VersionData            = body,
            FirstPublishLocationId = visitId
        );

        insert cv;

        return cv.Id;
    }

    /* =========================================================
       GET VISIT PHOTO
    ========================================================= */
    @AuraEnabled(cacheable=true)
    public static ContentVersion getVisitPhoto(Id visitId){

        if (visitId == null) {
            return null;
        }

        // Collect all ContentDocumentIds linked to this visit
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :visitId
        ];

        if(links.isEmpty()){
            return null;
        }

        Set<Id> docIds = new Set<Id>();
        for(ContentDocumentLink cdl : links){
            docIds.add(cdl.ContentDocumentId);
        }

        // Only return the dedicated visit photo — identified by its Title prefix
        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE ContentDocumentId IN :docIds
            AND Title LIKE 'Visit\_Photo\_%'
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        return versions.isEmpty() ? null : versions[0];
    }

    /* =========================================================
       DELETE VISIT PHOTO
    ========================================================= */
    @AuraEnabled
    public static void deleteVisitPhoto(Id contentVersionId){

        ContentVersion cv = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
        ];

        delete [
            SELECT Id
            FROM ContentDocument
            WHERE Id = :cv.ContentDocumentId
        ];
    }

    /* =========================================================
       RENAME ATTACHMENT
    ========================================================= */
    @AuraEnabled
    public static void renameAttachment(Id contentDocumentId, String newTitle){

        List<ContentVersion> versions = [
            SELECT Id, Title
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];

        if(!versions.isEmpty()){
            versions[0].Title = newTitle;
            update versions[0];
        }
    }

    /* =========================================================
       DELETE ATTACHMENT (by ContentDocumentId)
    ========================================================= */
    @AuraEnabled
    public static void deleteAttachment(Id contentDocumentId){
        delete [
            SELECT Id
            FROM ContentDocument
            WHERE Id = :contentDocumentId
        ];
    }

    /* =========================================================
       GET OUTLET PHOTO
    ========================================================= */
    @AuraEnabled(cacheable=true)
    public static ContentVersion getOutletPhoto(Id accountId){

        if (accountId == null) {
            return null;
        }

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId,
                   ContentDocument.LatestPublishedVersionId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :accountId
            LIMIT 1
        ];

        if(links.isEmpty()){
            return null;
        }

        return [
            SELECT Id, Title, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :links[0].ContentDocument.LatestPublishedVersionId
            LIMIT 1
        ];
    }

    /* =========================================================
       TODAY VISIT STATUS CHECK (for End Day pre-flight)
    ========================================================= */
    @AuraEnabled
    public static VisitStatusCheckResult getTodayVisitStatusCheck() {

        Id userId = UserInfo.getUserId();
        Date today = Date.today();

        List<Visit__c> todayVisits = [
            SELECT Id, Name, Visit_Status__c, Outlet1__r.Name
            FROM Visit__c
            WHERE Sales_Rep__c = :userId
            AND Visit_Date__c = :today
            ORDER BY Sequence__c NULLS LAST, Name
        ];

        VisitStatusCheckResult result = new VisitStatusCheckResult();

        for (Visit__c v : todayVisits) {
            String status = v.Visit_Status__c;

            if (status == 'In Progress') {
                VisitSummary vs = new VisitSummary();
                vs.Id = v.Id;
                vs.Name = v.Name;
                vs.outletName = v.Outlet1__r != null ? v.Outlet1__r.Name : '';
                result.inProgressVisit = vs;
                return result;
            }

            if (status == 'Approved') {
                VisitSummary vs = new VisitSummary();
                vs.Id = v.Id;
                vs.Name = v.Name;
                vs.outletName = v.Outlet1__r != null ? v.Outlet1__r.Name : '';
                result.draftVisits.add(vs);
            }
        }

        return result;
    }

    public class VisitStatusCheckResult {
        @AuraEnabled public VisitSummary inProgressVisit;
        @AuraEnabled public List<VisitSummary> draftVisits = new List<VisitSummary>();
    }

    public class VisitSummary {
        @AuraEnabled public Id Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String outletName;
    }

    /* =========================================================
       MARK DRAFT VISITS AS MISSED
    ========================================================= */
    @AuraEnabled
    public static void markDraftVisitsAsMissed(List<Id> visitIds) {

        if (visitIds == null || visitIds.isEmpty()) return;

        Id userId = UserInfo.getUserId();
        Date today = Date.today();

        List<Visit__c> toUpdate = [
            SELECT Id, Visit_Status__c
            FROM Visit__c
            WHERE Id IN :visitIds
            AND Sales_Rep__c = :userId
            AND Visit_Date__c = :today
            AND Visit_Status__c = 'Approved'
        ];

        for (Visit__c v : toUpdate) {
            v.Visit_Status__c = 'Missed';
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

}