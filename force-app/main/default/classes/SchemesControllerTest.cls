/**
 * @description Unit tests for SchemesController.
 * Covers: getAllSchemes, getSchemesDashboard.
 */
@IsTest
private class SchemesControllerTest {

    @TestSetup
    static void setup() {
        // Create 4 "active" schemes — Active__c is a formula (Start_Date__c <= Today <= End_Date__c)
        TestDataFactory.createActiveSchemeWithFlag(5, 30);
        TestDataFactory.createActiveSchemeWithFlag(10, 20);
        TestDataFactory.createActiveSchemeWithFlag(15, 10);
        TestDataFactory.createActiveSchemeWithFlag(20, 5);

        // One "inactive" scheme — End_Date__c in the past so formula resolves to false
        Scheme__c inactive = new Scheme__c(
            Scheme_Name__c          = 'Inactive Scheme',
            Discount__c             = 50,
            Threshold_Quantity__c   = 1,
            Start_Date__c           = Date.today().addDays(-10),
            End_Date__c             = Date.today().addDays(-1)  // ended yesterday
        );
        insert inactive;
    }

    /* =========================================================
       TEST getAllSchemes - returns all schemes (active and inactive)
       ========================================================= */
    @IsTest
    static void testGetAllSchemes_returnsAllSchemes() {
        Test.startTest();
        List<SchemesController.SchemeWrapper> schemes = SchemesController.getAllSchemes();
        Test.stopTest();

        System.assertNotEquals(null, schemes, 'Schemes list should not be null');
        System.assertEquals(5, schemes.size(), 'All 5 schemes (active+inactive) should be returned');
    }

    @IsTest
    static void testGetAllSchemes_wrapperFieldsPopulated() {
        Test.startTest();
        List<SchemesController.SchemeWrapper> schemes = SchemesController.getAllSchemes();
        Test.stopTest();

        SchemesController.SchemeWrapper w = schemes[0];
        System.assertNotEquals(null, w.schemeId, 'schemeId should be set');
        System.assertNotEquals(null, w.schemeName, 'schemeName should be set');
        System.assertNotEquals(null, w.color, 'color should be set');
        System.assertNotEquals(null, w.tileStyle, 'tileStyle should be set');
        System.assertNotEquals(null, w.detailStyle, 'detailStyle should be set');
    }

    @IsTest
    static void testGetAllSchemes_colorsAssignedCyclically() {
        Test.startTest();
        List<SchemesController.SchemeWrapper> schemes = SchemesController.getAllSchemes();
        Test.stopTest();

        // Colors cycle through 6 options. With 5 schemes all should have a color.
        for (SchemesController.SchemeWrapper w : schemes) {
            System.assertNotEquals(null, w.color, 'Every wrapper should have a color');
        }
    }

    @IsTest
    static void testGetAllSchemes_empty_returnsEmptyList() {
        delete [SELECT Id FROM Scheme__c];

        Test.startTest();
        List<SchemesController.SchemeWrapper> schemes = SchemesController.getAllSchemes();
        Test.stopTest();

        System.assertEquals(0, schemes.size(), 'Empty list expected when no schemes exist');
    }

    /* =========================================================
       TEST getSchemesDashboard - returns top 3 active + counts
       ========================================================= */
    @IsTest
    static void testGetSchemesDashboard_returnsTopThreeActive() {
        Test.startTest();
        Map<String, Object> result = SchemesController.getSchemesDashboard();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Dashboard result should not be null');

        List<SchemesController.SchemeWrapper> topSchemes =
            (List<SchemesController.SchemeWrapper>) result.get('topSchemes');
        System.assertNotEquals(null, topSchemes, 'topSchemes should not be null');
        System.assertEquals(3, topSchemes.size(), 'Should return top 3 active schemes');

        Integer totalCount = (Integer) result.get('totalCount');
        Integer moreCount  = (Integer) result.get('moreCount');
        System.assertEquals(4, totalCount, 'totalCount should be 4 active schemes');
        System.assertEquals(1, moreCount, 'moreCount should be 1 (4 - 3)');
    }

    @IsTest
    static void testGetSchemesDashboard_noActiveSchemes_returnsEmpty() {
        // Make all "active" schemes inactive by backdating End_Date__c
        List<Scheme__c> actives = [SELECT Id FROM Scheme__c WHERE End_Date__c >= :Date.today()];
        for (Scheme__c s : actives) s.End_Date__c = Date.today().addDays(-1);
        update actives;

        Test.startTest();
        Map<String, Object> result = SchemesController.getSchemesDashboard();
        Test.stopTest();

        List<SchemesController.SchemeWrapper> topSchemes =
            (List<SchemesController.SchemeWrapper>) result.get('topSchemes');
        System.assertEquals(0, topSchemes.size(), 'No active schemes — topSchemes should be empty');
        System.assertEquals(0, (Integer) result.get('totalCount'), 'totalCount should be 0');
        System.assertEquals(0, (Integer) result.get('moreCount'), 'moreCount should be 0');
    }

    @IsTest
    static void testGetSchemesDashboard_fewerThanThreeActive_returnsAll() {
        // Delete 3 active (future end date) schemes, leaving 1
        List<Scheme__c> actives = [SELECT Id FROM Scheme__c WHERE End_Date__c >= :Date.today() LIMIT 3];
        delete actives;

        Test.startTest();
        Map<String, Object> result = SchemesController.getSchemesDashboard();
        Test.stopTest();

        List<SchemesController.SchemeWrapper> topSchemes =
            (List<SchemesController.SchemeWrapper>) result.get('topSchemes');
        System.assertEquals(1, topSchemes.size(), 'Only 1 active scheme remains');
        System.assertEquals(0, (Integer) result.get('moreCount'), 'moreCount should be 0');
    }
}