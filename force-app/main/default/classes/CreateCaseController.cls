public with sharing class CreateCaseController {
    private static final String ORDER_RETURN_CANCEL_DEVELOPER_NAME = 'Order_Return_Cancel';
    private static final String APPROVAL_STATUS_PENDING = 'Pending';

    private class ApprovalSubmissionResult {
        public Boolean success;
        public String message;

        public ApprovalSubmissionResult(Boolean success, String message) {
            this.success = success;
            this.message = message;
        }
    }

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
       GET FILE SIZE
       ========================================================= */
    @AuraEnabled(cacheable=false)
    public static Map<String, Object> getFileSize(Id contentDocumentId) {
        Map<String, Object> fileInfo = new Map<String, Object>();

        try {
            ContentVersion cv = [
                SELECT Id, ContentDocumentId, ContentSize, FileExtension, Title
                FROM ContentVersion 
                WHERE ContentDocumentId = :contentDocumentId 
                AND IsLatest = true
                LIMIT 1
            ];

            fileInfo.put('size', cv.ContentSize);
            fileInfo.put('extension', cv.FileExtension);
            fileInfo.put('title', cv.Title);

            System.debug('File info retrieved: ' + cv.Title + ' (' + cv.ContentSize + ' bytes)');

        } catch (Exception e) {
            System.debug('Error fetching file size: ' + e.getMessage());
            fileInfo.put('size', 0);
        }

        return fileInfo;
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
        Id uploadedFileId,
        String uploadFileBase64,
        String uploadFileName,
        String uploadFileContentType
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

            Id orderReturnCancelRecordTypeId = getCaseRecordTypeId(ORDER_RETURN_CANCEL_DEVELOPER_NAME);
            Case newCase = new Case();
            newCase.AccountId = accountId;
            newCase.Order__c = orderId;
            newCase.Subject = subject;
            newCase.Description = description;
            newCase.Solution_Required__c = solution;
            newCase.Reason = reason;
            newCase.Type = caseType;
            newCase.Status = 'New';  // Default status
            newCase.Approval_Status__c = APPROVAL_STATUS_PENDING;
            newCase.Comments__c = comments;
            newCase.CurrencyIsoCode = currencyIsoCode;
            if (orderReturnCancelRecordTypeId != null) {
                newCase.RecordTypeId = orderReturnCancelRecordTypeId;
            }
            
            // Store Account Name if the field exists
            if (String.isNotBlank(accountName)) {
                try {
                    newCase.put('Account_Name__c', accountName);
                } catch (Exception e) {
                    // Field may not exist - continue without it
                    System.debug('Note: Account_Name__c field not available: ' + e.getMessage());
                }
            }

            // Assign case to Service_Team queue
            Id queueId = getQueueIdByDeveloperName('Service_Team');
            if (queueId != null) {
                newCase.OwnerId = queueId;
            }

            insert newCase;

            System.debug('✓ Case created successfully');
            System.debug('  - Case ID: ' + newCase.Id);
            System.debug('  - Account ID: ' + accountId);
            System.debug('  - Account Name: ' + accountName);
            if (queueId != null) {
                System.debug('  - Assigned to Queue: Service_Team (ID: ' + queueId + ')');
            }

            // Link uploaded file to case if provided
            if (uploadedFileId != null) {
                try {
                    // The uploadedFileId from lightning-file-upload is the ContentDocumentId
                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.ContentDocumentId = uploadedFileId;
                    cdl.LinkedEntityId = newCase.Id;
                    cdl.ShareType = 'V';  // Viewer permission
                    insert cdl;
                    
                    System.debug('✓ File linked to case successfully');
                } catch (Exception fileError) {
                    System.debug('Error linking file to case: ' + fileError.getMessage());
                    System.debug('Stack trace: ' + fileError.getStackTraceString());
                    // Don't fail the case creation if file linking fails
                }
            }

            // Create ContentVersion from uploaded file if provided
            if (String.isNotBlank(uploadFileBase64) && String.isNotBlank(uploadFileName)) {
                try {
                    // Decode base64 to blob
                    Blob fileBlob = EncodingUtil.base64Decode(uploadFileBase64);
                    
                    // Create ContentVersion
                    ContentVersion cv = new ContentVersion();
                    cv.Title = uploadFileName;
                    cv.PathOnClient = uploadFileName;
                    cv.VersionData = fileBlob;
                    cv.IsMajorVersion = true;
                    insert cv;
                    
                    System.debug('✓ File uploaded as ContentVersion: ' + cv.Id);
                    
                    // Get the ContentDocument ID
                    ContentVersion insertedCV = [
                        SELECT ContentDocumentId 
                        FROM ContentVersion 
                        WHERE Id = :cv.Id 
                        LIMIT 1
                    ];
                    
                    // Link file to case
                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.ContentDocumentId = insertedCV.ContentDocumentId;
                    cdl.LinkedEntityId = newCase.Id;
                    cdl.ShareType = 'V';  // Viewer permission
                    insert cdl;
                    
                    System.debug('✓ File linked to case successfully');
                    
                    // Add note about file attachment
                    String fileNote = 'Proof/Product image uploaded and attached. File: ' + uploadFileName;
                    if (String.isNotBlank(newCase.Comments__c)) {
                        newCase.Comments__c = newCase.Comments__c + '\n\n' + fileNote;
                    } else {
                        newCase.Comments__c = fileNote;
                    }
                    update newCase;
                    
                } catch (Exception fileError) {
                    System.debug('Error processing uploaded file: ' + fileError.getMessage());
                    System.debug('Stack trace: ' + fileError.getStackTraceString());
                    // Don't fail case creation if file processing fails
                }
            }

            // Submit case for approval process "Order_Return_Cancel"
            // Wrap in try-catch so approval failures don't fail case creation
            Boolean approvalSubmitted = false;
            String approvalMessage = '';
            try {
                ApprovalSubmissionResult approvalResult = submitForApproval(newCase.Id);
                approvalSubmitted = approvalResult.success;
                approvalMessage = approvalResult.message;
                System.debug('Approval process submitted successfully: ' + approvalSubmitted);
            } catch (Exception approvalError) {
                approvalMessage = approvalError.getMessage();
                System.debug('Warning: Approval process submission failed, but case was created');
                System.debug('Error: ' + approvalError.getMessage());
                // Don't throw - case is already created successfully
                // Approval can be manually triggered later if needed
            }

            // Query the case to get the auto-generated case number
            Case finalCase = [SELECT Id, CaseNumber FROM Case WHERE Id = :newCase.Id LIMIT 1];

            result.put('success', true);
            result.put('caseId', finalCase.Id);
            result.put('caseNumber', finalCase.CaseNumber);
            result.put('approvalSubmitted', approvalSubmitted);
            result.put('approvalMessage', approvalMessage);
            result.put(
                'message',
                approvalSubmitted
                    ? 'Case created successfully and submitted for approval!'
                    : 'Case created successfully, but approval submission did not complete.'
                        + (String.isNotBlank(approvalMessage) ? ' ' + approvalMessage : '')
            );

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

    private static ApprovalSubmissionResult submitForApproval(Id caseId) {
        User submitter;
        try {
            System.debug('====== CASE APPROVAL PROCESS DEBUG START ======');
            System.debug('Case ID: ' + caseId);
            
            // Fetch the case to update approval status
            Case caseRecord = [
                SELECT Id, Status, Approval_Status__c, RecordTypeId
                FROM Case
                WHERE Id = :caseId
                LIMIT 1
            ];
            System.debug('Case before approval - Status: ' + caseRecord.Status + ', Approval_Status__c: ' + caseRecord.Approval_Status__c);
            
            Id orderReturnCancelRecordTypeId = getCaseRecordTypeId(ORDER_RETURN_CANCEL_DEVELOPER_NAME);
            if (orderReturnCancelRecordTypeId != null && caseRecord.RecordTypeId != orderReturnCancelRecordTypeId) {
                caseRecord.RecordTypeId = orderReturnCancelRecordTypeId;
            }

            // Keep the case aligned with the record type's restricted picklist values.
            caseRecord.Approval_Status__c = APPROVAL_STATUS_PENDING;
            caseRecord.Status = 'New';
            update caseRecord;
            System.debug('Case updated with Approval_Status__c = ' + APPROVAL_STATUS_PENDING);
            
            submitter = [SELECT Id, ManagerId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            System.debug('Submitter Info - UserId: ' + submitter.Id + ', ManagerId: ' + submitter.ManagerId);
            
            // Submit for approval
            System.debug('Submitting case ' + caseId + ' for approval...');
            Approval.ProcessSubmitRequest approvalRequest = new Approval.ProcessSubmitRequest();
            approvalRequest.setObjectId(caseId);
            approvalRequest.setComments('Case submitted for approval by the system');
            // Mirror the working Visit flow and let Salesforce choose the active process.
            approvalRequest.setSkipEntryCriteria(false);
            
            Approval.ProcessResult processResult = Approval.process(approvalRequest);
            
            System.debug('Approval Result - Success: ' + processResult.isSuccess() + ', Instance ID: ' + processResult.getInstanceId());
            
            if (processResult.isSuccess()) {
                System.debug('Case submitted for approval successfully');
                System.debug('====== CASE APPROVAL PROCESS DEBUG END ======');
                return new ApprovalSubmissionResult(true, 'Approval submitted successfully.');
            } else {
                System.debug('Approval submission returned false - approval process may not have been triggered');
                String failureMessage = 'Approval submission failed.';
                if (processResult.getErrors() != null && processResult.getErrors().size() > 0) {
                    List<String> messages = new List<String>();
                    for (Database.Error err : processResult.getErrors()) {
                        System.debug('  Error: ' + err.getMessage());
                        messages.add(err.getMessage());
                    }
                    failureMessage = String.join(messages, ' | ');
                }
                System.debug('====== CASE APPROVAL PROCESS DEBUG END ======');
                return new ApprovalSubmissionResult(false, failureMessage);
            }
        } catch (DmlException dmlEx) {
            String statusCode = String.valueOf(dmlEx.getDmlStatusCode(0));
            String dmlMessage = dmlEx.getDmlMessage(0);
            System.debug('DML Exception during approval - StatusCode: ' + statusCode + ', Message: ' + dmlMessage);
            
            // Handle specific approval process errors gracefully
            if (statusCode == 'NO_APPLICABLE_PROCESS') {
                System.debug('NO_APPLICABLE_PROCESS: Entry criteria not met');
                System.debug('Verify: 1) Approval process entry criteria, 2) Submitter Manager is set, 3) Field values match criteria');
                String detailMsg = 'No applicable approval process was found for this case.'
                    + ' Verify the active approval process entry criteria for record type '
                    + ORDER_RETURN_CANCEL_DEVELOPER_NAME
                    + ', and confirm the submitter has a Manager set.'
                    + ' Submitter ManagerId=' + String.valueOf(submitter != null ? submitter.ManagerId : null) + '.';
                System.debug('====== CASE APPROVAL PROCESS DEBUG END (with DML error) ======');
                return new ApprovalSubmissionResult(false, detailMsg);
            }
            
            // Log but don't throw - case is already created
            System.debug('====== CASE APPROVAL PROCESS DEBUG END (with DML error) ======');
            return new ApprovalSubmissionResult(false, dmlMessage);
        } catch (Exception e) {
            System.debug('Exception during approval submission: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            System.debug('====== CASE APPROVAL PROCESS DEBUG END (with error) ======');
            // Don't throw - case is already created successfully
            return new ApprovalSubmissionResult(false, e.getMessage());
        }
    }

    private static Id getCaseRecordTypeId(String developerName) {
        Schema.RecordTypeInfo rtInfo = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get(developerName);
        return rtInfo != null ? rtInfo.getRecordTypeId() : null;
    }

    private static Id getQueueIdByDeveloperName(String queueDeveloperName) {
        try {
            List<Group> queues = [
                SELECT Id
                FROM Group
                WHERE Type = 'Queue' AND DeveloperName = :queueDeveloperName
                LIMIT 1
            ];
            if (!queues.isEmpty()) {
                System.debug('Queue found: ' + queueDeveloperName + ' (ID: ' + queues[0].Id + ')');
                return queues[0].Id;
            } else {
                System.debug('Queue not found: ' + queueDeveloperName);
            }
        } catch (Exception e) {
            System.debug('Error fetching queue ID for ' + queueDeveloperName + ': ' + e.getMessage());
        }
        return null;
    }

}
