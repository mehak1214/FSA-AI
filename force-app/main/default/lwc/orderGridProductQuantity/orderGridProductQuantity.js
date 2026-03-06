/*
==========================================
    Title: orderGridProductQuantity
    Purpose: Component that displays the 
        total quantity for the product.
    Author: Clay Phillips
    Date: 08/20/2020 
==========================================
*/

import {LightningElement, api} from 'lwc';

export default class OrderGridProductQuantity extends LightningElement{
    @api productId;

    @api
    get productQuantities(){
        return this._productQuantities;
    }

    //Uses the productQuantities array that's passed in to pull the correct quantity for the product
    set productQuantities(value){
        this._productQuantities = value;

        let productFound = false;
        for(let i = 0; i < this._productQuantities.length; i++){
            const productQuantity = this._productQuantities[i];

            if(productQuantity.productId === this.productId){
                this._quantity = productQuantity.quantity;
                productFound = true;
                break;
            }

        }
        if(!productFound){
            this._quantity = 0;
        }
    }

    _productQuantities;

    @api
    get cartItems(){
        return this._cartItems;
    }

    set cartItems(value){
        this._cartItems = value;

        let productFound = false;
        if(this._cartItems){
            for(let i = 0; i < this._cartItems.length; i++){
                const cartItem = this._cartItems[i];
                if(cartItem.productId === this.productId){
                    this._cartQuantity = cartItem.quantity;
                    productFound = true;
                    break;
                }
            }
        }

        if(!productFound){
            this._cartQuantity = 0;
        }
    }

    _cartItems;

    _quantity;
    _cartQuantity;

    //Centers the number in the lightning input text since it can't be done directly in the HTML markup
    renderedCallback() {
        const style = document.createElement('style');
        style.innerText = `c-order-grid-product-quantity .slds-input {
            text-align: center;
        }`;
        this.template.querySelector('lightning-input').appendChild(style);
    }

    //Updates the local quantity variable and sends it to orderGridTable via an event.
    changeQuantity(event){
        if(event.target.value >= 0){
            this._quantity = parseInt(event.target.value, 10);
        }
        else{
            return;
        }

        const detail = {
            productId: this.productId,
            quantity: this._quantity
        };

        const changeProductQuantityEvent = new CustomEvent('changeproductquantityevent', {
            detail: detail,
            bubbles: false,
            composed: false
        });
        this.dispatchEvent(changeProductQuantityEvent);
    }
}