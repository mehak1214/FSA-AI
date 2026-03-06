import { LightningElement, wire } from 'lwc';
import getActiveSchemes from '@salesforce/apex/ActiveSchemesCardViewController.getActiveSchemes';

export default class ActiveSchemesCardView extends LightningElement {
    schemes = [];
    allSchemes = [];
    displaySchemes = [];
    isModalOpen = false;
    isSchemeDetailModalOpen = false;
    selectedScheme = null;
    overflowCount = 0;
    maxCards = 4;

    @wire(getActiveSchemes)
    wiredSchemes({ error, data }) {
        if (data) {
            this.schemes = data;
            this.allSchemes = [...data];
            this.processSchemes();
        } else if (error) {
            console.error('Error loading schemes:', error);
        }
    }

    processSchemes() {
        if (!this.schemes || this.schemes.length === 0) {
            this.displaySchemes = [];
            return;
        }

        if (this.schemes.length <= this.maxCards) {
            // Show all schemes if less than or equal to max cards
            this.displaySchemes = this.schemes.map(scheme => ({
                ...scheme,
                isOverflow: false,
                cardClass: 'scheme-card'
            }));
            this.overflowCount = 0;
        } else {
            // Show first 3 schemes + overflow card
            const regularSchemes = this.schemes.slice(0, this.maxCards - 1).map(scheme => ({
                ...scheme,
                isOverflow: false,
                cardClass: 'scheme-card'
            }));
            const overflowCard = {
                Id: 'overflow',
                SchemeName: 'overflow',
                isOverflow: true,
                cardClass: 'scheme-card view-all-card'
            };
            this.displaySchemes = regularSchemes.concat(overflowCard);
            this.overflowCount = this.schemes.length - (this.maxCards - 1);
        }
    }

    renderedCallback() {
        // Scroll modal into view when it opens
        if (this.isModalOpen) {
            const modal = this.refs.schemesModal;
            if (modal) {
                setTimeout(() => {
                    modal.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }, 0);
            }
        }
    }

    handleOpenModal() {
        this.isModalOpen = true;
    }

    handleCloseModal() {
        this.isModalOpen = false;
    }

    handleSchemeCardClick(event) {
        const schemeId = event.currentTarget.dataset.schemeId;
        if (schemeId === 'overflow') {
            this.handleOpenModal();
            return;
        }
        if (schemeId) {
            this.selectedScheme = this.schemes.find(s => s.Id === schemeId);
            this.isSchemeDetailModalOpen = true;
        }
    }

    handleCloseSchemeDetailModal() {
        this.isSchemeDetailModalOpen = false;
        this.selectedScheme = null;
    }

    handleSchemeDetailModalContentClick(event) {
        // Prevent modal from closing when clicking inside modal content
        event.stopPropagation();
    }

    handleModalContentClick(event) {
        // Prevent modal from closing when clicking inside modal content
        event.stopPropagation();
    }
}