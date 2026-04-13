public with sharing class ActiveSchemesCardViewController {
    
    /**
     * Wrapper class to hold scheme data
     */
    public class SchemeWrapper {
        @AuraEnabled
        public String Id { get; set; }
        @AuraEnabled
        public String SchemeName { get; set; }
        @AuraEnabled
        public Date StartDate { get; set; }
        @AuraEnabled
        public Date EndDate { get; set; }
        @AuraEnabled
        public Decimal Discount { get; set; }
        @AuraEnabled
        public String Description { get; set; }
    }

    /**
     * Fetch active Scheme records from Scheme__c object
     */
    @AuraEnabled(cacheable=true)
    public static List<SchemeWrapper> getActiveSchemes() {
        try {
            List<SchemeWrapper> schemes = new List<SchemeWrapper>();
            
            // Query all active schemes
            List<Scheme__c> schemeList = [
                SELECT Id, Scheme_Name__c, Start_Date__c, End_Date__c, Discount__c, Description__c
                FROM Scheme__c
                WHERE Active__c = true
                ORDER BY CreatedDate DESC
                LIMIT 100
            ];
            
            // Create wrappers
            for (Scheme__c scheme : schemeList) {
                SchemeWrapper wrapper = new SchemeWrapper();
                wrapper.Id = scheme.Id;
                wrapper.SchemeName = scheme.Scheme_Name__c;
                wrapper.StartDate = scheme.Start_Date__c;
                wrapper.EndDate = scheme.End_Date__c;
                wrapper.Discount = scheme.Discount__c;
                wrapper.Description = scheme.Description__c;
                
                schemes.add(wrapper);
            }
            
            return schemes;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving active schemes: ' + e.getMessage());
        }
    }
}