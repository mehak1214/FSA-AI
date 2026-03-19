import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPicklistMetadata from '@salesforce/apex/CreateCaseController.getPicklistMetadata';
import getOrderInfo from '@salesforce/apex/CreateCaseController.getOrderInfo';
import getFileSize from '@salesforce/apex/CreateCaseController.getFileSize';
import createCase from '@salesforce/apex/CreateCaseController.createCase';

/**
 * CreateCaseModal - Enhanced LWC Component
 * 
 * Creates support cases from orders with comprehensive validation,
 * error handling, and user feedback.
 * 
 * @version 2.0
 * @author [Your Team]
 * @updated [Current Date]
 */
export default class CreateCaseModal extends LightningElement {

    /* ═══════════════════════════════════════════════════════════
       STATIC CONSTANTS
       ═══════════════════════════════════════════════════════════ */
    
    static MAX_FILE_SIZE = 5 * 1024 * 1024; // 5MB
    static ALLOWED_FILE_TYPES = ['jpg', 'jpeg', 'png', 'gif', 'pdf'];
    static MAX_SUBJECT_LENGTH = 255;
    static MAX_DESCRIPTION_LENGTH = 4000;
    static MAX_COMMENTS_LENGTH = 1000;
    static MIN_SUBJECT_LENGTH = 10;
    static MIN_DESCRIPTION_LENGTH = 20;
    static MAX_RETRY_ATTEMPTS = 3;
    static PICKLIST_CACHE_TTL = 5 * 60 * 1000; // 5 minutes
    
    static PICKLIST_CACHE = {
        data: null,
        timestamp: null
    };

    /* ═══════════════════════════════════════════════════════════
       PUBLIC PROPERTIES
       ═══════════════════════════════════════════════════════════ */
    
    @api orderId;
    @api accountId;
    @api isModalOpen = false;

    /* ═══════════════════════════════════════════════════════════
       TRACKED PROPERTIES - LOADING STATES
       ═══════════════════════════════════════════════════════════ */
    
    @track loadingStates = {
        picklistsLoading: false,
        orderInfoLoading: false,
        caseSubmitting: false,
        fileUploading: false
    };

    /* ═══════════════════════════════════════════════════════════
       TRACKED PROPERTIES - FORM DATA
       ═══════════════════════════════════════════════════════════ */
    
    @track formData = {
        subject: '',
        description: '',
        solution: '',
        reason: '',
        caseType: '',
        comments: '',
        currencyIsoCode: 'USD'
    };

    @track fieldErrors = {
        subject: '',
        description: '',
        reason: '',
        caseType: '',
        solution: ''
    };

    @track charCounts = {
        subject: 0,
        description: 0,
        comments: 0
    };

    /* ═══════════════════════════════════════════════════════════
       TRACKED PROPERTIES - ORDER INFO
       ═══════════════════════════════════════════════════════════ */
    
    @track orderInfo = {
        orderNumber: '',
        accountName: '',
        orderAmount: '',
        orderStatus: '',
        orderId: ''
    };

    /* ═══════════════════════════════════════════════════════════
       TRACKED PROPERTIES - PICKLIST OPTIONS
       ═══════════════════════════════════════════════════════════ */
    
    @track solutionOptions = [];
    @track reasonOptions = [];
    @track typeOptions = [];

    /* ═══════════════════════════════════════════════════════════
       TRACKED PROPERTIES - FILE UPLOAD
       ═══════════════════════════════════════════════════════════ */
    
    @track uploadState = {
        fileName: '',
        fileBase64: null,
        fileSize: 0,
        fileContentType: '',
        uploadError: '',
        isUploading: false,
        contentDocumentId: null,
        isPreUploaded: false
    };



    /* ═══════════════════════════════════════════════════════════
       TRACKED PROPERTIES - ERROR & MODAL STATE
       ═══════════════════════════════════════════════════════════ */
    
    @track errorMessage = '';
    @track errorDetails = {
        message: '',
        code: '',
        details: [],
        timestamp: null,
        isRecoverable: false
    };

    @track modalMetrics = {
        openedAt: null,
        closedAt: null,
        timeSpent: 0,
        formSubmitted: false
    };

    @track attemptCount = 0;
    isSubmitting = false;

    /* ═══════════════════════════════════════════════════════════
       GETTERS
       ═══════════════════════════════════════════════════════════ */

    /**
     * Check if form has all required fields with valid values
     */
    get isFormValid() {
        const hasNoErrors = Object.values(this.fieldErrors).every(error => !error);
        const hasAllFields = this.formData.subject && 
                            this.formData.description && 
                            this.formData.solution && 
                            this.formData.reason && 
                            this.formData.caseType;
        
        return hasNoErrors && hasAllFields;
    }

    /**
     * Determine if submit button should be disabled
     */
    get hasValidationDisabled() {
        return this.loadingStates.caseSubmitting || 
               this.loadingStates.fileUploading || 
               !this.isFormValid;
    }

    /**
     * Check if any async operation is in progress
     */
    get isAnyOperationInProgress() {
        return Object.values(this.loadingStates).some(state => state === true);
    }

    /**
     * Check if form can be submitted
     */
    get canSubmitForm() {
        return this.isFormValid && 
               !this.loadingStates.caseSubmitting &&
               !this.loadingStates.fileUploading;
    }

    /**
     * Get loading spinner visibility (show if any loading state is true)
     */
    get isLoading() {
        return this.loadingStates.picklistsLoading || 
               this.loadingStates.orderInfoLoading;
    }

    /**
     * Get saving state
     */
    get isSaving() {
        return this.loadingStates.caseSubmitting;
    }

    /* ═══════════════════════════════════════════════════════════
       LIFECYCLE HOOKS
       ═══════════════════════════════════════════════════════════ */

    connectedCallback() {
        console.log('CreateCaseModal: Component connected');
        this.loadPicklistMetadata();
        
        // Add keyboard event listener
        document.addEventListener('keydown', this.handleKeyDown.bind(this));
    }

    disconnectedCallback() {
        console.log('CreateCaseModal: Component disconnected');
        
        // Remove keyboard listener
        document.removeEventListener('keydown', this.handleKeyDown.bind(this));
        
        // Log metrics
        if (this.modalMetrics.openedAt) {
            const timeSpent = Date.now() - new Date(this.modalMetrics.openedAt).getTime();
            console.log('Modal Metrics:', {
                timeSpent: `${Math.round(timeSpent / 1000)}s`,
                formSubmitted: this.modalMetrics.formSubmitted,
                orderId: this.orderId
            });
        }
        
        this.resetForm();
    }

    /* ═══════════════════════════════════════════════════════════
       LOAD PICKLIST METADATA
       ═══════════════════════════════════════════════════════════ */

    /**
     * Load picklist metadata with caching
     */
    loadPicklistMetadata() {
        // Check cache first
        if (this.isPicklistCacheValid()) {
            console.log('Using cached picklist data');
            this.applyPicklistData(CreateCaseModal.PICKLIST_CACHE.data);
            return;
        }

        this.loadingStates = { 
            ...this.loadingStates, 
            picklistsLoading: true 
        };

        getPicklistMetadata()
            .then(result => {
                console.log('Picklist metadata loaded:', result);
                
                // Store in cache
                CreateCaseModal.PICKLIST_CACHE = {
                    data: result,
                    timestamp: Date.now()
                };
                
                this.applyPicklistData(result);
                this.loadingStates = { 
                    ...this.loadingStates, 
                    picklistsLoading: false 
                };
            })
            .catch(error => {
                console.error('Error loading picklist metadata:', error);
                this.handleError(
                    'Failed to load form options. Please refresh and try again.',
                    error,
                    true
                );
                this.loadingStates = { 
                    ...this.loadingStates, 
                    picklistsLoading: false 
                };
            });
    }

    /**
     * Check if picklist cache is still valid
     */
    isPicklistCacheValid() {
        if (!CreateCaseModal.PICKLIST_CACHE.data) return false;
        
        const cacheAge = Date.now() - CreateCaseModal.PICKLIST_CACHE.timestamp;
        return cacheAge < CreateCaseModal.PICKLIST_CACHE_TTL;
    }

    /**
     * Apply picklist data from cache or API response
     */
    applyPicklistData(result) {
        const emptyOption = { label: '-- Select --', value: '' };
        
        this.solutionOptions = [
            emptyOption,
            ...(result.solutions || []).map(item => ({
                label: item.label,
                value: item.value
            }))
        ];

        this.reasonOptions = [
            emptyOption,
            ...(result.reasons || []).map(item => ({
                label: item.label,
                value: item.value
            }))
        ];

        this.typeOptions = [
            emptyOption,
            ...(result.types || []).map(item => ({
                label: item.label,
                value: item.value
            }))
        ];

        console.log('Picklist options applied:', {
            solutionCount: this.solutionOptions.length - 1,
            reasonCount: this.reasonOptions.length - 1,
            typeCount: this.typeOptions.length - 1
        });
    }

    /* ═══════════════════════════════════════════════════════════
       OPEN/CLOSE MODAL
       ═══════════════════════════════════════════════════════════ */

    /**
     * Public API to open modal
     */
    @api
    openModal(orderId, accountId) {
        console.log('Opening CreateCaseModal for orderId:', orderId);
        
        this.orderId = orderId;
        this.accountId = accountId;
        this.isModalOpen = true;
        this.attemptCount = 0;
        this.resetForm();
        
        this.modalMetrics = {
            openedAt: new Date().toISOString(),
            closedAt: null,
            timeSpent: 0,
            formSubmitted: false
        };
        
        this.loadOrderInfo();
        
        // Focus on subject field after modal opens
        setTimeout(() => {
            const subjectInput = this.template.querySelector('[id="subject-input"]');
            if (subjectInput) {
                subjectInput.focus();
            }
        }, 100);
    }

    /**
     * Close modal
     */
    closeModal() {
        console.log('Closing CreateCaseModal');
        
        this.modalMetrics.closedAt = new Date().toISOString();
        this.isModalOpen = false;
        this.resetForm();
        
        // Dispatch close event
        this.dispatchEvent(new CustomEvent('modalclosed', {
            detail: this.modalMetrics,
            bubbles: true,
            composed: true
        }));
    }

    /**
     * Handle close button click
     */
    handleCloseModal() {
        if (this.isAnyOperationInProgress) {
            this.showToast(
                'Warning',
                'Please wait for the current operation to complete',
                'warning'
            );
            return;
        }
        
        this.closeModal();
    }

    /* ═══════════════════════════════════════════════════════════
       LOAD ORDER INFO
       ═══════════════════════════════════════════════════════════ */

    /**
     * Load order information
     */
    loadOrderInfo() {
        if (!this.orderId) return;

        this.loadingStates = { 
            ...this.loadingStates, 
            orderInfoLoading: true 
        };

        getOrderInfo({ orderId: this.orderId })
            .then(result => {
                if (!result) {
                    throw new Error('Order not found');
                }

                this.orderInfo = {
                    orderNumber: result.orderNumber || '',
                    accountName: result.accountName || '',
                    orderAmount: result.orderAmount 
                        ? this.formatCurrency(result.orderAmount) 
                        : 'N/A',
                    orderStatus: result.orderStatus || '',
                    orderId: result.orderId || ''
                };

                console.log('Order info loaded:', this.orderInfo.orderNumber);
                this.loadingStates = { 
                    ...this.loadingStates, 
                    orderInfoLoading: false 
                };
            })
            .catch(error => {
                console.error('Error loading order information:', error);
                this.handleError(
                    'Failed to load order details',
                    error,
                    true
                );
                this.loadingStates = { 
                    ...this.loadingStates, 
                    orderInfoLoading: false 
                };
            });
    }

    /* ═══════════════════════════════════════════════════════════
       FORM FIELD HANDLERS - TEXT INPUTS
       ═══════════════════════════════════════════════════════════ */

    /**
     * Handle subject field change with validation
     */
    handleSubjectChange(event) {
        const value = event.target.value;
        this.formData = { ...this.formData, subject: value };
        this.charCounts = { ...this.charCounts, subject: value.length };

        // Validate subject
        if (!value.trim()) {
            this.fieldErrors = { 
                ...this.fieldErrors, 
                subject: 'Subject is required' 
            };
        } else if (value.length < CreateCaseModal.MIN_SUBJECT_LENGTH) {
            this.fieldErrors = { 
                ...this.fieldErrors, 
                subject: `Subject must be at least ${CreateCaseModal.MIN_SUBJECT_LENGTH} characters` 
            };
        } else if (value.length > CreateCaseModal.MAX_SUBJECT_LENGTH) {
            this.fieldErrors = { 
                ...this.fieldErrors, 
                subject: `Subject must not exceed ${CreateCaseModal.MAX_SUBJECT_LENGTH} characters` 
            };
        } else {
            this.fieldErrors = { ...this.fieldErrors, subject: '' };
        }
    }

    /**
     * Handle description field change with validation
     */
    handleDescriptionChange(event) {
        const value = event.target.value;
        this.formData = { ...this.formData, description: value };
        this.charCounts = { ...this.charCounts, description: value.length };

        // Validate description
        if (!value.trim()) {
            this.fieldErrors = { 
                ...this.fieldErrors, 
                description: 'Description is required' 
            };
        } else if (value.length < CreateCaseModal.MIN_DESCRIPTION_LENGTH) {
            this.fieldErrors = { 
                ...this.fieldErrors, 
                description: `Description must be at least ${CreateCaseModal.MIN_DESCRIPTION_LENGTH} characters` 
            };
        } else if (value.length > CreateCaseModal.MAX_DESCRIPTION_LENGTH) {
            this.fieldErrors = { 
                ...this.fieldErrors, 
                description: `Description must not exceed ${CreateCaseModal.MAX_DESCRIPTION_LENGTH} characters` 
            };
        } else {
            this.fieldErrors = { ...this.fieldErrors, description: '' };
        }
    }

    /**
     * Handle comments field change
     */
    handleCommentsChange(event) {
        const value = event.target.value;
        this.formData = { ...this.formData, comments: value };
        this.charCounts = { ...this.charCounts, comments: value.length };
    }

    /* ═══════════════════════════════════════════════════════════
       FORM FIELD HANDLERS - COMBOBOXES
       ═══════════════════════════════════════════════════════════ */

    /**
     * Handle case type selection
     */
    handleCaseTypeChange(event) {
        const value = event.detail.value;
        this.formData = { ...this.formData, caseType: value };
        this.fieldErrors = { 
            ...this.fieldErrors, 
            caseType: value ? '' : 'Case Type is required' 
        };
    }

    /**
     * Handle reason selection
     */
    handleReasonChange(event) {
        const value = event.detail.value;
        this.formData = { ...this.formData, reason: value };
        this.fieldErrors = { 
            ...this.fieldErrors, 
            reason: value ? '' : 'Reason is required' 
        };
    }

    /**
     * Handle solution selection
     */
    handleSolutionChange(event) {
        const value = event.detail.value;
        this.formData = { ...this.formData, solution: value };
        this.fieldErrors = { 
            ...this.fieldErrors, 
            solution: value ? '' : 'Solution Required is required' 
        };
    }

    /* ═══════════════════════════════════════════════════════════
       FILE UPLOAD HANDLERS
       ═══════════════════════════════════════════════════════════ */





    /**
     * Handle file upload from lightning-file-upload component
     */
    handleFileUploadFinished(event) {
        const uploadedFiles = event.detail.files;

        if (!uploadedFiles || uploadedFiles.length === 0) {
            console.warn('No files uploaded');
            return;
        }

        const file = uploadedFiles[0];
        console.log('File uploaded via lightning-file-upload:', {
            name: file.name,
            documentId: file.documentId
        });

        // Query file size from Salesforce
        getFileSize({ contentDocumentId: file.documentId })
            .then(result => {
                const fileSize = result.size 
                    ? this.formatFileSize(result.size)
                    : 'Unknown size';

                // Update upload state with file details
                this.uploadState = {
                    fileName: file.name,
                    fileSize: fileSize,
                    fileBase64: null,  // Not needed for pre-uploaded files
                    fileContentType: 'application/octet-stream',
                    uploadProgress: 100,
                    uploadError: '',
                    isUploading: false,
                    contentDocumentId: file.documentId,  // Store for linking to case
                    isPreUploaded: true  // Flag to indicate file was pre-uploaded
                };

                console.log('File ready for case attachment:', this.uploadState.fileName, `(${fileSize})`);
            })
            .catch(error => {
                console.error('Error getting file size:', error);
                
                // Still set the file even if size fails
                this.uploadState = {
                    fileName: file.name,
                    fileSize: 'Size unavailable',
                    fileBase64: null,
                    fileContentType: 'application/octet-stream',
                    uploadProgress: 100,
                    uploadError: '',
                    isUploading: false,
                    contentDocumentId: file.documentId,
                    isPreUploaded: true
                };
            });
    }

    /**
     * Validate file before upload
     */
    validateFile(file) {
        if (!file) {
            return { isValid: false, error: 'No file provided' };
        }

        // Check size
        if (file.size > CreateCaseModal.MAX_FILE_SIZE) {
            return {
                isValid: false,
                error: `File size must be less than 5MB. Current: ${this.formatFileSize(file.size)}`
            };
        }

        // Check extension
        const extension = file.name.split('.').pop().toLowerCase();
        if (!CreateCaseModal.ALLOWED_FILE_TYPES.includes(extension)) {
            return {
                isValid: false,
                error: `File type not allowed. Allowed types: ${CreateCaseModal.ALLOWED_FILE_TYPES.join(', ')}`
            };
        }

        return { isValid: true };
    }

    /**
     * Clear uploaded file
     */
    handleClearFile() {
        this.uploadState = {
            fileName: '',
            fileBase64: null,
            fileSize: 0,
            fileContentType: '',
            uploadError: '',
            isUploading: false,
            contentDocumentId: null,
            isPreUploaded: false
        };
        this.showToast('Success', 'File removed', 'success');
    }

    /* ═══════════════════════════════════════════════════════════
       FORM SUBMISSION
       ═══════════════════════════════════════════════════════════ */

    /**
     * Handle case creation
     */
    handleSaveCase() {
        // Prevent double submission
        if (this.isSubmitting || this.loadingStates.caseSubmitting) {
            console.warn('Submission already in progress');
            return;
        }

        if (!this.canSubmitForm) {
            this.showToast(
                'Validation Error',
                'Please fill in all required fields correctly',
                'error'
            );
            return;
        }

        this.submitForm();
    }

    /**
     * Submit form to server
     */
    submitForm() {
        this.isSubmitting = true;
        this.loadingStates = { 
            ...this.loadingStates, 
            caseSubmitting: true 
        };

        console.log('Submitting case with data:', {
            orderId: this.orderId,
            accountId: this.accountId,
            subject: this.formData.subject,
            uploadedFileName: this.uploadState.fileName,
            uploadedViaComponent: this.uploadState.isPreUploaded
        });

        createCase({
            accountId: this.accountId,
            orderId: this.orderId,
            subject: this.formData.subject,
            description: this.formData.description,
            solution: this.formData.solution,
            reason: this.formData.reason,
            caseType: this.formData.caseType,
            comments: this.formData.comments,
            currencyIsoCode: this.formData.currencyIsoCode,
            uploadedFileId: this.uploadState.isPreUploaded ? this.uploadState.contentDocumentId : null,
            uploadFileBase64: null,
            uploadFileName: null,
            uploadFileContentType: null
        })
            .then(result => {
                this.handleSubmitSuccess(result);
            })
            .catch(error => {
                this.handleSubmitError(error);
            })
            .finally(() => {
                this.isSubmitting = false;
                this.loadingStates = { 
                    ...this.loadingStates, 
                    caseSubmitting: false 
                };
            });
    }

    /**
     * Handle successful form submission
     */
    handleSubmitSuccess(result) {
        if (result.success) {
            console.log('✓ Case created successfully:', {
                caseId: result.caseId,
                caseNumber: result.caseNumber,
                message: result.message
            });
            
            this.modalMetrics.formSubmitted = true;
            
            // Dispatch event for parent component
            this.dispatchEvent(new CustomEvent('casecreated', {
                detail: {
                    caseId: result.caseId,
                    caseNumber: result.caseNumber,
                    approvalSubmitted: !!result.approvalSubmitted,
                    message: result.message,
                    timestamp: new Date().toISOString()
                },
                bubbles: true,
                composed: true
            }));

            // Delay modal close to show success message
            setTimeout(() => {
                this.closeModal();
            }, 1500);
        } else {
            const errorMsg = result.message || 'Failed to create case';
            this.showToast('Error', errorMsg, 'error');
            this.errorMessage = errorMsg;
        }
    }

    /**
     * Handle form submission error
     */
    handleSubmitError(error) {
        console.error('✗ Case creation failed:', error);
        
        // Determine if error is recoverable
        const isRecoverable = this.isRecoverableError(error);
        
        this.handleError(
            'Failed to create case. Please try again.',
            error,
            isRecoverable
        );

        // Show retry option if recoverable
        if (isRecoverable && this.attemptCount < CreateCaseModal.MAX_RETRY_ATTEMPTS) {
            this.showToast(
                'Error',
                `Attempt ${this.attemptCount + 1} of ${CreateCaseModal.MAX_RETRY_ATTEMPTS}`,
                'error'
            );
        }
    }

    /**
     * Determine if error is recoverable
     */
    isRecoverableError(error) {
        if (!error) return false;
        
        const errorMsg = error.message || '';
        const recoverableKeywords = ['network', 'timeout', 'connection', 'temporary', 'try again'];
        
        return recoverableKeywords.some(keyword => 
            errorMsg.toLowerCase().includes(keyword)
        );
    }

    /* ═══════════════════════════════════════════════════════════
       ERROR HANDLING
       ═══════════════════════════════════════════════════════════ */

    /**
     * Handle errors with categorization and logging
     */
    handleError(message, error, isRecoverable = false) {
        const errorCode = error?.name || 'UNKNOWN_ERROR';
        const errorMessage = error?.message || 'No details available';

        console.error('=== ERROR LOG ===');
        console.error(`Code: ${errorCode}`);
        console.error(`Message: ${message}`);
        console.error(`Details: ${errorMessage}`);
        console.error(`Stack: ${error?.stack}`);

        // Categorize error for user
        let userMessage = message;
        if (errorCode === 'PERMISSION_ERROR') {
            userMessage = 'You do not have permission to create cases. Contact your administrator.';
        } else if (errorCode === 'NETWORK_ERROR' || errorCode === 'TIMEOUT') {
            userMessage = 'Network error. Please check your connection and try again.';
            isRecoverable = true;
        } else if (errorCode === 'VALIDATION_ERROR') {
            userMessage = 'Please review and correct the highlighted fields.';
        }

        this.errorDetails = {
            message: userMessage,
            code: errorCode,
            details: error?.details || [],
            timestamp: new Date().toISOString(),
            isRecoverable: isRecoverable
        };

        // Log error to tracking system
        this.logErrorToTracking(errorCode, message, errorMessage);
        this.errorMessage = userMessage;
        this.showToast('Error', userMessage, 'error');
    }

    /**
     * Log errors for support team analysis
     */
    logErrorToTracking(errorCode, message, details) {
        try {
            const errorLog = {
                component: 'CreateCaseModal',
                errorCode,
                message,
                details,
                userAgent: navigator.userAgent,
                timestamp: new Date().toISOString(),
                orderId: this.orderId,
                accountId: this.accountId
            };
            console.log('ERROR_LOG:', JSON.stringify(errorLog));
            // In production, you would send this to an error tracking service
        } catch (e) {
            console.error('Failed to log error:', e);
        }
    }

    /* ═══════════════════════════════════════════════════════════
       FORM RESET & CLEANUP
       ═══════════════════════════════════════════════════════════ */

    /**
     * Reset form to initial state
     */
    resetForm() {
        this.formData = {
            subject: '',
            description: '',
            solution: '',
            reason: '',
            caseType: '',
            comments: '',
            currencyIsoCode: 'USD'
        };

        this.fieldErrors = {
            subject: '',
            description: '',
            reason: '',
            caseType: '',
            solution: ''
        };

        this.charCounts = {
            subject: 0,
            description: 0,
            comments: 0
        };

        this.errorMessage = '';
        this.uploadState = {
            fileName: '',
            fileId: null,
            fileSize: 0,
            uploadProgress: 0,
            uploadError: '',
            isUploading: false
        };
    }

    /* ═══════════════════════════════════════════════════════════
       KEYBOARD HANDLING
       ═══════════════════════════════════════════════════════════ */

    /**
     * Handle keyboard shortcuts
     */
    handleKeyDown(event) {
        // Close modal on Escape key
        if (event.key === 'Escape' && this.isModalOpen) {
            this.handleCloseModal();
        }

        // Submit form on Ctrl/Cmd + Enter
        if ((event.ctrlKey || event.metaKey) && event.key === 'Enter' && this.isModalOpen) {
            if (this.canSubmitForm) {
                this.handleSaveCase();
            }
        }
    }

    /* ═══════════════════════════════════════════════════════════
       UTILITY METHODS
       ═══════════════════════════════════════════════════════════ */

    /**
     * Format amount as currency
     */
    formatCurrency(amount) {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(amount || 0);
    }

    /**
     * Format bytes to human-readable size
     */
    formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
    }

    /**
     * Show toast notification
     */
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant,
            mode: variant === 'success' ? 'dismissible' : 'sticky'
        }));
    }
}
