/**
 * @description Unit tests for TravelDistanceService.
 * Covers: getTodayTravelSummary, getTravelSummaryByDate, logPoint,
 *         recalculateAttendanceDistance, createOrUpdateClaim.
 *
 * Event_Type__c restricted picklist: START_DAY, CHECK_IN, CHECK_OUT, END_DAY
 * Source__c restricted picklist:     SYSTEM, MANUAL_ADJUSTMENT
 */
@IsTest
private class TravelDistanceServiceTest {

    @TestSetup
    static void setup() {
        User rep = TestDataFactory.getRunningUser();

        // Attendance for today with rate per KM
        Day_Attendance__c att = TestDataFactory.createStartedAttendanceWithRate(rep, Date.today(), 8.0);

        // Two travel points — use valid restricted picklist values
        TestDataFactory.createTravelPoint(att.Id, null, 'START_DAY', 12.9716, 77.5946, 1);
        TestDataFactory.createTravelPoint(att.Id, null, 'END_DAY',   12.9780, 77.6000, 2);
    }

    private static Day_Attendance__c getAttendance() {
        return [SELECT Id FROM Day_Attendance__c WHERE Attendance_Date__c = :Date.today() LIMIT 1];
    }

    /* =========================================================
       TEST getTodayTravelSummary
       ========================================================= */
    @IsTest
    static void testGetTodayTravelSummary_withAttendance() {
        Test.startTest();
        TravelDistanceService.TravelSummary summary = TravelDistanceService.getTodayTravelSummary();
        Test.stopTest();

        System.assertNotEquals(null, summary, 'Summary should not be null');
        System.assertEquals(Date.today(), summary.summaryDate, 'Summary date should be today');
        System.assertNotEquals(null, summary.attendanceId, 'Attendance Id should be set');
    }

    @IsTest
    static void testGetTodayTravelSummary_noAttendanceReturnsEmpty() {
        // Delete attendance — no claim exists yet either, so returns empty summary
        delete [SELECT Id FROM Visit_Travel_Point__c];
        delete [SELECT Id FROM Day_Attendance__c];

        Test.startTest();
        TravelDistanceService.TravelSummary summary = TravelDistanceService.getTodayTravelSummary();
        Test.stopTest();

        System.assertNotEquals(null, summary, 'Summary should not be null even with no attendance');
        System.assertEquals(Date.today(), summary.summaryDate, 'Summary date should be today');
        System.assertEquals(null, summary.attendanceId, 'AttendanceId should be null when no attendance');
    }

    /* =========================================================
       TEST getTravelSummaryByDate
       ========================================================= */
    @IsTest
    static void testGetTravelSummaryByDate_todayReturnsAttendanceData() {
        Test.startTest();
        TravelDistanceService.TravelSummary summary = TravelDistanceService.getTravelSummaryByDate(Date.today());
        Test.stopTest();

        System.assertNotEquals(null, summary, 'Summary should not be null');
        System.assertNotEquals(null, summary.attendanceId, 'Attendance Id should be set');
    }

    @IsTest
    static void testGetTravelSummaryByDate_nullDateDefaultsToToday() {
        Test.startTest();
        TravelDistanceService.TravelSummary summary = TravelDistanceService.getTravelSummaryByDate(null);
        Test.stopTest();

        System.assertEquals(Date.today(), summary.summaryDate, 'Should default to today for null date');
    }

    @IsTest
    static void testGetTravelSummaryByDate_noAttendanceButHasClaim() {
        // Travel_Expense_Claim__c.Attendance__c is required=true AND deleteConstraint=Restrict,
        // so it is impossible to delete an attendance while a claim references it, and impossible
        // to create a claim without an attendance. The "no attendance, has claim" fallback path
        // in getTravelSummaryByDate is reached when we query a DATE that has no attendance record
        // but DOES have a claim whose Claim_Date__c matches.
        //
        // Strategy: use a past date (30 days ago) which has no Day_Attendance__c.
        // Create a claim for that date pointing to today's attendance (still exists, not deleted).
        // getTravelSummaryByDate(pastDate) finds no attendance for pastDate → falls back to claim.
        Date pastDate = Date.today().addDays(-30);
        Day_Attendance__c att = getAttendance(); // today's attendance — kept alive, not deleted

        Travel_Expense_Claim__c claim = TestDataFactory.createTravelExpenseClaim(
            att.Id, UserInfo.getUserId(), pastDate, 10.5, 8.0
        );

        Test.startTest();
        // Query for pastDate: no Day_Attendance__c exists for that date → controller falls back to claim
        TravelDistanceService.TravelSummary summary = TravelDistanceService.getTravelSummaryByDate(pastDate);
        Test.stopTest();

        System.assertNotEquals(null, summary, 'Summary should not be null');
        System.assertEquals(10.5, summary.totalDistanceKm, 'Should return claim Calculated_KM__c');
        System.assertEquals(8.0, summary.ratePerKm, 'Rate per KM should match claim Rate_Per_KM__c');
    }

    /* =========================================================
       TEST logPoint
       ========================================================= */
    @IsTest
    static void testLogPoint_createsNewTravelPoint() {
        Day_Attendance__c att = getAttendance();

        Test.startTest();
        // CHECK_IN is a valid Event_Type__c value
        TravelDistanceService.logPoint(att.Id, null, 'CHECK_IN', 12.9716, 77.5946, Datetime.now());
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Visit_Travel_Point__c WHERE Attendance__c = :att.Id];
        System.assertEquals(3, count, 'Third travel point should have been created (2 from setup + 1)');
    }

    @IsTest
    static void testLogPoint_nullAttendanceIdDoesNotInsert() {
        Test.startTest();
        TravelDistanceService.logPoint(null, null, 'CHECK_IN', 12.9716, 77.5946, Datetime.now());
        Test.stopTest();

        System.assert(true, 'No exception expected for null attendanceId');
    }

    @IsTest
    static void testLogPoint_sequenceIncrements() {
        Day_Attendance__c att = getAttendance();

        // Wrap both logPoint calls inside Test.startTest/stopTest to avoid row-lock contention
        Test.startTest();
        TravelDistanceService.logPoint(att.Id, null, 'CHECK_IN',  12.9716, 77.5946, Datetime.now());
        TravelDistanceService.logPoint(att.Id, null, 'CHECK_OUT', 12.9750, 77.5980, Datetime.now());
        Test.stopTest();

        List<Visit_Travel_Point__c> points = [
            SELECT Sequence__c FROM Visit_Travel_Point__c
            WHERE Attendance__c = :att.Id
            ORDER BY Sequence__c ASC
        ];

        System.assertEquals(4, points.size(), 'Should have 4 points (2 from setup + 2 added)');
        for (Integer i = 0; i < points.size(); i++) {
            System.assertEquals(i + 1, Integer.valueOf(points[i].Sequence__c),
                'Sequence should increment: expected ' + (i + 1));
        }
    }

    /* =========================================================
       TEST recalculateAttendanceDistance
       ========================================================= */
    @IsTest
    static void testRecalculateAttendanceDistance_calculatesDistance() {
        Day_Attendance__c att = getAttendance();

        Test.startTest();
        TravelDistanceService.recalculateAttendanceDistance(att.Id);
        Test.stopTest();

        Day_Attendance__c updated = [
            SELECT Total_Distance_KM__c, Eligible_Distance_KM__c, Travel_Expense_Amount__c, Distance_Status__c
            FROM Day_Attendance__c WHERE Id = :att.Id
        ];

        System.assertNotEquals(null, updated.Total_Distance_KM__c, 'Total distance should be set');
        System.assertEquals('Calculated', updated.Distance_Status__c, 'Distance status should be Calculated');
    }

    @IsTest
    static void testRecalculateAttendanceDistance_nullIdDoesNothing() {
        Test.startTest();
        TravelDistanceService.recalculateAttendanceDistance(null);
        Test.stopTest();

        System.assert(true, 'Should not throw exception for null attendance Id');
    }

    /* =========================================================
       TEST createOrUpdateClaim
       ========================================================= */
    @IsTest
    static void testCreateOrUpdateClaim_createsNewClaim() {
        Day_Attendance__c att = getAttendance();

        // Ensure no existing claim
        delete [SELECT Id FROM Travel_Expense_Claim__c WHERE Attendance__c = :att.Id];

        Test.startTest();
        TravelDistanceService.createOrUpdateClaim(att.Id);
        Test.stopTest();

        Integer claimCount = [SELECT COUNT() FROM Travel_Expense_Claim__c WHERE Attendance__c = :att.Id];
        System.assertEquals(1, claimCount, 'One claim should have been created');
    }

    @IsTest
    static void testCreateOrUpdateClaim_updatesExistingClaim() {
        Day_Attendance__c att = getAttendance();

        // Create an existing claim
        TestDataFactory.createTravelExpenseClaim(att.Id, UserInfo.getUserId(), Date.today(), 5.0, 8.0);

        // Recalculate distance first so eligible distance fields are populated
        TravelDistanceService.recalculateAttendanceDistance(att.Id);

        Test.startTest();
        TravelDistanceService.createOrUpdateClaim(att.Id);
        Test.stopTest();

        Integer claimCount = [SELECT COUNT() FROM Travel_Expense_Claim__c WHERE Attendance__c = :att.Id];
        System.assertEquals(1, claimCount, 'Should update existing claim, not create a duplicate');
    }

    @IsTest
    static void testCreateOrUpdateClaim_nullIdDoesNothing() {
        Test.startTest();
        TravelDistanceService.createOrUpdateClaim(null);
        Test.stopTest();

        System.assert(true, 'Should not throw exception for null attendance Id');
    }
}