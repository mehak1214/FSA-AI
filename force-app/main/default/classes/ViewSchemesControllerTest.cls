/**
 * @description Unit tests for ViewSchemesController.
 * Covers: getAllSchemes — returns SchemeWrapper list sorted by Active__c DESC.
 */
@IsTest
private class ViewSchemesControllerTest {

    @TestSetup
    static void setup() {
        // Two active schemes — Start_Date__c < today < End_Date__c so formula Active__c = true
        TestDataFactory.createActiveSchemeWithFlag(5, 15);
        TestDataFactory.createActiveSchemeWithFlag(10, 25);

        // One inactive scheme — End_Date__c in the past so formula Active__c = false
        Scheme__c inactive = new Scheme__c(
            Scheme_Name__c          = 'VSC Inactive',   // ≤18 chars
            Discount__c             = 5,
            Threshold_Quantity__c   = 1,
            Start_Date__c           = Date.today().addDays(-10),
            End_Date__c             = Date.today().addDays(-1)  // ended yesterday
        );
        insert inactive;
    }

    /* =========================================================
       TEST getAllSchemes - returns all schemes
       ========================================================= */
    @IsTest
    static void testGetAllSchemes_returnsAllSchemes() {
        Test.startTest();
        List<ViewSchemesController.SchemeWrapper> schemes = ViewSchemesController.getAllSchemes();
        Test.stopTest();

        System.assertNotEquals(null, schemes, 'Schemes list should not be null');
        System.assertEquals(3, schemes.size(), 'All 3 schemes should be returned');
    }

    @IsTest
    static void testGetAllSchemes_activeSchemesFirst() {
        Test.startTest();
        List<ViewSchemesController.SchemeWrapper> schemes = ViewSchemesController.getAllSchemes();
        Test.stopTest();

        // ORDER BY Active__c DESC means active (true) schemes sort before inactive (false)
        if (schemes.size() >= 2) {
            System.assertEquals(true, schemes[0].isActive, 'First scheme should be active');
        }
    }

    @IsTest
    static void testGetAllSchemes_wrapperFieldsPopulated() {
        Test.startTest();
        List<ViewSchemesController.SchemeWrapper> schemes = ViewSchemesController.getAllSchemes();
        Test.stopTest();

        for (ViewSchemesController.SchemeWrapper w : schemes) {
            System.assertNotEquals(null, w.schemeId, 'schemeId should be set');
            System.assertNotEquals(null, w.schemeName, 'schemeName should be set');
        }
    }

    @IsTest
    static void testGetAllSchemes_discountAndThresholdPopulated() {
        // Query using date filter instead of formula field in WHERE clause
        Scheme__c source = [SELECT Id, Discount__c, Threshold_Quantity__c, Start_Date__c, End_Date__c
                            FROM Scheme__c
                            WHERE End_Date__c >= :Date.today()
                            LIMIT 1];

        Test.startTest();
        List<ViewSchemesController.SchemeWrapper> schemes = ViewSchemesController.getAllSchemes();
        Test.stopTest();

        ViewSchemesController.SchemeWrapper found = null;
        for (ViewSchemesController.SchemeWrapper w : schemes) {
            if (w.schemeId == source.Id) { found = w; break; }
        }

        System.assertNotEquals(null, found, 'Scheme should appear in results');
        System.assertEquals(source.Discount__c, found.discount, 'Discount should match');
        System.assertEquals(source.Threshold_Quantity__c, found.thresholdQuantity, 'Threshold should match');
        System.assertEquals(source.Start_Date__c, found.startDate, 'Start date should match');
        System.assertEquals(source.End_Date__c, found.endDate, 'End date should match');
    }

    @IsTest
    static void testGetAllSchemes_emptyOrg_returnsEmpty() {
        // Backdate all schemes so none are returned (don't delete to avoid lock contention)
        List<Scheme__c> all = [SELECT Id FROM Scheme__c];
        delete all;

        Test.startTest();
        List<ViewSchemesController.SchemeWrapper> schemes = ViewSchemesController.getAllSchemes();
        Test.stopTest();

        System.assertEquals(0, schemes.size(), 'Empty list expected when no schemes exist');
    }
}