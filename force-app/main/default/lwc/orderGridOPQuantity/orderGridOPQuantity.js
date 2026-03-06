/*
==========================================
    Title: orderGridOPQuantity
    Purpose: Component that displays the
        quantity for the order product 
        and allows the user to add it to
        the product quantity column.
    Author: Clay Phillips
    Date: 08/20/2020 
==========================================
*/

import {LightningElement, api} from 'lwc';

export default class OrderGridOPQuantity extends LightningElement{
    @api quantity;
    @api productId;


    //Sends an event to orderGridTable to update the product quantities array
    addQuantity(){
        if(this.quantity && this.quantity > 0){
            const detail = {
                productId: this.productId,
                quantity: this.quantity
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