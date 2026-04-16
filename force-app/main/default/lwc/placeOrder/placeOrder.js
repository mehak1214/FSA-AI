import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import ORDER_OBJECT from '@salesforce/schema/Order';
import ORDER_TYPE_FIELD from '@salesforce/schema/Order.Type';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

// Apex Imports
import getFranchiseAccounts from '@salesforce/apex/PlaceOrderController.getFranchiseAccounts';
import getDistributorAccounts from '@salesforce/apex/PlaceOrderController.getDistributorAccounts';
import getProductsByDistributor from '@salesforce/apex/PlaceOrderController.getProductsByDistributor';
import getSampleProducts from '@salesforce/apex/PlaceOrderController.getSampleProducts';
import getSchemesByThresholdQuantity from '@salesforce/apex/PlaceOrderController.getSchemesByThresholdQuantity';
import placeOrder from '@salesforce/apex/PlaceOrderController.placeOrder';
import getAccountAddress from '@salesforce/apex/PlaceOrderController.getAccountAddress';

export default class PlaceOrder extends LightningElement {

    // ─── Background scroll lock ───────────────────────────────────────────────
    // Walk up from the host element to find the nearest ancestor that is
    // actually scrollable, then freeze it. This works regardless of which
    // Salesforce shell (LEX, Communities, Mobile) is hosting the modal.
    _lockedEl = null;
    _savedOverflow = '';

    connectedCallback() {
        // Find the closest scrollable ancestor of this component's host node
        const scrollParent = this._getScrollParent(this.template.host);
        if (scrollParent) {
            this._lockedEl      = scrollParent;
            this._savedOverflow = scrollParent.style.overflow;
            scrollParent.style.overflow = 'hidden';
        }
    }

    disconnectedCallback() {
        if (this._lockedEl) {
            this._lockedEl.style.overflow = this._savedOverflow;
            this._lockedEl = null;
        }
    }

    _getScrollParent(el) {
        if (!el) return null;
        let node = el.parentElement;
        while (node && node !== document.body) {
            const { overflow, overflowY } = window.getComputedStyle(node);
            const isScrollable = /(auto|scroll)/.test(overflow + overflowY);
            if (isScrollable && node.scrollHeight > node.clientHeight) {
                return node;
            }
            node = node.parentElement;
        }
        // Fallback to body if no scrollable ancestor found
        return document.body;
    }
    // ─────────────────────────────────────────────────────────────────────────

    _franchiseId;
    @track currentStep = 1; 

    @track address = {
        shippingStreet: '', shippingCity: '', shippingState: '', shippingPostalCode: '', shippingCountry: '',
        billingStreet: '', billingCity: '', billingState: '', billingPostalCode: '', billingCountry: '', contactName:'', phone:''
    };

    @track isBillingSame = false;
    @track addressReady = false; // controls address form mount/remount

    @track payment = {
        amount: 0, mode: 'Cash', cardNumber: '', cardHolder: '', cardExpiry: '', cardType: '', upiId: ''
    };

    @track sampleProducts = [];
    @track regularProducts = [];
    @track franchiseOptions = [];
    @track distributorOptions = [];
    @track availableSchemes = [];
    @track orderTypeOptions = [];
    @track selectedOrderType = 'Sample Order';
    @track selectedFranchise;
    @track selectedDistributor;
    @track selectedSchemeId = null;
    @track isSavingOrder = false;

    @track isCartModalOpen = false;
    @track isCartButtonHidden = false;
    @track showCartRemoveBtn = false;
    @track cartLongPressTimer = null;
    @track calculatedDiscountAmount = 0;   // NEW - Total discount amount
    @track payableAmount = 0;               // NEW - Payable amount (editable by user)

    paymentModes = [{ label: 'Cash', value: 'Cash' }, { label: 'UPI', value: 'UPI' }, { label: 'Card', value: 'Card' }];
    cardOptions = [{ label: 'Visa', value: 'Visa' }, { label: 'MasterCard', value: 'MasterCard' }, { label: 'RuPay', value: 'RuPay'}];

    @api
    get franchiseId() { return this._franchiseId; }
    set franchiseId(value) {
        this._franchiseId = value;
        if (value) { this.selectedFranchise = value; }
    }

    @api visitId;

    /**
     * Called by the parent dialog when it opens, so re-opening after a
     * completed order always starts at step 1 with a clean slate.
     */
    @api
    reset() {
        this.currentStep      = 1;
        this.selectedOrderType = undefined;
        this.selectedDistributor = undefined;
        this.selectedSchemeId = null;
        this.addressReady = false;
        this.address = {
            shippingStreet: '', shippingCity: '', shippingState: '',
            shippingPostalCode: '', shippingCountry: '',
            billingStreet: '', billingCity: '', billingState: '',
            billingPostalCode: '', billingCountry: '',
            contactName: '', phone: ''
        };
        this.payment = {
            amount: 0, mode: 'Cash', cardNumber: '',
            cardHolder: '', cardExpiry: '', cardType: '', upiId: ''
        };
        this.isBillingSame = false;
        // Reset product quantities to 0 so the grid looks fresh
        this.sampleProducts  = this.sampleProducts.map(p  => ({ ...p, quantity: 0 }));
        this.regularProducts = this.regularProducts.map(p => ({ ...p, quantity: 0 }));
    }

    get stepOne() { return this.currentStep === 1; }
    get stepTwo() { return this.currentStep === 2; }
    // For Sample Orders, stepThree (payment) is skipped; step 3 maps directly to success
    get stepThree() { return this.currentStep === 3 && !this.isSampleOrder; }
    get stepFour() { return this.isSampleOrder ? this.currentStep === 3 : this.currentStep === 4; }
    // Show Place Order on stepTwo for Sample Orders, stepThree for Regular Orders
    get showPlaceOrder() { return (this.isSampleOrder && this.currentStep === 2) || (!this.isSampleOrder && this.currentStep === 3); }
    get showNextButton() { return !this.showPlaceOrder && !this.stepFour; }

    get isCard() { return this.payment.mode === 'Card'; }
    get isUPI() { return this.payment.mode === 'UPI'; }
    get isFranchiseLocked() { return !!this.franchiseId; }

    // ─── UI-only getters for checkout-style redesign ──────────────────────

    // Nav step CSS classes
    _navStepCls(n) {
        const cur = this.currentStep;
        if (cur > n) return 'step-item step-done';
        if (cur === n) return 'step-item step-active';
        return 'step-item step-pending';
    }
    get step1NavClass()       { return this._navStepCls(1); }
    get step2NavClass()       { return this._navStepCls(2); }
    get step3NavClass()       { return this._navStepCls(3); }
    get confirmStepNavClass() {
        const n = this.isSampleOrder ? 3 : 4;
        return this._navStepCls(n);
    }
    get confirmStepNum() { return this.isSampleOrder ? '3' : '4'; }

    // Product card class (highlights cards that have qty > 0)
    get displayedProducts() {
        return this.currentProducts.map(p => {
            let stockLabel = null;
            let stockLabelClass = 'stock-label';
            if (this.isSampleOrder) {
                const stock = p.quantityOnHand;
                if (stock != null && stock > 0) {
                    stockLabel = `${stock} in stock`;
                    stockLabelClass = 'stock-label stock-available';
                } else {
                    stockLabel = 'Out of stock';
                    stockLabelClass = 'stock-label stock-out';
                }
            }
            return {
                ...p,
                stockLabel,
                stockLabelClass,
                cardClass: p.quantity > 0 ? 'product-card has-qty' : 'product-card'
            };
        });
    }

    // Payment card / radio classes for the styled payment selector
    get cashCardClass() { return this.payment.mode === 'Cash' ? 'pm-card pm-selected' : 'pm-card'; }
    get upiCardClass()  { return this.payment.mode === 'UPI'  ? 'pm-card pm-selected' : 'pm-card'; }
    get cardCardClass() { return this.payment.mode === 'Card' ? 'pm-card pm-selected' : 'pm-card'; }
    get cashRadioClass() { return this.payment.mode === 'Cash' ? 'pm-radio pm-radio-on' : 'pm-radio'; }
    get upiRadioClass()  { return this.payment.mode === 'UPI'  ? 'pm-radio pm-radio-on' : 'pm-radio'; }
    get cardRadioClass() { return this.payment.mode === 'Card' ? 'pm-radio pm-radio-on' : 'pm-radio'; }

    // Payment method click handlers (replaces lightning-combobox for payment)
    selectCash() { this.payment = { ...this.payment, mode: 'Cash' }; }
    selectUPI()  { this.payment = { ...this.payment, mode: 'UPI' };  }
    selectCard() { this.payment = { ...this.payment, mode: 'Card' }; }

    // Whether any products are selected (for side-panel hint)
    get hasSelectedItems() { return this.selectedItemsForSummary.length > 0; }

    // Success screen text
    get successTitle()    { return this.isSampleOrder ? 'Sample Order Placed !' : 'Order Placed Successfully!'; }
    get successSubtitle() { return this.isSampleOrder ? 'Your order is confirmed and being processed.' : 'Your order is confirmed and being processed.'; }

    @wire(getObjectInfo, { objectApiName: ORDER_OBJECT })
    orderObjectInfo;

    @wire(getPicklistValues, { recordTypeId: '$orderObjectInfo.data.defaultRecordTypeId', fieldApiName: ORDER_TYPE_FIELD })
    wiredOrderTypes({ data }) {
        if (data) this.orderTypeOptions = data.values.map(v => ({ label: v.label, value: v.value }));
    }

    @wire(getFranchiseAccounts)
    wiredFranchises({ data }) {
        if (data) {
            this.franchiseOptions = data.map(acc => ({ label: acc.Name, value: acc.Id }));
            if (this.franchiseId) { this.selectedFranchise = this.franchiseId; }
        }
    }

    @wire(getDistributorAccounts)
    wiredDistributors({ data }) {
        if (data) this.distributorOptions = data.map(acc => ({ label: acc.Name, value: acc.Id }));
    }

    @wire(getProductsByDistributor, { distributorId: '$selectedDistributor' })
    wiredProductsResult(result) {
        this._wiredProductsResult = result;
        const { data } = result;
        if (data) {
            const normalizedProducts = data.map(p => ({
                ...p,
                quantity: 0,
                unitPrice: p.unitPrice || 0,
                totalSampleQuantity: p.totalSampleQuantity,
            }));
            this.regularProducts = normalizedProducts.filter(p => p.isSample !== true);
        } else {
            this.regularProducts = [];
        }
    }

    handleNext() {
        if (this.currentStep === 1) {
            const selectedItems = this.currentProducts.filter(p => p.quantity > 0);
            if (!this.selectedFranchise || selectedItems.length === 0) {
                this.showToast('Error', 'Ensure franchise is selected and products are added', 'error');
                return;
            }
            this.addressReady = false; // unmount address form before fetch
            getAccountAddress({ accountId: this.selectedFranchise })
                .then(result => {
                    // Normalize nulls to empty strings so lightning-input
                    // fields reliably update when the address object is replaced.
                    const toStr = v => (v == null ? '' : v);
                    // Strip all characters except digits and leading '+' so the
                    // phone value is valid for Salesforce phone fields (no hyphens,
                    // spaces, parentheses, etc. from the Contact record).
                    const sanitizePhone = v => {
                        if (!v) return '';
                        const cleaned = String(v).replace(/[^\d+]/g, '');
                        return cleaned.startsWith('+')
                            ? '+' + cleaned.slice(1).replace(/\D/g, '')
                            : cleaned;
                    };
                    if (result) {
                        this.address = {
                            shippingStreet:     toStr(result.shippingStreet),
                            shippingCity:       toStr(result.shippingCity),
                            shippingState:      toStr(result.shippingState),
                            shippingPostalCode: toStr(result.shippingPostalCode),
                            shippingCountry:    toStr(result.shippingCountry),
                            billingStreet:      toStr(result.billingStreet),
                            billingCity:        toStr(result.billingCity),
                            billingState:       toStr(result.billingState),
                            billingPostalCode:  toStr(result.billingPostalCode),
                            billingCountry:     toStr(result.billingCountry),
                            contactName:        toStr(result.contactName),
                            phone:              sanitizePhone(result.phone)
                        };
                        if (!result.billingStreet) {
                            this.isBillingSame = true;
                            this.handleSameAddress({ target: { checked: true } });
                        }
                    }
                    // Advance to step 2 and remount address form AFTER data is set,
                    // so lightning-input fields render fresh with the fetched values.
                    this.currentStep = 2;
                    this.addressReady = true;
                })
                .catch(() => {
                    this.currentStep = 2;
                    this.addressReady = true;
                });
        } else if (this.currentStep === 2 && !this.isSampleOrder) {
            // Regular Order: proceed to payment step
            // Initialize payable amount to grand total if not set
            if (this.payableAmount === 0) {
                this.payableAmount = parseFloat(this.computedTotalPriceDisplay) || 0;
            }
            // Also update payment.amount to grand total
            this.payment.amount = parseFloat(this.computedTotalPriceDisplay) || 0;
            this.currentStep = 3;
        }
    }

    handlePrev() {
        this.currentStep -= 1;
        // Reset cart state when going back to ensure cart button is visible
        this.isCartButtonHidden = false;
        this.isCartModalOpen = false;
        this.showCartRemoveBtn = false;
    }

    handleOrderTypeChange(event) {
        this.selectedOrderType = event.detail.value;
        if (!this.selectedOrderType) {
            this.selectedDistributor = null;
        }
        // When Sample Order is selected, load sample products immediately (no distributor needed)
        if (this.selectedOrderType === 'Sample Order' && this.selectedFranchise) {
            this.loadSampleProducts();
        }
    }

    loadSampleProducts() {
        getSampleProducts({ franchiseId: this.selectedFranchise })
            .then(data => {
                this.sampleProducts = data.map(p => ({
                    ...p,
                    quantity: 0,
                    quantityOnHand: p.quantityOnHand,
                    sampleOrderLimit: p.sampleOrderLimit,
                    alreadyOrderedQty: p.alreadyOrderedQty || 0
                }));
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Failed to load sample products', 'error');
            });
    }
    handleFranchiseChange(event) {
        if (!this.isFranchiseLocked) {
            this.selectedFranchise = event.detail.value;
            if (this.selectedOrderType === 'Sample Order') {
                this.loadSampleProducts();
            }
        }
    }
    handleDistributorChange(event) {
        this.selectedDistributor = event.detail.value;
        // Reset cart state when distributor changes
        this.isCartButtonHidden = false;
        this.isCartModalOpen = false;
        this.showCartRemoveBtn = false;
    }

    handleAddressChange(event) {
        const field = event.target.name;
        this.address[field] = event.target.value;
        if (this.isBillingSame && field.startsWith('shipping')) {
            this.address[field.replace('shipping', 'billing')] = event.target.value;
        }
    }

    handleSameAddress(event) {
        this.isBillingSame = event.target.checked;
        if (this.isBillingSame) {
            this.address.billingStreet = this.address.shippingStreet;
            this.address.billingCity = this.address.shippingCity;
            this.address.billingState = this.address.shippingState;
            this.address.billingPostalCode = this.address.shippingPostalCode;
            this.address.billingCountry = this.address.shippingCountry;
        }
    }

    handlePaymentChange(event) { this.payment[event.target.name] = event.target.value; }
    
    handlePayableAmountChange(event) {
        const inputValue = event.target.value;
        
        // Handle empty/cleared field
        if (inputValue === '' || inputValue == null) {
            this.payableAmount = 0;
            this.payment.amount = 0;
            return;
        }
        
        let newAmount = parseFloat(inputValue) || 0;
        const grandTotal = parseFloat(this.computedTotalPriceDisplay) || 0;
        
        // Prevent negative amounts
        if (newAmount < 0) {
            this.showToast('Invalid Amount', 'Payable amount cannot be negative.', 'warning');
            this.payableAmount = 0;
            this.payment.amount = 0;
            return;
        }
        
        // Validation: Prevent amount > grand total (Option A)
        if (newAmount > grandTotal) {
            this.showToast(
                'Amount Limit',
                `Payable amount cannot exceed Grand Total of ₹${grandTotal.toFixed(2)}. Please enter a valid amount.`,
                'warning'
            );
            // Reset to grand total
            this.payableAmount = grandTotal;
            this.payment.amount = grandTotal;
            return;
        }
        
        // Set the validated amount
        this.payableAmount = newAmount;
        this.payment.amount = newAmount;  // Keep payment.amount in sync
    }
    
    // if(computedTotalPriceDisplay) }
    // handleSummarySchemeChange(event) { this.selectedSchemeId = event.detail.value; }

    handleSummarySchemeChange(event) {
    this.selectedSchemeId = event.detail.value;

    if (this.selectedSchemeId) {
        const selectedScheme = this.availableSchemes.find(s => s.value === this.selectedSchemeId);
        if (selectedScheme) {
            const discountPercent = selectedScheme.discount || 0;
            this.calculatedDiscountAmount = this.selectedItemsForSummary.reduce((sum, item) => {
                return sum + ((item.lineTotal || 0) * (discountPercent / 100));
            }, 0);
        }
    } else {
        this.calculatedDiscountAmount = 0;
    }
}

    // Unified Quantity Logic
    handleSummaryQtyChange(event) {
        const productId = event.target.dataset.id;
        const newQty = parseInt(event.target.value, 10);
        this.updateQtyValue(productId, isNaN(newQty) ? 0 : newQty);
    }

    increaseQty(event) { this.updateQtyValue(event.target.dataset.id, 'inc'); }
    decreaseQty(event) { this.updateQtyValue(event.target.dataset.id, 'dec'); }

    updateQtyValue(productId, actionOrValue) {
        const updatedProducts = this.currentProducts.map(p => {
            if (p.productId === productId) {
                let qty = p.quantity;
                if (actionOrValue === 'inc') qty++;
                else if (actionOrValue === 'dec') qty--;
                else qty = actionOrValue;

                if (qty < 0) qty = 0;

                // Sample order validations
                if (this.selectedOrderType === 'Sample Order') {
                    // Cannot exceed available stock (from ProductItem.QuantityOnHand)
                    const stock = p.quantityOnHand != null ? p.quantityOnHand : null;
                    if (stock !== null && qty > stock) {
                        this.showToast('Stock Limit', `Only ${stock} unit(s) available in stock for "${p.productName}".`, 'warning');
                        qty = stock;
                    }
                    // Cannot exceed the remaining sample order limit for this franchise
                    const limit = p.sampleOrderLimit != null ? p.sampleOrderLimit : null;
                    if (limit !== null) {
                        const alreadyOrdered = p.alreadyOrderedQty || 0;
                        const remaining = limit - alreadyOrdered;
                        if (remaining <= 0) {
                            this.showToast('Order Limit Reached', `The sample order limit for "${p.productName}" has already been reached for this account.`, 'warning');
                            qty = 0;
                        } else if (qty > remaining) {
                            this.showToast('Order Limit', `You can only order ${remaining} more unit(s) of "${p.productName}" as a sample (limit: ${limit}, already ordered: ${alreadyOrdered}).`, 'warning');
                            qty = remaining;
                        }
                    }
                }

                return { ...p, quantity: qty };
            }
            return p;
        });
        this.setCurrentProducts(updatedProducts);
        this.updateAvailableSchemes();
    }

    updateAvailableSchemes() {
        const totalQty = this.currentProducts.reduce((sum, p) => sum + (parseInt(p.quantity, 10) || 0), 0);
        if (totalQty === 0) {
            this.availableSchemes = [];
            this.selectedSchemeId = null;
            return;
        }
        getSchemesByThresholdQuantity({ thresholdQuantity: totalQty })
            .then((result) => {
                this.availableSchemes = result.map(scheme => ({
                    label: scheme.label + ' (' + scheme.discount + '% off)',
                    value: scheme.value,
                    discount: scheme.discount
                }));
                if (!this.availableSchemes.length) {
                    // No schemes qualify for this qty — clear selection
                    this.selectedSchemeId = null;
                } else {
                    // Keep the current selection only if it still exists in the
                    // updated list (e.g. user manually picked a scheme earlier).
                    // Otherwise auto-select the first (best) available scheme.
                    const stillValid = this.availableSchemes.some(s => s.value === this.selectedSchemeId);
                    if (!stillValid) {
                        this.selectedSchemeId = this.availableSchemes[0].value;
                    }
                }
            });
    }

    orderAmt;

    saveOrder() {
        if (this.isSavingOrder) {
            return;
        }

        const selectedItems = this.currentProducts.filter(p => p.quantity > 0).map(p => ({
            productId: p.productId, productName: p.productName, quantity: parseInt(p.quantity, 10), unitPrice: p.unitPrice, productItemId: p.productItemId || null
        }));

        if (!selectedItems.length) {
            this.showToast('Error', 'Please select at least one product before placing the order.', 'error');
            return;
        }

        this.orderAmt = this.computedTotalPriceDisplay;
        
        // For Regular Orders, ensure payment data has both grand total and payable amount
        if (!this.isSampleOrder) {
            this.payment.amount = parseFloat(this.computedTotalPriceDisplay) || 0;  // Grand Total
            this.payment.paidAmount = this.payableAmount;  // Payable Amount (user entered)
        }
        
        this.isSavingOrder = true;

        placeOrder({
            franchiseId: this.selectedFranchise,
            distributorId: this.selectedDistributor,
            orderType: this.selectedOrderType,
            selectedProducts: selectedItems,
            selectedSchemeId: this.selectedSchemeId ? String(this.selectedSchemeId) : null,
            addressData: this.address,
            paymentData: this.payment,
            visitId: this.visitId || null,
            discountAmount: this.calculatedDiscountAmount || 0,      // NEW
            appliedSchemeId: this.selectedSchemeId || null           // NEW
        })
        .then((result) => {
            // For Sample Orders, success is currentStep=3; for Regular Orders, currentStep=4
            this.currentStep = this.isSampleOrder ? 3 : 4;

            // Optimistically update local stock and alreadyOrderedQty so the
            // product grid is accurate immediately if the user starts a new order.
            if (this.selectedOrderType === 'Sample Order') {
                const orderedQtyById = {};
                selectedItems.forEach(item => { orderedQtyById[item.productId] = item.quantity; });

                this.sampleProducts = this.sampleProducts.map(p => {
                    const ordered = orderedQtyById[p.productId] || 0;
                    if (ordered > 0) {
                        const currentStock = p.quantityOnHand != null ? p.quantityOnHand : 0;
                        const newStock = Math.max(0, currentStock - ordered);
                        const newAlreadyOrdered = (p.alreadyOrderedQty || 0) + ordered;
                        return { ...p, quantity: 0, quantityOnHand: newStock, alreadyOrderedQty: newAlreadyOrdered };
                    }
                    return { ...p, quantity: 0 };
                });
            } else {
                this.setCurrentProducts(this.currentProducts.map(p => ({ ...p, quantity: 0 })));
            }

            // Also force a server-side cache refresh so subsequent wire calls get fresh data
            refreshApex(this._wiredProductsResult);

            this.dispatchEvent(new CustomEvent('ordercreated', {
                detail: {
                    orderId: result,
                    orderType: this.selectedOrderType
                },
                bubbles: true,
                composed: true
            }));
        })
        .catch(error => this.showToast('Error', error.body?.message || 'Error', 'error'))
        .finally(() => {
            this.isSavingOrder = false;
        });
    }

    get selectedItemsForSummary() {
        const isSample = this.isSampleOrder;
        return this.currentProducts.filter(p => p.quantity > 0).map(p => {
            const qty = parseInt(p.quantity, 10) || 0;
            const unit = parseFloat(p.unitPrice) || 0;
            let disc = 0;
            if (this.selectedSchemeId) {
                const s = this.availableSchemes.find(x => x.value === this.selectedSchemeId);
                if (s) disc = parseFloat(s.discount) || 0;
            }
            const dAmt = qty * unit * (disc / 100);
            return {
                ...p,
                summaryRowClass: isSample ? 'summary-row summary-row-sample' : 'summary-row',
                unitPriceDisplay: unit.toFixed(2),
                lineTotalDisplay: (qty * unit).toFixed(2),
                discountAmountDisplay: dAmt.toFixed(2),
                discountedTotalDisplay: ((qty * unit) - dAmt).toFixed(2),
                discountedTotal: (qty * unit) - dAmt,
                lineTotal: qty * unit,
                discountAmount: dAmt
            };
        });
    }

    get selectedItemsSubtotalDisplay() { return this.selectedItemsForSummary.reduce((s, i) => s + i.lineTotal, 0).toFixed(2); }
    get selectedItemsTotalDiscountDisplay() { return this.selectedItemsForSummary.reduce((s, i) => s + i.discountAmount, 0).toFixed(2); }
    get computedTotalPriceDisplay() { return this.selectedItemsForSummary.reduce((s, i) => s + i.discountedTotal, 0).toFixed(2); }
    
    // NEW GETTERS FOR PAYMENT LOGIC
    get grandTotal() { return parseFloat(this.computedTotalPriceDisplay) || 0; }
    
    get outstandingAmount() {
        if (this.payableAmount < this.grandTotal) {
            return (this.grandTotal - this.payableAmount).toFixed(2);
        }
        return '0.00';
    }
    
    get displayPaymentStatus() {
        if (this.payableAmount > 0 && this.payableAmount < this.grandTotal) {
            return 'Partially Paid';
        } else if (this.payableAmount >= this.grandTotal && this.payableAmount > 0) {
            return 'Paid';
        }
        return 'Pending';
    }
    
    get payableAmountDisplay() {
        return this.payableAmount.toFixed(2);
    }
    get currentProducts() {
        if (this.selectedOrderType === 'Sample Order') return this.sampleProducts;
        if (this.selectedOrderType === 'Regular Order') return this.regularProducts;
        return [];
    }


    get isSampleOrder() {
        return this.selectedOrderType === 'Sample Order';
    }

    get isRegularOrder() {
        return this.selectedOrderType === 'Regular Order';
    }

    get shouldShowSelectProducts() {
        // Show products section if:
        // 1. Sample Order is selected, OR
        // 2. Regular Order is selected AND a distributor is chosen
        if (this.isSampleOrder) return true;
        if (this.isRegularOrder && this.selectedDistributor) return true;
        return false;
    }

    get canGoBack() {
        return this.currentStep > 1;
    }

    get canProceedNext() {
        return this.hasSelectedItems;
    }

    get isBackButtonDisabled() {
        return !this.canGoBack || this.isSavingOrder;
    }

    get isNextButtonDisabled() {
        return !this.canProceedNext || this.isSavingOrder;
    }

    get isPlaceOrderDisabled() {
        return this.isSavingOrder || !this.hasSelectedItems;
    }

    get shouldShowFooter() {
        // Show footer only when dealer is selected or products are selected
        return this.selectedDistributor || this.isSampleOrder || this.hasSelectedItems;
    }

    get checkoutLayoutClass() {
        let classes = 'checkout-layout step-one-layout';
        if (this.shouldShowFooter) {
            classes += ' has-footer';
        }
        return classes;
    }

    get cartSummaryClass() {
        return this.isCartSummaryExpanded ? 'price-card price-card-pinned' : 'price-card price-card-pinned collapsed';
    }

    get cartToggleIcon() {
        return this.isCartSummaryExpanded ? '▼' : '▶';
    }

    get cartToggleTitle() {
        return this.isCartSummaryExpanded ? 'Collapse cart summary' : 'Expand cart summary';
    }

    get cartItemCount() {
        return this.selectedItemsForSummary.length;
    }

    get floatingCartBtnClass() {
        const classes = ['floating-cart-btn'];
        if (this.showCartRemoveBtn) {
            classes.push('show-remove-btn');
        }
        return classes.join(' ');
    }

    handleCartLongPressStart() {
        // Start a timer for long press (700ms)
        this.cartLongPressTimer = setTimeout(() => {
            this.showCartRemoveBtn = true;
        }, 700);
    }

    handleCartLongPressEnd() {
        // Clear timer if mouse/touch released before 700ms
        if (this.cartLongPressTimer) {
            clearTimeout(this.cartLongPressTimer);
            this.cartLongPressTimer = null;
        }
    }

    handleCartLongPressCancel() {
        // Clear timer if mouse leaves or touch is cancelled
        if (this.cartLongPressTimer) {
            clearTimeout(this.cartLongPressTimer);
            this.cartLongPressTimer = null;
        }
        this.showCartRemoveBtn = false;
    }

    removeCartButton() {
        this.isCartButtonHidden = true;
        this.showCartRemoveBtn = false;
    }

    toggleCartModal() {
        // Don't open modal if remove button is showing
        if (this.showCartRemoveBtn) return;
        this.isCartModalOpen = !this.isCartModalOpen;
    }

    closeCartModal() {
        this.isCartModalOpen = false;
        // Show cart button again when modal is closed
        this.isCartButtonHidden = false;
        this.showCartRemoveBtn = false;
    }

    toggleCartSummary() {
        this.isCartSummaryExpanded = !this.isCartSummaryExpanded;
    }

    setCurrentProducts(updatedProducts) {
        if (this.selectedOrderType === 'Sample Order') {
            this.sampleProducts = updatedProducts;
        } else if (this.selectedOrderType === 'Regular Order') {
            this.regularProducts = updatedProducts;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}