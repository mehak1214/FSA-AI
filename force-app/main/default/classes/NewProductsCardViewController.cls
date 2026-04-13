public with sharing class NewProductsCardViewController {
    
    /**
     * Wrapper class to hold product and image data
     */
    public class ProductWrapper {
        @AuraEnabled
        public String Id { get; set; }
        @AuraEnabled
        public String Name { get; set; }
        @AuraEnabled
        public String ProductCode { get; set; }
        @AuraEnabled
        public String Family { get; set; }
        @AuraEnabled
        public String Description { get; set; }
        @AuraEnabled
        public String imageUrl { get; set; }
    }

    /**
     * Fetch new Product2 records with images where Is_New__c = true
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductWrapper> getNewProducts() {
        try {
            List<ProductWrapper> products = new List<ProductWrapper>();
            
            // Query all new products
            List<Product2> productList = [
                SELECT Id, Name, ProductCode, Family, Description
                FROM Product2
                WHERE Is_New__c = true
                ORDER BY CreatedDate DESC
                LIMIT 100
            ];
            
            // Get all product IDs for bulk query
            Set<Id> productIds = new Set<Id>();
            for (Product2 product : productList) {
                productIds.add(product.Id);
            }
            
            // Query ContentVersion through ContentDocumentLink (modern Salesforce files)
            List<ContentDocumentLink> contentLinks = [
                SELECT ContentDocumentId, LinkedEntityId, ContentDocument.LatestPublishedVersionId
                  FROM ContentDocumentLink
                 WHERE LinkedEntityId IN :productIds
                       AND ContentDocument.FileType IN ('JPG', 'JPEG', 'PNG', 'GIF', 'WEBP')
                 LIMIT 10000
            ];
            
            // Map to store first content version per product
            Map<Id, String> contentVersionByProductId = new Map<Id, String>();
            for (ContentDocumentLink link : contentLinks) {
                if (!contentVersionByProductId.containsKey(link.LinkedEntityId)) {
                    contentVersionByProductId.put(link.LinkedEntityId, link.ContentDocument.LatestPublishedVersionId);
                }
            }
            
            // Query legacy Attachments as fallback
            List<Attachment> allAttachments = [
                SELECT Id, Name, ContentType, ParentId
                  FROM Attachment
                 WHERE ParentId IN :productIds
            ];
            
            // Map attachments by ProductId
            Map<Id, Attachment> attachmentsByProductId = new Map<Id, Attachment>();
            for (Attachment attachment : allAttachments) {
                if (!attachmentsByProductId.containsKey(attachment.ParentId)) {
                    attachmentsByProductId.put(attachment.ParentId, attachment);
                }
            }
            
            // Create wrappers with image URLs
            for (Product2 product : productList) {
                ProductWrapper wrapper = new ProductWrapper();
                wrapper.Id = product.Id;
                wrapper.Name = product.Name;
                wrapper.ProductCode = product.ProductCode;
                wrapper.Family = product.Family;
                wrapper.Description = product.Description;
                
                // Try ContentVersion first (modern approach)
                if (contentVersionByProductId.containsKey(product.Id)) {
                    String contentVersionId = contentVersionByProductId.get(product.Id);
                    wrapper.imageUrl = '/sfc/servlet.shepherd/version/download/' + contentVersionId;
                }
                // Fallback to Attachment if no ContentVersion found
                else if (attachmentsByProductId.containsKey(product.Id)) {
                    Attachment attachment = attachmentsByProductId.get(product.Id);
                    wrapper.imageUrl = '/sfc/servlet.shepherd/attachment/' + attachment.Id;
                }
                
                products.add(wrapper);
            }
            
            return products;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching products: ' + e.getMessage());
        }
    }
}