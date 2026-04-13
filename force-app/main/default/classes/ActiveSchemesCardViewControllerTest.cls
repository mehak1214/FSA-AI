/**
 * @description Unit tests for ActiveSchemesCardViewController.
 * Tests getActiveSchemes() - returns active scheme wrappers.
 */
@IsTest
private class ActiveSchemesCardViewControllerTest {

    @TestSetup
    static void setup() {
        // Create two active schemes and one inactive scheme
        TestDataFactory.createActiveSchemeWithFlag(5, 10);
        TestDataFactory.createActiveSchemeWithFlag(10, 20);

        // Inactive scheme — set End_Date__c in the past so Active__c formula = false
        Scheme__c inactive = new Scheme__c();
        inactive.Scheme_Name__c         = 'Inactive Scheme';
        inactive.Discount__c            = 5;
        inactive.Threshold_Quantity__c  = 2;
        inactive.Start_Date__c          = Date.today().addDays(-10);
        inactive.End_Date__c            = Date.today().addDays(-1); // ended yesterday → inactive
        insert inactive;
    }

    /* =========================================================
       TEST getActiveSchemes - returns active schemes only
       ========================================================= */
    @IsTest
    static void testGetActiveSchemes_returnsActiveOnly() {
        Test.startTest();
        List<ActiveSchemesCardViewController.SchemeWrapper> schemes =
            ActiveSchemesCardViewController.getActiveSchemes();
        Test.stopTest();

        System.assertNotEquals(null, schemes, 'Schemes list should not be null');
        System.assertEquals(2, schemes.size(), 'Only active schemes should be returned');

        for (ActiveSchemesCardViewController.SchemeWrapper wrapper : schemes) {
            System.assertNotEquals(null, wrapper.Id, 'Scheme Id should be set');
            System.assertNotEquals(null, wrapper.SchemeName, 'Scheme Name should be set');
            System.assertNotEquals(null, wrapper.Discount, 'Discount should be set');
        }
    }

    /* =========================================================
       TEST getActiveSchemes - empty org returns empty list
       ========================================================= */
    @IsTest
    static void testGetActiveSchemes_noActiveSchemes_returnsEmpty() {
        // Delete the active schemes created in setup (schemes with future end date)
        delete [SELECT Id FROM Scheme__c WHERE End_Date__c >= :Date.today()];

        Test.startTest();
        List<ActiveSchemesCardViewController.SchemeWrapper> schemes =
            ActiveSchemesCardViewController.getActiveSchemes();
        Test.stopTest();

        System.assertNotEquals(null, schemes, 'Should return an empty list, not null');
        System.assertEquals(0, schemes.size(), 'No active schemes should be returned');
    }

    /* =========================================================
       TEST getActiveSchemes - wrapper fields are correctly populated
       ========================================================= */
    @IsTest
    static void testGetActiveSchemes_wrapperFieldsPopulated() {
        Scheme__c scheme = [SELECT Id, Scheme_Name__c, Start_Date__c, End_Date__c, Discount__c
                            FROM Scheme__c WHERE Active__c = true LIMIT 1];

        Test.startTest();
        List<ActiveSchemesCardViewController.SchemeWrapper> schemes =
            ActiveSchemesCardViewController.getActiveSchemes();
        Test.stopTest();

        ActiveSchemesCardViewController.SchemeWrapper found = null;
        for (ActiveSchemesCardViewController.SchemeWrapper w : schemes) {
            if (w.Id == scheme.Id) {
                found = w;
                break;
            }
        }

        System.assertNotEquals(null, found, 'Scheme wrapper should be present in result');
        System.assertEquals(scheme.Scheme_Name__c, found.SchemeName, 'Scheme name should match');
        System.assertEquals(scheme.Discount__c, found.Discount, 'Discount should match');
        System.assertEquals(scheme.Start_Date__c, found.StartDate, 'Start date should match');
        System.assertEquals(scheme.End_Date__c, found.EndDate, 'End date should match');
    }
}