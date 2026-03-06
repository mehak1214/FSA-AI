import { LightningElement, wire } from 'lwc';
import getNewProducts from '@salesforce/apex/NewProductsCardViewController.getNewProducts';

export default class NewProductsCardView extends LightningElement {
    products = [];
    allProducts = [];
    displayProducts = [];
    isModalOpen = false;
    isProductDetailModalOpen = false;
    selectedProduct = null;
    overflowCount = 0;
    maxCards = 4;

    @wire(getNewProducts)
    wiredProducts({ error, data }) {
        if (data) {
            this.products = data;
            this.allProducts = [...data];
            this.processProducts();
        } else if (error) {
            console.error('Error loading products:', error);
        }
    }

    renderedCallback() {
        // Scroll modals into view when they open
        if (this.isModalOpen) {
            const modal = this.refs.productsModal;
            if (modal) {
                setTimeout(() => {
                    modal.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }, 0);
            }
        }
        if (this.isProductDetailModalOpen) {
            const detailModal = this.refs.detailModal;
            if (detailModal) {
                setTimeout(() => {
                    detailModal.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }, 0);
            }
        }
    }

    processProducts() {
        if (!this.products || this.products.length === 0) {
            this.displayProducts = [];
            return;
        }

        if (this.products.length <= this.maxCards) {
            // Show all products if less than or equal to max cards
            this.displayProducts = this.products.map(product => ({
                ...product,
                isOverflow: false,
                cardClass: 'product-card'
            }));
            this.overflowCount = 0;
        } else {
            // Show first 3 products + overflow card
            const regularProducts = this.products.slice(0, this.maxCards - 1).map(product => ({
                ...product,
                isOverflow: false,
                cardClass: 'product-card'
            }));
            const overflowCard = {
                Id: 'overflow',
                Name: 'overflow',
                isOverflow: true,
                cardClass: 'product-card view-all-card'
            };
            this.displayProducts = regularProducts.concat(overflowCard);
            this.overflowCount = this.products.length - (this.maxCards - 1);
        }
    }

    handleOpenModal() {
        this.isModalOpen = true;
    }

    handleCloseModal() {
        this.isModalOpen = false;
    }

    handleProductCardClick(event) {
        const productId = event.currentTarget.dataset.productId;
        if (productId === 'overflow') {
            this.handleOpenModal();
            return;
        }
        if (productId) {
            this.selectedProduct = this.products.find(p => p.Id === productId);
            this.isProductDetailModalOpen = true;
        }
    }

    handleCloseProductDetailModal() {
        this.isProductDetailModalOpen = false;
        this.selectedProduct = null;
    }

    handleProductDetailModalContentClick(event) {
        // Prevent modal from closing when clicking inside modal content
        event.stopPropagation();
    }

    handleModalContentClick(event) {
        // Prevent modal from closing when clicking inside modal content
        event.stopPropagation();
    }
}