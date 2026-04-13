public with sharing class TravelDistanceService {
    private static final Decimal EARTH_RADIUS_KM = 6371;
    private static final Decimal NOISE_THRESHOLD_KM = 0.10;
    private static final Double PI = 3.141592653589793;

    @AuraEnabled
    public static TravelSummary getTodayTravelSummary() {
        return getTravelSummaryByDate(Date.today());
    }

    @AuraEnabled
    public static TravelSummary getTravelSummaryByDate(Date targetDate) {
        Date selectedDate = targetDate == null ? Date.today() : targetDate;
        List<Day_Attendance__c> atts = [
            SELECT Id, Total_Distance_KM__c, Eligible_Distance_KM__c, Travel_Expense_Amount__c, Rate_Per_KM__c, Distance_Status__c
            FROM Day_Attendance__c
            WHERE Sales_Rep__c = :UserInfo.getUserId()
            AND Attendance_Date__c = :selectedDate
            LIMIT 1
        ];

        if (atts.isEmpty()) {
            List<Travel_Expense_Claim__c> claims = [
                SELECT Id, Calculated_KM__c, Approved_KM__c, Rate_Per_KM__c, Claim_Amount__c, Status__c, Attendance__c
                FROM Travel_Expense_Claim__c
                WHERE Sales_Rep__c = :UserInfo.getUserId()
                AND Claim_Date__c = :selectedDate
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];

            if (claims.isEmpty()) {
                TravelSummary emptySummary = new TravelSummary();
                emptySummary.summaryDate = selectedDate;
                return emptySummary;
            }

            Travel_Expense_Claim__c claim = claims[0];
            TravelSummary claimSummary = new TravelSummary();
            claimSummary.attendanceId = claim.Attendance__c;
            claimSummary.summaryDate = selectedDate;
            claimSummary.totalDistanceKm = claim.Calculated_KM__c;
            claimSummary.eligibleDistanceKm = claim.Approved_KM__c;
            claimSummary.expenseAmount = claim.Claim_Amount__c;
            claimSummary.ratePerKm = claim.Rate_Per_KM__c;
            claimSummary.status = claim.Status__c;
            return claimSummary;
        }

        Day_Attendance__c att = atts[0];
        TravelSummary summary = new TravelSummary();
        summary.attendanceId = att.Id;
        summary.summaryDate = selectedDate;
        summary.totalDistanceKm = att.Total_Distance_KM__c;
        summary.eligibleDistanceKm = att.Eligible_Distance_KM__c;
        summary.expenseAmount = att.Travel_Expense_Amount__c;
        summary.ratePerKm = att.Rate_Per_KM__c;
        summary.status = att.Distance_Status__c;
        return summary;
    }

    public static void logPoint(
        Id attendanceId,
        Id visitId,
        String eventType,
        Decimal latitude,
        Decimal longitude,
        Datetime eventTime
    ) {
        if (attendanceId == null || String.isBlank(eventType) || latitude == null || longitude == null) {
            return;
        }

        Integer nextSequence = 1;
        List<Visit_Travel_Point__c> lastPoint = [
            SELECT Sequence__c
            FROM Visit_Travel_Point__c
            WHERE Attendance__c = :attendanceId
            ORDER BY Sequence__c DESC
            LIMIT 1
        ];
        if (!lastPoint.isEmpty() && lastPoint[0].Sequence__c != null) {
            nextSequence = Integer.valueOf(lastPoint[0].Sequence__c) + 1;
        }

        Visit_Travel_Point__c point = new Visit_Travel_Point__c(
            Sales_Rep__c = UserInfo.getUserId(),
            Attendance__c = attendanceId,
            Visit__c = visitId,
            Event_Type__c = eventType,
            Event_Time__c = eventTime == null ? System.now() : eventTime,
            Latitude__c = latitude,
            Longitude__c = longitude,
            Sequence__c = nextSequence,
            Source__c = 'SYSTEM'
        );

        insert point;
    }

    public static void recalculateAttendanceDistance(Id attendanceId) {
        if (attendanceId == null) {
            return;
        }

        List<Visit_Travel_Point__c> points = [
            SELECT Id, Latitude__c, Longitude__c, Event_Time__c, Sequence__c, Segment_Distance_KM__c
            FROM Visit_Travel_Point__c
            WHERE Attendance__c = :attendanceId
            ORDER BY Event_Time__c ASC, Sequence__c ASC
        ];

        Decimal totalDistance = 0;
        for (Integer i = 0; i < points.size(); i++) {
            Visit_Travel_Point__c current = points[i];
            if (i == 0) {
                current.Segment_Distance_KM__c = 0;
                continue;
            }

            Visit_Travel_Point__c previous = points[i - 1];
            Decimal segment = calculateHaversineKm(
                previous.Latitude__c,
                previous.Longitude__c,
                current.Latitude__c,
                current.Longitude__c
            );

            if (segment < NOISE_THRESHOLD_KM) {
                segment = 0;
            }

            current.Segment_Distance_KM__c = segment.setScale(3);
            totalDistance += current.Segment_Distance_KM__c;
        }

        if (!points.isEmpty()) {
            update points;
        }

        List<Day_Attendance__c> atts = [
            SELECT Id, Rate_Per_KM__c, Distance_Adjustment_KM__c, Total_Distance_KM__c, Eligible_Distance_KM__c, Travel_Expense_Amount__c, Distance_Status__c
            FROM Day_Attendance__c
            WHERE Id = :attendanceId
            LIMIT 1
        ];
        if (atts.isEmpty()) {
            return;
        }

        Day_Attendance__c att = atts[0];
        Decimal adjustment = att.Distance_Adjustment_KM__c == null ? 0 : att.Distance_Adjustment_KM__c;
        Decimal rate = att.Rate_Per_KM__c == null ? 0 : att.Rate_Per_KM__c;
        Decimal eligible = totalDistance + adjustment;
        if (eligible < 0) {
            eligible = 0;
        }

        att.Total_Distance_KM__c = totalDistance.setScale(3);
        att.Eligible_Distance_KM__c = eligible.setScale(3);
        att.Travel_Expense_Amount__c = (eligible * rate).setScale(2);
        att.Distance_Status__c = 'Calculated';
        update att;
    }

    public static void createOrUpdateClaim(Id attendanceId) {
        if (attendanceId == null) {
            return;
        }

        List<Day_Attendance__c> atts = [
            SELECT Id, Sales_Rep__c, Attendance_Date__c, Eligible_Distance_KM__c, Rate_Per_KM__c, Travel_Expense_Amount__c
            FROM Day_Attendance__c
            WHERE Id = :attendanceId
            LIMIT 1
        ];
        if (atts.isEmpty()) {
            return;
        }
        Day_Attendance__c att = atts[0];

        List<Travel_Expense_Claim__c> existing = [
            SELECT Id
            FROM Travel_Expense_Claim__c
            WHERE Attendance__c = :attendanceId
            LIMIT 1
        ];

        Travel_Expense_Claim__c claim = existing.isEmpty()
            ? new Travel_Expense_Claim__c()
            : existing[0];

        claim.Attendance__c = att.Id;
        claim.Sales_Rep__c = att.Sales_Rep__c;
        claim.Claim_Date__c = att.Attendance_Date__c;
        claim.Calculated_KM__c = att.Eligible_Distance_KM__c == null ? 0 : att.Eligible_Distance_KM__c;
        claim.Approved_KM__c = claim.Calculated_KM__c;
        claim.Rate_Per_KM__c = att.Rate_Per_KM__c == null ? 0 : att.Rate_Per_KM__c;
        claim.Claim_Amount__c = att.Travel_Expense_Amount__c == null ? 0 : att.Travel_Expense_Amount__c;
        claim.Status__c = 'Draft';

        if (existing.isEmpty()) {
            insert claim;
        } else {
            update claim;
        }
    }

    private static Decimal calculateHaversineKm(
        Decimal lat1,
        Decimal lon1,
        Decimal lat2,
        Decimal lon2
    ) {
        if (lat1 == null || lon1 == null || lat2 == null || lon2 == null) {
            return 0;
        }
        if (lat1 == lat2 && lon1 == lon2) {
            return 0;
        }

        Double dLat = toRadians((Double) (lat2 - lat1));
        Double dLon = toRadians((Double) (lon2 - lon1));
        Double rLat1 = toRadians((Double) lat1);
        Double rLat2 = toRadians((Double) lat2);

        Double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(rLat1) * Math.cos(rLat2) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
        Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        Decimal arc = Decimal.valueOf(String.valueOf(c));
        return (EARTH_RADIUS_KM * arc).setScale(3);
    }

    public class TravelSummary {
        @AuraEnabled public Id attendanceId;
        @AuraEnabled public Date summaryDate;
        @AuraEnabled public Decimal totalDistanceKm;
        @AuraEnabled public Decimal eligibleDistanceKm;
        @AuraEnabled public Decimal expenseAmount;
        @AuraEnabled public Decimal ratePerKm;
        @AuraEnabled public String status;
    }

    private static Double toRadians(Double degrees) {
        if (degrees == null) {
            return 0;
        }
        return degrees * (PI / 180);
    }
}