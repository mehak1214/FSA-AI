public with sharing class ViewSchemesController {

    /* =========================================================
       SCHEME WRAPPER FOR DISPLAY
       ========================================================= */
    public class SchemeWrapper {
        @AuraEnabled public Id schemeId;
        @AuraEnabled public String schemeName;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Decimal discount;
        @AuraEnabled public Decimal thresholdQuantity;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String description;

        public SchemeWrapper(Scheme__c scheme) {
            this.schemeId = scheme.Id;
            this.schemeName = scheme.Scheme_Name__c;
            this.isActive = scheme.Active__c;
            this.discount = scheme.Discount__c;
            this.thresholdQuantity = scheme.Threshold_Quantity__c;
            this.startDate = scheme.Start_Date__c;
            this.endDate = scheme.End_Date__c;
            this.description =scheme.Description__c;
        }
    }

    /* =========================================================
       FETCH ALL SCHEMES SORTED BY ACTIVE STATUS
       ========================================================= */
    @AuraEnabled(cacheable=true)
    public static List<SchemeWrapper> getAllSchemes() {
        System.debug('getAllSchemes() called');
        
        List<SchemeWrapper> schemeWrappers = new List<SchemeWrapper>();
        
        try {
            List<Scheme__c> schemes = [
                SELECT Id, Name, Active__c,scheme_name__c, Discount__c,Description__c, 
                       Threshold_Quantity__c, Start_Date__c, End_Date__c
                FROM Scheme__c
                ORDER BY Active__c DESC NULLS LAST, Name ASC
            ];
            
            for (Scheme__c scheme : schemes) {
                schemeWrappers.add(new SchemeWrapper(scheme));
            }
            
            System.debug('getAllSchemes() returned ' + schemeWrappers.size() + ' schemes');
        } catch (Exception e) {
            System.debug('ERROR in getAllSchemes(): ' + e.getMessage());
            throw new AuraHandledException('Error fetching schemes: ' + e.getMessage());
        }
        
        return schemeWrappers;
    }
}