public without sharing class SchemesController {

    /* =========================================================
       SCHEME WRAPPER CLASS
       ========================================================= */
    public class SchemeWrapper {
        @AuraEnabled public Id schemeId;
        @AuraEnabled public String schemeName;
        @AuraEnabled public Decimal schemeValue;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal thresholdQuantity;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public String color;
        @AuraEnabled public String tileStyle;
        @AuraEnabled public String detailStyle;

        public SchemeWrapper() {}

        public SchemeWrapper(Scheme__c scheme, String schemeColor) {
            this.schemeId = scheme.Id;
            this.schemeName = scheme.Scheme_Name__c;
            this.schemeValue = scheme.Discount__c != null ? scheme.Discount__c : 0;
            this.description = scheme.Description__c;
            this.thresholdQuantity = scheme.Threshold_Quantity__c;
            this.startDate = scheme.Start_Date__c;
            this.endDate = scheme.End_Date__c;
            this.isActive = scheme.Active__c;
            this.color = schemeColor;
            this.tileStyle = 'background-color: ' + schemeColor + ';';
            this.detailStyle = 'background-color: ' + schemeColor + ';';
        }
    }

    /* =========================================================
       GET ALL SCHEMES
       ========================================================= */
    @AuraEnabled(cacheable=false)
    public static List<SchemeWrapper> getAllSchemes() {
        List<SchemeWrapper> schemeWrappers = new List<SchemeWrapper>();
        List<String> colors = new List<String>{
            '#4CAF50', '#2196F3', '#FF9800', '#F44336', '#9C27B0', '#00BCD4'
        };

        try {
            System.debug('=== Starting getAllSchemes ===');
            List<Scheme__c> schemes = [
                SELECT 
                    Id,
                    Scheme_Name__c,
                    Discount__c,
                    Description__c,
                    Threshold_Quantity__c,
                    Start_Date__c,
                    End_Date__c,
                    Active__c
                FROM Scheme__c
                ORDER BY Discount__c DESC
                LIMIT 100
            ];
            
            System.debug('Schemes retrieved: ' + schemes.size());

            Integer colorIndex = 0;
            for (Scheme__c scheme : schemes) {
                String color = colors.get(Math.mod(colorIndex, colors.size()));
                schemeWrappers.add(new SchemeWrapper(scheme, color));
                colorIndex++;
            }
            
            System.debug('Wrapped schemes: ' + schemeWrappers.size());
        } catch (Exception e) {
            System.debug('Error fetching schemes: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Unable to fetch schemes: ' + e.getMessage());
        }

        return schemeWrappers;
    }

    /* =========================================================
       GET FIRST 3 SCHEMES
       ========================================================= */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getSchemesDashboard() {
        Map<String, Object> result = new Map<String, Object>();
        List<SchemeWrapper> topSchemes = new List<SchemeWrapper>();
        List<String> colors = new List<String>{
            '#4CAF50', '#2196F3', '#FF9800', '#F44336', '#9C27B0', '#00BCD4'
        };

        try {
            System.debug('=== Starting getSchemesDashboard ===');
            List<Scheme__c> schemes = [
                SELECT 
                    Id,
                    Scheme_Name__c,
                    Discount__c,
                    Description__c,
                    Threshold_Quantity__c,
                    Start_Date__c,
                    End_Date__c,
                    Active__c
                FROM Scheme__c
                WHERE Active__c = true
                ORDER BY Discount__c DESC
            ];
            
            System.debug('Total schemes found: ' + schemes.size());
            
            Integer totalCount = schemes.size();
            Integer colorIndex = 0;

            // Get top 3 schemes
            for (Integer i = 0; i < Math.min(3, schemes.size()); i++) {
                Scheme__c scheme = schemes.get(i);
                System.debug('Processing scheme: ' + scheme.Scheme_Name__c + ', Discount: ' + scheme.Discount__c);
                String color = colors.get(Math.mod(colorIndex, colors.size()));
                topSchemes.add(new SchemeWrapper(scheme, color));
                colorIndex++;
            }

            result.put('topSchemes', topSchemes);
            result.put('totalCount', totalCount);
            result.put('moreCount', Math.max(0, totalCount - 3));
            
            System.debug('Result: ' + result);

        } catch (Exception e) {
            System.debug('Error fetching schemes dashboard: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Unable to fetch schemes: ' + e.getMessage());
        }

        return result;
    }
}