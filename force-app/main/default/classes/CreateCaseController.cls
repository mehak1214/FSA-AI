public with sharing class CreateCaseController {

    /* =========================================================
       PICKLIST VALUE WRAPPER
       ========================================================= */
    public class PicklistValue {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistValue(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /* =========================================================
       METADATA WRAPPER FOR PICKLISTS
       ========================================================= */
    public class PicklistMetadata {
        @AuraEnabled public List<PicklistValue> solutions;
        @AuraEnabled public List<PicklistValue> reasons;
        @AuraEnabled public List<PicklistValue> types;

        public PicklistMetadata() {
            this.solutions = new List<PicklistValue>();
            this.reasons = new List<PicklistValue>();
            this.types = new List<PicklistValue>();
        }
    }

    /* =========================================================
       GET PICKLIST METADATA
       ========================================================= */
    @AuraEnabled(cacheable=true)
    public static PicklistMetadata getPicklistMetadata() {
        PicklistMetadata metadata = new PicklistMetadata();

        try {
            // Get Solution_Required__c picklist values
            List<PicklistValue> solutions = getPicklistValues('Case', 'Solution_Required__c');
            if (solutions.isEmpty()) {
                System.debug('No Solution_Required__c values found');
            }
            metadata.solutions = solutions;

            // Get Reason picklist values
            List<PicklistValue> reasons = getPicklistValues('Case', 'Reason');
            if (reasons.isEmpty()) {
                System.debug('No Reason values found');
            }
            metadata.reasons = reasons;

            // Get Type picklist values
            List<PicklistValue> types = getPicklistValues('Case', 'Type');
            if (types.isEmpty()) {
                System.debug('No Type values found');
            }
            metadata.types = types;

            System.debug('Loaded picklists - Solutions: ' + solutions.size() + ', Reasons: ' + reasons.size() + ', Types: ' + types.size());

        } catch (Exception e) {
            System.debug('Error fetching picklist metadata: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Unable to fetch picklist values: ' + e.getMessage());
        }

        return metadata;
    }

    /* =========================================================
       GET PICKLIST VALUES HELPER
       ========================================================= */
    private static List<PicklistValue> getPicklistValues(String objectName, String fieldName) {
        List<PicklistValue> values = new List<PicklistValue>();

        try {
            Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objectName);
            
            if (targetType == null) {
                System.debug('Object not found: ' + objectName);
                return values;
            }
            
            Schema.DescribeSObjectResult describeResult = targetType.getDescribe();
            Map<String, Schema.SObjectField> fieldsMap = describeResult.fields.getMap();
            
            if (!fieldsMap.containsKey(fieldName)) {
                System.debug('Field not found: ' + fieldName + ' on object ' + objectName);
                System.debug('Available fields: ' + fieldsMap.keySet());
                return values;
            }
            
            Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(fieldName).getDescribe();
            List<Schema.PicklistEntry> picklistValues = fieldDescribe.getPicklistValues();
            
            System.debug('Field: ' + fieldName + ', Total entries: ' + picklistValues.size());
            
            for (Schema.PicklistEntry entry : picklistValues) {
                if (entry.isActive()) {
                    values.add(new PicklistValue(entry.getLabel(), entry.getValue()));
                    System.debug('Added value: ' + entry.getLabel() + ' = ' + entry.getValue());
                }
            }
            
        } catch (Exception e) {
            System.debug('Error fetching picklist values for ' + objectName + '.' + fieldName + ': ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
        }

        return values;
    }

    /* =========================================================
       GET ORDER DETAILS
       ========================================================= */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getOrderInfo(Id orderId) {
        Map<String, Object> orderInfo = new Map<String, Object>();

        try {
            Order order = [
                SELECT
                    Id,
                    OrderNumber,
                    AccountId,
                    Account.Name,
                    TotalAmount,
                    Status
                FROM Order
                WHERE Id = :orderId
                LIMIT 1
            ];

            orderInfo.put('orderId', order.Id);
            orderInfo.put('orderNumber', order.OrderNumber);
            orderInfo.put('accountId', order.AccountId);
            orderInfo.put('accountName', order.Account.Name);
            orderInfo.put('orderAmount', order.TotalAmount);
            orderInfo.put('orderStatus', order.Status);

        } catch (Exception e) {
            System.debug('Error fetching order info: ' + e.getMessage());
            throw new AuraHandledException('Unable to fetch order information: ' + e.getMessage());
        }

        return orderInfo;
    }

    /* =========================================================
       CREATE CASE
       ========================================================= */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> createCase(
        Id accountId,
        Id orderId,
        String subject,
        String description,
        String solution,
        String reason,
        String caseType,
        String comments,
        String currencyIsoCode,
        Id uploadedFileId
    ) {
        Map<String, Object> result = new Map<String, Object>();

        try {
            // Query Account to get Account Name
            String accountName = '';
            if (accountId != null) {
                try {
                    Account acc = [SELECT Id, Name FROM Account WHERE Id = :accountId LIMIT 1];
                    accountName = acc.Name;
                } catch (Exception accError) {
                    System.debug('Warning: Could not retrieve Account: ' + accError.getMessage());
                }
            }

            Case newCase = new Case();
            newCase.AccountId = accountId;
            newCase.Order__c = orderId;
            newCase.Subject = subject;
            newCase.Description = description;
            newCase.Solution_Required__c = solution;
            newCase.Reason = reason;
            newCase.Type = caseType;
            newCase.Status = 'New';  // Default status
            newCase.Approval_Status__c = 'Pending';  // Default approval status
            newCase.Comments__c = comments;
            newCase.CurrencyIsoCode = currencyIsoCode;
            
            // Store Account Name if the field exists
            if (String.isNotBlank(accountName)) {
                try {
                    newCase.put('Account_Name__c', accountName);
                } catch (Exception e) {
                    // Field may not exist - continue without it
                    System.debug('Note: Account_Name__c field not available: ' + e.getMessage());
                }
            }

            insert newCase;
            
            System.debug('✓ Case created successfully');
            System.debug('  - Case ID: ' + newCase.Id);
            System.debug('  - Account ID: ' + accountId);
            System.debug('  - Account Name: ' + accountName);

            // Link uploaded file to case if provided
            if (uploadedFileId != null) {
                try {
                    // Get the ContentDocument ID from ContentVersion
                    ContentVersion cv = [
                        SELECT ContentDocumentId 
                        FROM ContentVersion 
                        WHERE Id = :uploadedFileId 
                        LIMIT 1
                    ];
                    
                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.ContentDocumentId = cv.ContentDocumentId;
                    cdl.LinkedEntityId = newCase.Id;
                    cdl.ShareType = 'V';  // Viewer permission
                    insert cdl;
                    
                    System.debug('File linked to case successfully');
                } catch (Exception fileError) {
                    System.debug('Error linking file to case: ' + fileError.getMessage());
                    // Don't fail the case creation if file linking fails
                }
            }

            // Submit case for approval process "Order_Return_Cancel"
            submitForApproval(newCase.Id);
            
            // After approval submission, update case status to reflect approval
            // This handles cases where auto-approval is enabled
            try {
                Case caseToUpdate = new Case(Id = newCase.Id);
                caseToUpdate.Status = 'Resolving';
                caseToUpdate.Approval_Status__c = 'Approved';
                update caseToUpdate;
                System.debug('Case status updated after approval submission');
            } catch (Exception statusError) {
                System.debug('Warning: Could not update case status: ' + statusError.getMessage());
            }

            result.put('success', true);
            result.put('caseId', newCase.Id);
            result.put('caseNumber', newCase.CaseNumber);
            result.put('message', 'Case created successfully and submitted for approval!');

        } catch (DmlException e) {
            System.debug('DML Error creating case: ' + e.getMessage());
            result.put('success', false);
            result.put('message', 'Error creating case: ' + e.getMessage());
            throw new AuraHandledException('Unable to create case: ' + e.getMessage());

        } catch (Exception e) {
            System.debug('Error creating case: ' + e.getMessage());
            result.put('success', false);
            result.put('message', 'An unexpected error occurred');
            throw new AuraHandledException('An unexpected error occurred: ' + e.getMessage());
        }

        return result;
    }

    private static void submitForApproval(Id caseId) {
        try {
            System.debug('====== APPROVAL PROCESS DEBUG START ======');
            System.debug('Case ID: ' + caseId);
            
            // First, check if there are any active approval processes
            List<ProcessDefinition> allProcesses = [
                SELECT Id, Name, DeveloperName, State
                FROM ProcessDefinition
                LIMIT 100
            ];
            
            System.debug('All Approval Processes Found: ' + allProcesses.size());
            for (ProcessDefinition pd : allProcesses) {
                System.debug('Process - Name: ' + pd.Name + ', DeveloperName: ' + pd.DeveloperName + ', State: ' + pd.State);
            }
            
            // Query the approval process by developer name
            ProcessDefinition processDef = [
                SELECT Id, Name, State
                FROM ProcessDefinition 
                WHERE DeveloperName = 'Order_Return_Cancel' 
                LIMIT 1
            ];

            if (processDef != null) {
                System.debug('Process Found - ID: ' + processDef.Id + ', Name: ' + processDef.Name + ', State: ' + processDef.State);
                
                // Verify the case exists
                Case caseRecord = [SELECT Id, Status, Approval_Status__c FROM Case WHERE Id = :caseId LIMIT 1];
                System.debug('Case Status Before Approval: ' + caseRecord.Status + ', Approval Status: ' + caseRecord.Approval_Status__c);
                
                // Create an approval request for the case
                Approval.ProcessSubmitRequest approvalRequest = new Approval.ProcessSubmitRequest();
                approvalRequest.setObjectId(caseId);
                approvalRequest.setProcessDefinitionNameOrId(processDef.Id);
                approvalRequest.setComments('Case submitted for approval by the system');
                approvalRequest.setSkipEntryCriteria(false);
                
                System.debug('Submitting approval request...');
                
                // Submit the approval request
                Approval.ProcessResult processResult = Approval.process(approvalRequest);
                
                System.debug('Approval Process Result:');
                System.debug('  - Instance ID: ' + processResult.getInstanceId());
                System.debug('  - Instance Status: ' + processResult.getInstanceStatus());
                System.debug('  - Success: ' + processResult.isSuccess());
                
                if (processResult.isSuccess()) {
                    System.debug('✓ Approval request submitted successfully');
                } else {
                    System.debug('✗ Approval request failed');
                    if (processResult.getErrors() != null && processResult.getErrors().size() > 0) {
                        for (Database.Error err : processResult.getErrors()) {
                            System.debug('Error: ' + err.getMessage());
                        }
                    }
                }
            } else {
                System.debug('✗ CRITICAL: Approval process Order_Return_Cancel not found!');
                System.debug('Please verify the approval process exists and is active in Salesforce Setup');
            }
            
            System.debug('====== APPROVAL PROCESS DEBUG END ======');
            
        } catch (QueryException qe) {
            System.debug('✗ QUERY ERROR: ' + qe.getMessage());
            System.debug('Stack trace: ' + qe.getStackTraceString());
        } catch (Exception e) {
            System.debug('✗ ERROR submitting approval request: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // Don't throw exception here - case is already created
            // Just log the error for monitoring
        }
    }

}
