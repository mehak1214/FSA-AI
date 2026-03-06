/*
==========================================
    Title: orderGridTableDateColumnHeader
    Purpose: Component that's used to
        display the order grid's
        date column labels.
    Author: Clay Phillips
    Date: 08/20/2020 
==========================================
*/

import {LightningElement, api} from 'lwc';

export default class OrderGridTableDateColumnHeader extends LightningElement{
    @api columnHeader;

    //Sends an event to orderGridTable to add all of the order's products to the product quantity column
    addAllOrderQuantities(){
        const detail = {
            orderId: this.columnHeader.orderId
        };

        const addOrderQuantitiesEvent = new CustomEvent('addorderquantitiesevent', {
            detail: detail,
            bubbles: false,
            composed: false
        });
        this.dispatchEvent(addOrderQuantitiesEvent);
    }
}