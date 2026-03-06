import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getAllSchemes from '@salesforce/apex/ViewSchemesController.getAllSchemes';

export default class ViewSchemes extends NavigationMixin(LightningElement) {
    @wire(getAllSchemes)
    wiredSchemes({ error, data }) {
        if (data) {
            this.schemes = data.map(scheme => ({
                ...scheme,
                formattedDiscount: this.formatValue(scheme.discount, 'percentage'),
                formattedThreshold: this.formatValue(scheme.thresholdQuantity, 'number'),
                formattedStartDate: this.formatDate(scheme.startDate),
                formattedEndDate: this.formatDate(scheme.endDate)
            }));
            console.log('Schemes loaded:', this.schemes);
        } else if (error) {
            console.error('Error loading schemes:', error);
            this.dispatchEvent(new CustomEvent('error-message', {
                detail: {
                    message: error.body?.message || 'Error loading schemes'
                }
            }));
        }
    }

    schemes = [];
    filterValue = 'active'; // all, active, inactive
    sortValue = 'name'; // name, discount, threshold

    filterOptions = [
        { label: 'All Schemes', value: 'all' },
        { label: 'Active Only', value: 'active' },
        { label: 'Inactive Only', value: 'inactive' }
    ];

    sortOptions = [
        { label: 'Name (A-Z)', value: 'name' },
        { label: 'Discount (High to Low)', value: 'discount_desc' },
        { label: 'Discount (Low to High)', value: 'discount_asc' },
        { label: 'Threshold (High to Low)', value: 'threshold_desc' },
        { label: 'Threshold (Low to High)', value: 'threshold_asc' }
    ];

    handleFilterChange(event) {
        this.filterValue = event.detail.value;
    }

    handleSortChange(event) {
        this.sortValue = event.detail.value;
    }

    get filteredAndSortedSchemes() {
        let filtered = this.schemes;

        // Apply filter
        if (this.filterValue === 'active') {
            filtered = filtered.filter(scheme => scheme.isActive);
        } else if (this.filterValue === 'inactive') {
            filtered = filtered.filter(scheme => !scheme.isActive);
        }

        // Apply sort
        const sorted = [...filtered];
        switch (this.sortValue) {
            case 'name':
                sorted.sort((a, b) => a.schemeName.localeCompare(b.schemeName));
                break;
            case 'discount_desc':
                sorted.sort((a, b) => (b.discount || 0) - (a.discount || 0));
                break;
            case 'discount_asc':
                sorted.sort((a, b) => (a.discount || 0) - (b.discount || 0));
                break;
            case 'threshold_desc':
                sorted.sort((a, b) => (b.thresholdQuantity || 0) - (a.thresholdQuantity || 0));
                break;
            case 'threshold_asc':
                sorted.sort((a, b) => (a.thresholdQuantity || 0) - (b.thresholdQuantity || 0));
                break;
            default:
                break;
        }
        return sorted;
    }

    get activeSchemes() {
        return this.filteredAndSortedSchemes.filter(scheme => scheme.isActive);
    }

    get inactiveSchemes() {
        return this.filteredAndSortedSchemes.filter(scheme => !scheme.isActive);
    }

    get hasSchemes() {
        return this.schemes.length > 0;
    }

    get hasFilteredSchemes() {
        return this.filteredAndSortedSchemes.length > 0;
    }

    formatDate(date) {
        if (!date) return '-';
        return new Date(date).toLocaleDateString('en-US', {
            year: 'numeric',
            month: 'short',
            day: 'numeric'
        });
    }

    formatValue(value, type) {
        if (value === null || value === undefined) return '-';
        
        if (type === 'percentage') {
            return `${parseFloat(value).toFixed(2)}%`;
        } else if (type === 'number') {
            return parseFloat(value).toFixed(2);
        }
        return value;
    }

    handleSchemeClick(event) {
        const schemeId = event.target.dataset.schemeId;
        if (schemeId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: schemeId,
                    actionName: 'view'
                }
            });
        }
    }
}