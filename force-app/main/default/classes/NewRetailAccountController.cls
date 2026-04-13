public with sharing class NewRetailAccountController {

    // ─── Wrapper ──────────────────────────────────────────────────────────────

    public class OutletWrapper {
        @AuraEnabled public String shopName;
        @AuraEnabled public String businessType;
        @AuraEnabled public String shopActLicense;
        @AuraEnabled public String billingStreet;
        @AuraEnabled public String billingCity;
        @AuraEnabled public String billingPostalCode;
        @AuraEnabled public String billingState;
        @AuraEnabled public String billingCountry;
        @AuraEnabled public String shippingStreet;
        @AuraEnabled public String shippingCity;
        @AuraEnabled public String shippingPostalCode;
        @AuraEnabled public String shippingState;
        @AuraEnabled public String shippingCountry;
        @AuraEnabled public String ownerSalutation;
        @AuraEnabled public String ownerFirstName;
        @AuraEnabled public String ownerLastName;
        @AuraEnabled public String ownerTitle;
        @AuraEnabled public String ownerPhone;
        @AuraEnabled public String ownerEmail;
        @AuraEnabled public String outletStatus;
        @AuraEnabled public String recordTypeId;
        @AuraEnabled public String locationLatitude;
        @AuraEnabled public String locationLongitude;
        // Edit mode
        @AuraEnabled public String accountId;
    }

    // ─── Create / Update Account ──────────────────────────────────────────────

    @AuraEnabled
    public static String createOutletAccount(String wrapperJson) {
        OutletWrapper w;
        try {
            w = (OutletWrapper) JSON.deserialize(wrapperJson, OutletWrapper.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid data received: ' + e.getMessage());
        }

        if (w == null || String.isBlank(w.shopName)) {
            throw new AuraHandledException('Shop Name is required.');
        }
        if (String.isBlank(w.businessType)) {
            throw new AuraHandledException('Business Type is required.');
        }

        Boolean isEdit = !String.isBlank(w.accountId);
        Account acc;

        if (isEdit) {
            // Load existing record for edit/resubmit
            acc = [
                SELECT Id, OutletStatus__c FROM Account
                WHERE Id = :w.accountId WITH SECURITY_ENFORCED LIMIT 1
            ];
        } else {
            acc = new Account();
        }

        // Determine target status and validate transition via StatusService
        String targetStatus = String.isBlank(w.outletStatus)
            ? AccountStatusService.STATUS_DRAFT
            : w.outletStatus;

        AccountStatusService.validateTransition(
            isEdit ? acc.OutletStatus__c : null,
            targetStatus
        );

        // Map fields
        acc.Name                       = w.shopName.trim();
        acc.Type                       = w.businessType;
        acc.Shop_Act_License_Number__c = w.shopActLicense;
        acc.OutletStatus__c            = targetStatus;
        acc.BillingStreet              = w.billingStreet;
        acc.BillingCity                = w.billingCity;
        acc.BillingPostalCode          = w.billingPostalCode;
        acc.BillingState               = w.billingState;
        acc.BillingCountry             = String.isBlank(w.billingCountry) ? 'India' : w.billingCountry;
        acc.ShippingStreet             = w.shippingStreet;
        acc.ShippingCity               = w.shippingCity;
        acc.ShippingPostalCode         = w.shippingPostalCode;
        acc.ShippingState              = w.shippingState;
        acc.ShippingCountry            = String.isBlank(w.shippingCountry) ? 'India' : w.shippingCountry;
        // Build concatenated display name for Owner_Name__c on Account
        // Format: "Salutation FirstName LastName" (omitting blanks)
        List<String> nameParts = new List<String>();
        if (!String.isBlank(w.ownerSalutation)) nameParts.add(w.ownerSalutation.trim());
        if (!String.isBlank(w.ownerFirstName))  nameParts.add(w.ownerFirstName.trim());
        if (!String.isBlank(w.ownerLastName))   nameParts.add(w.ownerLastName.trim());
        String ownerFullName = nameParts.isEmpty() ? null : String.join(nameParts, ' ');

        acc.Owner_Name__c  = ownerFullName;
        acc.Phone          = w.ownerPhone;
        acc.Owner_Email__c = w.ownerEmail;

        if (!isEdit && !String.isBlank(w.recordTypeId) && Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')) {
            acc.put('RecordTypeId', w.recordTypeId);
        }

        if (!String.isBlank(w.locationLatitude) && !String.isBlank(w.locationLongitude)) {
            acc.Outlet_Location__latitude__s  = Decimal.valueOf(w.locationLatitude);
            acc.Outlet_Location__longitude__s = Decimal.valueOf(w.locationLongitude);
        }

        try {
            if (isEdit) {
                update acc;
            } else {
                insert acc;
            }
        } catch (DmlException e) {
            throw new AuraHandledException('Failed to save account: ' + e.getDmlMessage(0));
        }

        // ── Primary Contact upsert ─────────────────────────────────────────────
        // Create or update a primary Contact whenever at least one owner field
        // is provided. On repeated saves/edits we look for an existing Contact
        // on this Account where Primary_Contact__c = true so we never create
        // duplicate contacts.
        if (!String.isBlank(w.ownerSalutation) || !String.isBlank(w.ownerFirstName) ||
            !String.isBlank(w.ownerLastName)   || !String.isBlank(w.ownerPhone)     ||
            !String.isBlank(w.ownerEmail)) {
            upsertPrimaryContact(acc.Id, w.ownerSalutation, w.ownerFirstName,
                                 w.ownerLastName, w.ownerTitle, w.ownerPhone, w.ownerEmail);
        }

        return acc.Id;
    }

    // ─── Load Account for Edit (Draft / Rejected) ─────────────────────────────

    @AuraEnabled
    public static OutletWrapper getAccountForEdit(Id accountId) {
        String accountFields = 'Id, Name, Type, Shop_Act_License_Number__c, OutletStatus__c,' +
            ' BillingStreet, BillingCity, BillingPostalCode, BillingState, BillingCountry,' +
            ' ShippingStreet, ShippingCity, ShippingPostalCode, ShippingState, ShippingCountry,' +
            ' Owner_Name__c, Phone, Owner_Email__c, Outlet_Location__latitude__s, Outlet_Location__longitude__s';
        if (Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')) {
            accountFields += ', RecordTypeId';
        }
        Account acc = (Account) Database.query(
            'SELECT ' + accountFields +
            ' FROM Account WHERE Id = :accountId LIMIT 1'
        );

        OutletWrapper w      = new OutletWrapper();
        w.accountId          = acc.Id;
        w.shopName           = acc.Name;
        w.businessType       = acc.Type;
        w.shopActLicense     = acc.Shop_Act_License_Number__c;
        w.outletStatus       = acc.OutletStatus__c;
        w.billingStreet      = acc.BillingStreet;
        w.billingCity        = acc.BillingCity;
        w.billingPostalCode  = acc.BillingPostalCode;
        w.billingState       = acc.BillingState;
        w.billingCountry     = String.isBlank(acc.BillingCountry) ? 'India' : acc.BillingCountry;
        w.shippingStreet     = acc.ShippingStreet;
        w.shippingCity       = acc.ShippingCity;
        w.shippingPostalCode = acc.ShippingPostalCode;
        w.shippingState      = acc.ShippingState;
        w.shippingCountry    = String.isBlank(acc.ShippingCountry) ? 'India' : acc.ShippingCountry;
        w.ownerPhone         = acc.Phone;
        w.ownerEmail         = acc.Owner_Email__c;
        w.recordTypeId       = Schema.SObjectType.Account.fields.getMap().containsKey('RecordTypeId')
            ? (String) acc.get('RecordTypeId')
            : null;

        // Populate split owner fields from the primary Contact if one exists
        List<Contact> primaryContacts = [
            SELECT Salutation, FirstName, LastName, Title, Phone, Email
            FROM Contact
            WHERE AccountId          = :accountId
            AND   Primary_Contact__c = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!primaryContacts.isEmpty()) {
            Contact con          = primaryContacts[0];
            w.ownerSalutation    = con.Salutation;
            w.ownerFirstName     = con.FirstName;
            w.ownerLastName      = con.LastName;
            w.ownerTitle         = con.Title;
        }
        if (acc.Outlet_Location__latitude__s != null) {
            w.locationLatitude  = String.valueOf(acc.Outlet_Location__latitude__s);
            w.locationLongitude = String.valueOf(acc.Outlet_Location__longitude__s);
        }
        return w;
    }

    // ─── Upload File ──────────────────────────────────────────────────────────

    @AuraEnabled
    public static void uploadFile(String parentId, String fileName,
                                  String base64Data, String contentType) {
        if (String.isBlank(parentId) || String.isBlank(fileName) || String.isBlank(base64Data)) {
            throw new AuraHandledException('parentId, fileName, and base64Data are required.');
        }

        Blob fileBody;
        try {
            fileBody = EncodingUtil.base64Decode(base64Data);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid base64 data for file: ' + fileName);
        }

        ContentVersion cv = new ContentVersion();
        cv.Title         = fileName;
        cv.PathOnClient  = fileName;
        cv.VersionData   = fileBody;
        cv.IsMajorVersion = true;
        try {
            insert cv;
        } catch (DmlException e) {
            throw new AuraHandledException('File upload failed: ' + e.getDmlMessage(0));
        }

        ContentVersion inserted = [
            SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1
        ];

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = inserted.ContentDocumentId;
        cdl.LinkedEntityId    = parentId;
        cdl.ShareType         = 'V';
        cdl.Visibility        = 'AllUsers';
        try {
            insert cdl;
        } catch (DmlException e) {
            throw new AuraHandledException('Failed to link file to account: ' + e.getDmlMessage(0));
        }
    }

    // ─── Primary Contact Upsert ───────────────────────────────────────────────

    /**
     * Creates or updates the primary Contact linked to an Account.
     * Searches for an existing Contact where Primary_Contact__c = true on
     * this Account. If found, updates it in place; otherwise inserts a new one.
     * This ensures repeated saves (Draft saves, Resubmits) never create
     * duplicate contacts.
     */
    private static void upsertPrimaryContact(Id accountId, String salutation, String firstName,
                                              String lastName, String title, String phone, String email) {

        // LastName is required in Salesforce — use placeholder if blank
        String lastNameSafe = String.isBlank(lastName) ? 'Unknown' : lastName.trim();

        // Look for an existing primary contact on this account
        List<Contact> existing = [
            SELECT Id
            FROM Contact
            WHERE AccountId          = :accountId
            AND   Primary_Contact__c = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Contact con;
        if (!existing.isEmpty()) {
            con = existing[0];                          // update in place
        } else {
            con = new Contact(AccountId = accountId);   // create new
        }

        con.Salutation         = salutation;
        con.FirstName          = String.isBlank(firstName) ? null : firstName.trim();
        con.LastName           = lastNameSafe;
        con.Title              = String.isBlank(title) ? null : title.trim();
        con.Phone              = phone;
        con.Email              = email;
        con.Primary_Contact__c = true;

        try {
            if (con.Id != null) {
                update con;
            } else {
                insert con;
            }
        } catch (DmlException e) {
            throw new AuraHandledException('Failed to save primary contact: ' + e.getDmlMessage(0));
        }
    }
}