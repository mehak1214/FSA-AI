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
                   Outlet1__r.Name, Outlet1__r.Phone
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
                   Outlet1__r.Name, Outlet1__r.Phone
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
                   Outlet1__r.Name, Outlet1__r.Phone
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

        Visit__c v = [
            SELECT Id
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

        v.Meeting_Notes__c = notes;

        update v;
    }

    /* =========================================================
       CHECK IN VISIT
    ========================================================= */
    @AuraEnabled
    public static void checkInVisit(Id visitId, String lat, String lon){

        Visit__c v = [
            SELECT Id
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

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

        Visit__c v = [
            SELECT Id
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

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

        Day_Attendance__c att = [
            SELECT Id
            FROM Day_Attendance__c
            WHERE Sales_Rep__c = :UserInfo.getUserId()
            AND Attendance_Date__c = :Date.today()
            LIMIT 1
        ];

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

        Blob body = EncodingUtil.base64Decode(base64Data);

        Visit__c v = [
            SELECT Name
            FROM Visit__c
            WHERE Id = :visitId
            LIMIT 1
        ];

        String fileName = 'Visit_Photo_' + v.Name + '.jpg';

        ContentVersion cv = new ContentVersion(
            Title = fileName,
            PathOnClient = fileName,
            VersionData = body
        );

        insert cv;

        cv = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :cv.Id
        ];

        insert new ContentDocumentLink(
            LinkedEntityId = visitId,
            ContentDocumentId = cv.ContentDocumentId,
            ShareType = 'V'
        );

        return cv.Id;
    }

    /* =========================================================
       GET VISIT PHOTO
    ========================================================= */
    @AuraEnabled(cacheable=true)
    public static ContentVersion getVisitPhoto(Id visitId){

        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :visitId
            LIMIT 1
        ];

        if(links.isEmpty()){
            return null;
        }

        List<ContentVersion> versions = [
            SELECT Id, ContentDocumentId, Title
            FROM ContentVersion
            WHERE ContentDocumentId = :links[0].ContentDocumentId
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
       GET OUTLET PHOTO
    ========================================================= */
    @AuraEnabled(cacheable=true)
    public static ContentVersion getOutletPhoto(Id accountId){

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
}