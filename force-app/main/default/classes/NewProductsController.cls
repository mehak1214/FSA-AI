public with sharing class NewProductsController {

    /* =========================================================
       PRODUCT WRAPPER CLASS
       ========================================================= */
    public class ProductCardWrapper {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String productDescription;
        @AuraEnabled public String contentVersionId;

        public ProductCardWrapper() {}

        public ProductCardWrapper(Product2 product, String imgUrl, String versionId) {
            this.productId = product.Id;
            this.productName = product.Name;
            this.imageUrl = imgUrl;
            this.productDescription = product.Description;
            this.contentVersionId = versionId;
        }
    }

    /* =========================================================
       GET LATEST NEW PRODUCTS WITH IMAGES
       ========================================================= */
    @AuraEnabled(cacheable=true)
    public static List<ProductCardWrapper> getLatestNewProducts() {
        List<ProductCardWrapper> productWrappers = new List<ProductCardWrapper>();

        try {
            // Query the latest 3 new products
            List<Product2> newProducts = [
                SELECT 
                    Id,
                    Name,
                    Description,
                    CreatedDate
                FROM Product2
                WHERE Is_New__c = true
                ORDER BY CreatedDate DESC
                LIMIT 3
            ];

            if (newProducts.isEmpty()) {
                return productWrappers;
            }

            // Get product IDs for attachment query
            Set<Id> productIds = new Set<Id>();
            for (Product2 product : newProducts) {
                productIds.add(product.Id);
            }

            // Query ContentDocumentLink to get file associations
            Map<Id, String> productImageMap = getProductImages(productIds);

            // Create wrappers with image URLs
            for (Product2 product : newProducts) {
                String versionId = productImageMap.containsKey(product.Id) 
                    ? productImageMap.get(product.Id) 
                    : null;
                productWrappers.add(new ProductCardWrapper(product, versionId, versionId));
            }
        } catch (Exception e) {
            System.debug('Error fetching new products: ' + e.getMessage());
            throw new AuraHandledException('Unable to fetch products: ' + e.getMessage());
        }

        return productWrappers;
    }

    /* =========================================================
       GET PRODUCT IMAGES FROM CONTENT DOCUMENTS
       ========================================================= */
    private static Map<Id, String> getProductImages(Set<Id> productIds) {
        Map<Id, String> imageMap = new Map<Id, String>();

        try {
            // Query ContentDocumentLink to find linked documents
            List<ContentDocumentLink> contentLinks = [
                SELECT 
                    ContentDocumentId,
                    LinkedEntityId,
                    ContentDocument.Title,
                    ContentDocument.FileType
                FROM ContentDocumentLink
                WHERE LinkedEntityId IN :productIds
                AND ContentDocument.FileType IN ('PNG', 'JPG', 'JPEG', 'GIF', 'WEBP')
                ORDER BY ContentDocument.CreatedDate DESC
            ];

            // Build map of product ID to content document ID
            if (!contentLinks.isEmpty()) {
                Set<Id> contentDocIds = new Set<Id>();
                Map<Id, Id> docIdToProductId = new Map<Id, Id>();

                for (ContentDocumentLink link : contentLinks) {
                    contentDocIds.add(link.ContentDocumentId);
                    // Store the first (most recent) image for each product
                    if (!docIdToProductId.containsKey(link.LinkedEntityId)) {
                        docIdToProductId.put(link.LinkedEntityId, link.ContentDocumentId);
                    }
                }

                // Query ContentVersion to get latest version info
                List<ContentVersion> contentVersions = [
                    SELECT 
                        Id,
                        ContentDocumentId,
                        Title,
                        FileType
                    FROM ContentVersion
                    WHERE ContentDocumentId IN :contentDocIds
                    AND IsLatest = true
                ];

                // Map document IDs to version IDs for URL generation
                Map<Id, Id> docToVersionMap = new Map<Id, Id>();
                for (ContentVersion cv : contentVersions) {
                    docToVersionMap.put(cv.ContentDocumentId, cv.Id);
                }

                // Build final image map - return ContentVersion IDs to construct URLs in LWC
                for (Id productId : docIdToProductId.keySet()) {
                    Id docId = docIdToProductId.get(productId);
                    if (docToVersionMap.containsKey(docId)) {
                        Id versionId = docToVersionMap.get(docId);
                        // Return ContentVersion ID - LWC will construct the proper URL
                        imageMap.put(productId, versionId);
                    }
                }
            }
        } catch (Exception e) {
            System.debug('Error fetching product images: ' + e.getMessage());
            // Return map as-is, some products may not have images
        }

        return imageMap;
    }
}