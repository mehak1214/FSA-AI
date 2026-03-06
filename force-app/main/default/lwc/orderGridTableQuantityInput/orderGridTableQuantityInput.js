import {LightningElement, api} from 'lwc';

export default class OrderGridTableQuantityInput extends LightningElement{
    @api quantity;
    @api productId;

    _quantity;

    connectedCallback(){
        this._quantity = this.quantity;   
    }

    changeQuantity(event){
        if(event.target.value.length > 0){
            this._quantity = parseInt(event.target.value, 10);
        }
    }

    addQuantity(){
        if(this._quantity && this._quantity > 0){
            const detail = {
                productId: this.productId,
                quantity: this._quantity
            };

            const addProductQuantityEvent = new CustomEvent('addproductquantityevent', {
                detail: detail,
                bubbles: false,
                composed: false
            });
            this.dispatchEvent(addProductQuantityEvent);
        }
    }
}