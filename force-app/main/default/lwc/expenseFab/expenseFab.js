import { LightningElement, track, wire } from 'lwc';
import { publish, subscribe, MessageContext } from 'lightning/messageService';
// Note: CurrentPageReference has been removed as it's unreliable in mobile tabs
import EXPENSE_QUEUED_CHANNEL from '@salesforce/messageChannel/ExpenseQueued__c';
import FAB_CONTROL_CHANNEL    from '@salesforce/messageChannel/FabControl__c';
import { ShowToastEvent }                from 'lightning/platformShowToastEvent';
import {
    enqueue, getStorageStatus,
    getQueueForSync, markSyncing, dequeue, markSyncFailed,
    isSyncInProgress, setSyncInProgress, isOnline
} from 'c/offlineQueueForExpenses';
import createExpense        from '@salesforce/apex/ExpenseController.createExpense';
import attachFilesToExpense from '@salesforce/apex/ExpenseController.attachFilesToExpense';
import getVisitsForDate     from '@salesforce/apex/ExpenseController.getVisitsForDate';

const EXPENSE_TYPES = [
    'Travel', 'Food & Beverages', 'Market Execution Expenses',
    'Communications Expenses', 'Miscellaneous Expenses', 'Other'
];
const EMPTY_FORM = {
    amount: '', expenseType: '',
    expenseDate: new Date().toISOString().slice(0, 10), description: ''
};
const MAX_FILE_SIZE_MB = 5;
const ALLOWED_TYPES    = ['image/jpeg','image/png','image/gif','image/webp',
                          'application/pdf','image/heic','image/heif'];

function fileToBase64(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload  = () => {
            const base64Data = reader.result.split(',')[1];
            resolve({ fileName: file.name, base64Data, mimeType: file.type });
        };
        reader.onerror = () => reject(new Error(`Failed to read ${file.name}`));
        reader.readAsDataURL(file);
    });
}

export default class ExpenseFab extends LightningElement {

    @track isModalOpen   = false;
    @track formData      = { ...EMPTY_FORM };
    @track errors        = {};
    @track isSaving      = false;
    @track attachedFiles = [];

    // Visit linking
    @track availableVisits   = [];
    @track visitsLoading     = false;
    @track visitsLoadError   = false;

    _fabMoved = false;
    _portal   = null;
    
    // Tracking Visibility
    _isHostVisible = true;
    _lmsFabVisible = true;
    _hostObserver = null;

    @wire(MessageContext)
    messageContext;

    // ── Lifecycle ───────────────────────────────────────
    connectedCallback() {
        this._onlineHandler = () => this.syncPendingExpenses();
        window.addEventListener('online', this._onlineHandler);
        
        this._fabControlSub = subscribe(
            this.messageContext,
            FAB_CONTROL_CHANNEL,
            ({ action }) => this._updateFabVisibility(action === 'show')
        );

        // Native Observer to detect tab visibility
        this._hostObserver = new IntersectionObserver((entries) => {
            const entry = entries[0];
            
            // isIntersecting handles both display:none and off-screen translations
            this._isHostVisible = entry.isIntersecting;
            this._applyPortalVisibility();
            
        }, {
            // rootMargin: top right bottom left
            // We expand the vertical detection box by 50,000 pixels up and down.
            // This means scrolling will NEVER cause the element to "leave" the screen vertically.
            // However, the left/right bounds remain strictly at 0px, instantly hiding 
            // the FAB when Salesforce slides the tab off-screen horizontally.
            rootMargin: '50000px 0px 50000px 0px'
        });
    }

    renderedCallback() {
        if (!this._fabMoved) {
            const portal = this.template.querySelector('.fab-portal');
            if (portal) {
                const btn = portal.querySelector('.fab');
                if (btn) btn.addEventListener('click', () => this.openModal());
                document.body.appendChild(portal);
                this._portal   = portal;
                this._fabMoved = true;
            }
            
            // Tell the observer to watch this component's host tag
            if (this.template.host) {
                this._hostObserver.observe(this.template.host);
            }
        }
        this._applyPortalVisibility();
    }

    disconnectedCallback() {
        window.removeEventListener('online', this._onlineHandler);
        if (this._hostObserver) this._hostObserver.disconnect();
        if (this._portal) this._portal.remove();
    }

    // ── FAB & modal ─────────────────────────────────────
    openModal() {
        this.formData        = { ...EMPTY_FORM };
        this.errors          = {};
        this.isSaving        = false;
        this.attachedFiles   = [];
        this.availableVisits = [];
        this.visitsLoadError = false;
        this.isModalOpen     = true;
        this._updateFabVisibility(false);
        this._loadVisitsForDate(this.formData.expenseDate);
    }

    closeModal() {
        this.isModalOpen = false;
        this._updateFabVisibility(true);
    }

    _updateFabVisibility(visible) {
        this._lmsFabVisible = visible;
        this._applyPortalVisibility();
    }

    _applyPortalVisibility() {
        if (!this._portal) return;
        const fab = this._portal.querySelector('.fab');
        if (!fab) return;
        
        // FAB shows ONLY if: 
        // 1. Component is visible on screen (tab is active)
        // 2. The Form Modal isn't blocking it
        // 3. LMS hasn't told it to hide
        const shouldShow = this._isHostVisible && !this.isModalOpen && this._lmsFabVisible;
        
        fab.style.display = shouldShow ? 'flex' : 'none';
    }

    // ── Visit loading ────────────────────────────────────
    async _loadVisitsForDate(dateStr) {
        if (!dateStr) { this.availableVisits = []; return; }
        this.visitsLoading   = true;
        this.visitsLoadError = false;
        try {
            const raw = await getVisitsForDate({ expenseDate: dateStr });
            const prevSelected = new Set(
                this.availableVisits.filter(v => v.selected).map(v => v.id)
            );
            this.availableVisits = (raw || []).map(v => ({
                id        : v.id,
                name      : v.name,
                outletName: v.outletName || '—',
                selected  : prevSelected.has(v.id),
                checkClass: prevSelected.has(v.id) ? 'visit-check visit-check--on' : 'visit-check'
            }));
        } catch (err) {
            console.error('[expenseFab] getVisitsForDate failed:', err);
            this.visitsLoadError = true;
            this.availableVisits = [];
        } finally {
            this.visitsLoading = false;
        }
    }

    // ── Form inputs ─────────────────────────────────────
    get expenseTypeOptions() {
        return EXPENSE_TYPES.map(t => ({
            label: t, value: t, selected: this.formData.expenseType === t
        }));
    }

    handleInput(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;
        this.formData = { ...this.formData, [field]: value };
        if (this.errors[field]) {
            const e = { ...this.errors };
            delete e[field];
            this.errors = e;
        }
        if (field === 'expenseDate') {
            this.availableVisits = [];
            this._loadVisitsForDate(value);
        }
    }

    // ── Visit selection ──────────────────────────────────
    get hasVisits()          { return this.availableVisits.length > 0; }
    get noVisitsForDate()    { return !this.visitsLoading && !this.visitsLoadError && this.availableVisits.length === 0; }
    get selectedVisitIds()   { return this.availableVisits.filter(v => v.selected).map(v => v.id); }
    get selectedVisitCount() { return this.selectedVisitIds.length; }

    handleVisitToggle(event) {
        const id = event.currentTarget.dataset.id;
        this.availableVisits = this.availableVisits.map(v => {
            const selected = v.id === id ? !v.selected : v.selected;
            return { ...v, selected, checkClass: selected ? 'visit-check visit-check--on' : 'visit-check' };
        });
    }

    // ── File handling ────────────────────────────────────
    get hasFiles()  { return this.attachedFiles.length > 0; }
    get fileCount() { return this.attachedFiles.length; }

    triggerFilePicker() {
        if (!this._portal) return;
        if (!isOnline()) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'You\'re Offline',
                message: 'File uploads require an internet connection. Your other expense details will be saved offline.',
                variant: 'warning',
                mode   : 'sticky'
            }));
            return;
        }
        const input = this._portal.querySelector('.file-input');
        if (input) input.click();
    }

    async handleFileChange(event) {
        const files = Array.from(event.target.files);
        if (!files.length) return;

        const tooBig  = files.filter(f => f.size > MAX_FILE_SIZE_MB * 1024 * 1024);
        const badType = files.filter(f => !ALLOWED_TYPES.includes(f.type));
        const valid   = files.filter(f =>
            f.size <= MAX_FILE_SIZE_MB * 1024 * 1024 && ALLOWED_TYPES.includes(f.type)
        );

        if (tooBig.length) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'File Too Large',
                message: `${tooBig.map(f => f.name).join(', ')} exceed${tooBig.length > 1 ? '' : 's'} the ${MAX_FILE_SIZE_MB}MB limit.`,
                variant: 'warning'
            }));
        }
        if (badType.length) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Unsupported File Type',
                message: `${badType.map(f => f.name).join(', ')} — only images and PDFs are allowed.`,
                variant: 'warning'
            }));
        }

        for (const file of valid) {
            try {
                const { fileName, base64Data, mimeType } = await fileToBase64(file);
                const previewUrl = mimeType.startsWith('image/')
                    ? `data:${mimeType};base64,${base64Data}` : null;
                this.attachedFiles = [
                    ...this.attachedFiles,
                    { name: fileName, size: file.size, mimeType, base64Data, previewUrl,
                      id: `f_${Date.now()}_${Math.random()}` }
                ];
            } catch (err) {
                console.error('[expenseFab] File read error:', err);
            }
        }
        event.target.value = '';
    }

    removeFile(event) {
        const id = event.currentTarget.dataset.id;
        this.attachedFiles = this.attachedFiles.filter(f => f.id !== id);
    }

    formatSize(bytes) {
        return bytes >= 1024 * 1024
            ? `${(bytes / 1024 / 1024).toFixed(1)} MB`
            : `${Math.round(bytes / 1024)} KB`;
    }

    get enrichedFiles() {
        return this.attachedFiles.map(f => ({
            ...f,
            formattedSize: this.formatSize(f.size),
            isPdf: f.mimeType === 'application/pdf'
        }));
    }

    // ── Validate & Save ──────────────────────────────────
    validate() {
        const e = {};
        if (!this.formData.amount || Number(this.formData.amount) <= 0)
            e.amount = 'Please enter a valid amount greater than 0.';
        if (!this.formData.expenseType)
            e.expenseType = 'Please select an expense type.';
        if (!this.formData.expenseDate)
            e.expenseDate = 'Please select a date.';
        this.errors = e;
        return Object.keys(e).length === 0;
    }

    async handleSave() {
        if (!this.validate()) return;
        this.isSaving = true;

        const storage = getStorageStatus();
        if (storage.isNearlyFull) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Storage Nearly Full',
                message: `Storage is ${storage.usedPercent}% full. Sync pending expenses soon.`,
                variant: 'warning', mode: 'sticky'
            }));
        }

        const filesPayload   = this.attachedFiles.map(f => ({
            fileName  : f.name,
            base64Data: f.base64Data,
            mimeType  : f.mimeType
        }));
        const hasFiles       = filesPayload.length > 0;
        const selectedVisits = this.selectedVisitIds;

        const expenseData = {
            amount     : parseFloat(this.formData.amount),
            expenseType: this.formData.expenseType,
            expenseDate: this.formData.expenseDate,
            description: this.formData.description,
            visitIds   : selectedVisits
        };

        const result = enqueue({
            amount     : expenseData.amount,
            expenseType: expenseData.expenseType,
            expenseDate: expenseData.expenseDate,
            description: expenseData.description,
            visitIds   : expenseData.visitIds
        });

        if (!result.ok) {
            this.dispatchEvent(new ShowToastEvent({
                title  : result.reason === 'full' ? 'Storage Full' : 'Save Failed',
                message: result.message,
                variant: 'error', mode: 'sticky'
            }));
            this.isSaving = false;
            return;
        }

        this.closeModal();
        publish(this.messageContext, EXPENSE_QUEUED_CHANNEL, { localId: result.localId });

        if (isOnline()) {
            await this._syncAndAttach(result.localId, expenseData, hasFiles ? filesPayload : []);
        } else {
            this.syncPendingExpenses();
            if (hasFiles) {
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'Expense Saved Offline',
                    message: 'Your expense was saved. File attachments could not be uploaded while offline — please re-attach when back online.',
                    variant: 'warning',
                    mode   : 'sticky'
                }));
            }
        }
    }

    async _syncAndAttach(localId, expenseData, filesPayload) {
        if (isSyncInProgress()) {
            await new Promise(r => setTimeout(r, 800));
            if (isSyncInProgress()) {
                if (filesPayload.length > 0) {
                    this.dispatchEvent(new ShowToastEvent({
                        title  : 'Files Not Uploaded',
                        message: 'A sync was already in progress. Your expense was queued but files could not be attached. Please re-attach them once the current sync completes.',
                        variant: 'warning'
                    }));
                }
                return;
            }
        }

        setSyncInProgress(true);
        try {
            const result = await createExpense({
                amount     : expenseData.amount,
                expenseType: expenseData.expenseType,
                expenseDate: expenseData.expenseDate,
                description: expenseData.description,
                visitIds   : expenseData.visitIds || []
            });
            const expenseId = result.expenseId;
            dequeue(localId);

            if (filesPayload.length > 0) {
                await attachFilesToExpense({ expenseId, files: filesPayload });
            }

            publish(this.messageContext, EXPENSE_QUEUED_CHANNEL, { localId: null });

            if (result.hasPolicyWarning) {
                this.dispatchEvent(new ShowToastEvent({
                    title  : '⚠ Policy Limit Exceeded',
                    message: result.warningMessage,
                    variant: 'warning',
                    mode   : 'sticky'
                }));
            }

            this.dispatchEvent(new ShowToastEvent({
                title  : 'Expense Saved',
                message: filesPayload.length > 0
                    ? `Expense saved with ${filesPayload.length} file(s) attached.`
                    : 'Expense saved successfully.',
                variant: 'success'
            }));
        } catch (err) {
            markSyncFailed(localId);
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Save Failed',
                message: err?.body?.message || 'Could not save expense. It has been queued and will retry.',
                variant: 'error'
            }));
        } finally {
            setSyncInProgress(false);
        }
    }

    async syncPendingExpenses() {
        if (!isOnline() || isSyncInProgress()) return;
        setSyncInProgress(true);

        const queue = getQueueForSync();
        let synced = 0, failed = 0;

        for (const item of queue) {
            markSyncing(item.localId);
            try {
                await createExpense({
                    amount     : item.amount,
                    expenseType: item.expenseType,
                    expenseDate: item.expenseDate,
                    description: item.description,
                    visitIds   : item.visitIds || []
                });
                dequeue(item.localId);
                synced++;
            } catch (err) {
                markSyncFailed(item.localId);
                failed++;
                console.error('[expenseFab] Sync failed for', item.localId, err);
            }
        }

        setSyncInProgress(false);

        if (synced > 0) {
            publish(this.messageContext, EXPENSE_QUEUED_CHANNEL, { localId: null });
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Sync Complete',
                message: `${synced} expense(s) saved successfully.`,
                variant: 'success'
            }));
        }
        if (failed > 0) {
            this.dispatchEvent(new ShowToastEvent({
                title  : 'Sync Incomplete',
                message: `${failed} expense(s) could not be saved. Will retry when online.`,
                variant: 'warning'
            }));
        }
    }
}