/*
==========================================
    Title: orderGridTable
    Purpose: Component that displays the
        order grid.
    Author: Clay Phillips
    Date: 08/20/2020 
==========================================
*/

import {LightningElement, api} from 'lwc';
import BASE_PATH from "@salesforce/community/basePath";

export default class OrderGridTable extends LightningElement{
    @api orderProducts;

    @api
    get sortObject(){
        return this._sortObject;
    }

    //Setter for sortObject that calls the sortTableRows() method 
    set sortObject(value){
        this._sortObject = value;
        if(this._sortObject){
            this.sortTableRows();
        }
    }
    _sortObject;

    @api
    get orderYear(){
        return this._orderYear;
    }

    //Setter for orderYear that calls the filterOrderProductsByYear() method 
    set orderYear(value){
        this._orderYear = value;
        this.filterOrderProductsByYear();
    }
    _orderYear;

    @api
    get searchText(){
        return this._searchText;
    }

    @api cartURL;
    @api cartItems;

    get communityName() {
		let path = BASE_PATH;
		let pos = BASE_PATH.lastIndexOf("/s");
		if (pos >= 0) {
			path = BASE_PATH.substring(0, pos);
		}

		return path;
	}

    showTable = false;

    //Setter for searchText that calls the filterOrderProductsByNameSKU() method
    //if there is search text or shows all of the OPs again if there isn't any search text.
    set searchText(value){
        this._searchText = value;
        if(this._searchText.length > 0){
            this.filterOrderProductsByNameSKU();
        }
        else{
            this.filteredOrderProducts = this.filteredOrderProductsCopy;
            this.orders = [];
            this.orderColumns = [];
            this.orderColumnStrings = [];
            this.tableRows = [];
            this.productArray = [];
            this._sortObject = null;
            this.createTable();
            this.showNoOrdersMessage = false;
            this.showTable = true;
        }
    }
    _searchText;

    @api
    get resetQuantities(){
        return this._resetQuantities;
    }

    set resetQuantities(value){
        this._resetQuantities = value;
        this.productQuantities = [];
        this.totalProductQuantity = 0;
        this.addToCartDisabled = true;
    }
    _resetQuantities

    filteredOrderProducts = [];

    //Needed for searching to store the original order product list without filters
    filteredOrderProductsCopy = [];
    orders = [];
    orderColumns = [];
    orderColumnStrings = [];
    tableRows = [];
    tableRowOne = {};
    productArray = [];
    productQuantities = [];
    totalProductQuantity = 0;

    showNoOrdersMessage = false;
    showNoMatchingProductsMessage = false;

    addToCartDisabled = true;

    //For order pagination
    numberOfPages = 1;
    pageNumber = 1;

    //Filters the order products by year
    filterOrderProductsByYear(){
        if(!this._orderYear){
            const today = new Date();
            this._orderYear = today.getFullYear();
        }

        this.filteredOrderProducts = [];
        this.orderProducts.forEach((op) =>{
            const orderedDateRaw = new Date(op.orderedDate);
            const orderedDate = new Date(orderedDateRaw.getTime() + orderedDateRaw.getTimezoneOffset() * 60000);
            if(orderedDate.getFullYear() === this._orderYear){
                this.filteredOrderProducts.push(op);
            }
        })
        
        if(this.filteredOrderProducts.length > 0){
            this.filteredOrderProductsCopy = this.filteredOrderProducts;
            this.orders = [];
            this.orderColumns = [];
            this.orderColumnStrings = [];
            this.tableRows = [];
            this.productArray = [];
            this.productQuantities = [];
            this.totalProductQuantity = 0;
            this.addToCartDisabled = true;
            this._sortObject = null;
            this.createTable();
            this.showNoOrdersMessage = false;
            this.showTable = true;
        }
        else{
            this.showTable = false;
            this.showNoOrdersMessage = true;
        }

        this.sendShowTableEvent();
    }

    //Filters the order products by name or SKU
    filterOrderProductsByNameSKU(){
        let filteredOrderProducts = [];
        this.filteredOrderProductsCopy.forEach((op) =>{
            if(op.productName.toLowerCase().includes(this._searchText.toLowerCase())
                || op.productSKU.toLowerCase().includes(this._searchText.toLowerCase())){
                
                    filteredOrderProducts.push(op);
            }
        }) 

        this.filteredOrderProducts = filteredOrderProducts;

        if(this.filteredOrderProducts.length > 0){ 
            this.orderColumns = [];
            this.orderColumnStrings = [];
            this.tableRows = [];
            this.productArray = [];
            this._sortObject = null;
            this.createTable();
            this.showNoMatchingProductsMessage = false;
            this.showTable = true;
        }
        else{
            this.showTable = false;
            this.showNoMatchingProductsMessage = true;
        }
    }

    //Parses the order items and creates the table
    createTable(){
        this.showNoMatchingProductsMessage = false;
        this.parseOrderItems();
        this.createTableRows();
    }

    //Creates the date column headers and product array needed for the table
    parseOrderItems(){
        this.createOrderArray(this.filteredOrderProducts);
        this.createOrderColumns(this.orders);
        this.createProductArray(this.filteredOrderProducts);
        this.numberOfPages = Math.ceil(this.orders.length / 5);
    }

    createOrderArray(filteredOrderProducts){
        for(let a = 0; a < filteredOrderProducts.length; a++){
            const op = filteredOrderProducts[a];
            const order = {
                orderId: op.orderId,
                orderedDate: op.orderedDate
            }

            let orderFound = false;
            for(let b = 0; b < this.orders.length; b++){
                if(this.orders[b].orderId === order.orderId){
                    orderFound = true;
                    break;    
                }
            }
            if(!orderFound){
                this.orders.push(order);
            }
        }    
        //console.log('orders', this.orders);
    }

    //Uses the OP Ordered Dates to date column headers for the table 
    createOrderColumns(orders){
        const offset = (this.pageNumber * 5) - 5;
        const orderArrayEndpoint = ((this.pageNumber * 5 < orders.length) ? this.pageNumber * 5 : orders.length);

        for(let a = offset; a < orderArrayEndpoint; a++){
            const order = orders[a];
            const orderedDateRaw = new Date(order.orderedDate);
            const orderedDate = new Date(orderedDateRaw.getTime() + orderedDateRaw.getTimezoneOffset() * 60000); //needed to account for the time offset
            
            let columnLabel = this.getMonthString(orderedDate.getMonth()) + ' ';
            columnLabel += orderedDate.getDate() + ', ' + orderedDate.getFullYear();

            const orderColumn = {
                orderId: order.orderId,
                label: columnLabel,
                date: order.orderedDate
            }

            this.orderColumns.push(orderColumn);
        }
        //console.log('orderColumns', this.orderColumns);
    }

    createProductArray(filteredOrderProducts){
        for(let a = 0; a < filteredOrderProducts.length; a++){
            const op = filteredOrderProducts[a];
            let productImageURL = '';
            if(op.productImageURL){
                // format image url
                let url = op.productImageURL;

                if (url.indexOf("/cms/delivery/media") >= 0) {
                    const searchRegExp = /\/cms\/delivery\/media/g;

                    url = url.replace(searchRegExp, this.communityName + "/cms/delivery/media");
                }

                if (url.indexOf("/cms/media") >= 0) {
                    const searchRegExp = /\/cms\/media/g;

                    url = url.replace(searchRegExp, this.communityName + "/cms/delivery/media");
                }

                productImageURL = url;
            }
            let productDetailURL = BASE_PATH + "/product/" + op.productId;
            const productObject = {
                Id: op.productId,
                SKU: op.productSKU,
                name: op.productName,
                productImageURL: productImageURL,
                quantityValues: [],
                productDetailURL: productDetailURL,
                attributeMap: op.attributeMap,
                attributeSetInfo: op.attributeSetInfo,
                attributeDeveloperName: op.attributeDeveloperName
            }

            let productFound = false;
            for(let b = 0; b < this.productArray.length; b++){
                if(this.productArray[b].Id === productObject.Id){
                    productFound = true;
                    break;    
                }
            }
            if(!productFound){
                this.productArray.push(productObject);
            }
        }
        //console.log('productArray', this.productArray);
    }

    //Creates the table row objects needed for the table
    createTableRows(){
        for(let i = 0; i < this.productArray.length; i++){
            const productObject = this.productArray[i];

            for(let b = 0; b < this.orderColumns.length; b++){
                const order = this.orderColumns[b];
                let matchFound = false;

                for(let c = 0; c < this.filteredOrderProducts.length; c++){
                    if(this.filteredOrderProducts[c].productId === productObject.Id
                        && this.filteredOrderProducts[c].orderId === order.orderId){
                            const uniqueQuantityObj = {
                                quantity: this.filteredOrderProducts[c].quantity,
                                //Used as a unique key for the HTML for each loop
                                uniqueQuantity: this.filteredOrderProducts[c].quantity + ' ' + Math.random() 
                            };

                            productObject.quantityValues.push(uniqueQuantityObj);
                            matchFound = true;
                            break;
                    }
                }

                //Sets the quantiy to 0 for the order product for this particular order
                //if there aren't any of this product in the order
                if(!matchFound){
                    const uniqueQuantityObj = {
                        quantity: 0,
                        uniqueQuantity: Math.random()
                    };

                    productObject.quantityValues.push(uniqueQuantityObj);
                }
            }
            
            let quantityGreaterThanZeroFound = false;
            for(let d = 0; d < productObject.quantityValues.length; d++){
                if(productObject.quantityValues[d].quantity > 0){
                    quantityGreaterThanZeroFound = true;
                    break;
                }
            }
            if(quantityGreaterThanZeroFound){
                this.tableRows.push(productObject);
            }
        }
        //console.log('this.tableRows', this.tableRows);
        this.tableRowOne = this.tableRows[0];
    }

    //Main method to sort the table rows. Calls either the sortByFieldAscending() or sortByFieldDescending() method
    sortTableRows(){
        if(this._sortObject.sortDirection === 'ASC'){
            this.sortByFieldAscending(this._sortObject.sortField);
            return;
        }
        
        this.sortByFieldDescending(this._sortObject.sortField);
    }

    //Sorts the table rows in ascending order by product name or SKU
    sortByFieldAscending(fieldName){
        function compare(a, b){
            const valueA = a[fieldName];
            const valueB = b[fieldName];

            let comparison = 0;
            if(valueA != null && valueB != null){
                if(valueA > valueB){
                    comparison = 1;
                }
                else if(valueA < valueB){
                    comparison = -1;
                }
            }
            else if(valueA == null && valueB != null){
                comparison = 1;
            }
            else if(valueA != null && valueB == null){
                comparison = -1;
            }
            
            return comparison;
        }
          
        this.tableRows.sort(compare);

        //Needed to refresh the UI due to the reactivity of LWCs
        this.tableRows = [...this.tableRows];
    }

    //Sorts the table rows in descending order by product name or SKU
    sortByFieldDescending(fieldName){
        function compare(a, b){
            const valueA = a[fieldName];
            const valueB = b[fieldName];

            let comparison = 0;
            if(valueA != null && valueB != null){
                if(valueB > valueA){
                    comparison = 1;
                }
                else if(valueB < valueA){
                    comparison = -1;
                }
            }
            else if(valueA == null && valueB != null){
                comparison = 1;
            }
            else if(valueA != null && valueB == null){
                comparison = -1;
            }
            
            return comparison;
        }
          
        this.tableRows.sort(compare);

        //Needed to refresh the UI due to the reactivity of LWCs
        this.tableRows = [...this.tableRows];
    }

    //Uses the month number to return a abbreaviated month string
    getMonthString(monthNumber){
        if(monthNumber === 0){
            return 'Jan.';
        }
        else if(monthNumber === 1){
            return 'Feb.';
        }
        else if(monthNumber === 2){
            return 'Mar.';
        }
        else if(monthNumber === 3){
            return 'Apr.';
        }
        else if(monthNumber === 4){
            return 'May';
        }
        else if(monthNumber === 5){
            return 'June';
        }
        else if(monthNumber === 6){
            return 'July';
        }
        else if(monthNumber === 7){
            return 'Aug.';
        }
        else if(monthNumber === 8){
            return 'Sept.';
        }
        else if(monthNumber === 9){
            return 'Oct.';
        }
        else if(monthNumber === 10){
            return 'Nov.';
        }
        else if(monthNumber === 11){
            return 'Dec.';
        }

        return null;
    }

    //Handler to update the productQuantities array with the products that were selected
    addProductQuantityHandler(event){
        let productFound = false;
        for(let i = 0; i < this.productQuantities.length; i++){
            const productQuantity = this.productQuantities[i];

            if(productQuantity.productId === event.detail.productId){
                productQuantity.quantity += event.detail.quantity;
                this.totalProductQuantity += event.detail.quantity;
                this.productQuantities.splice(i, 1, productQuantity);
                productFound = true;
                break;
            }
        }
        if(!productFound){
            const productQuantity = {
                productId: event.detail.productId,
                quantity: event.detail.quantity
            }
            this.productQuantities.push(productQuantity);
            this.totalProductQuantity += event.detail.quantity;
        }

        //Needed to refresh the UI due to the reactivity of LWCs
        this.productQuantities = [...this.productQuantities]; 

        this.addToCartDisabled = false;
    }

    //Handler to update productQuantities with all of the products from the selected order
    addOrderQuantitiesHandler(event){
        for(let i = 0; i < this.filteredOrderProducts.length; i++){
            const orderProduct = this.filteredOrderProducts[i];
            if(orderProduct.orderId === event.detail.orderId){
                let productFound = false;
                for(let a = 0; a < this.productQuantities.length; a++){
                    const productQuantity = this.productQuantities[a];

                    if(orderProduct.productId === productQuantity.productId){
                        productQuantity.quantity += orderProduct.quantity;
                        this.totalProductQuantity += orderProduct.quantity;
                        this.productQuantities.splice(a, 1, productQuantity);
                        productFound = true;
                        break;
                    }
                }
                if(!productFound){
                    const productQuantity = {
                        productId: orderProduct.productId,
                        quantity: orderProduct.quantity
                    }
                    this.productQuantities.push(productQuantity);
                    this.totalProductQuantity += orderProduct.quantity;
                }
            }
        }

        //Needed to refresh the UI due to the reactivity of LWCs
        this.productQuantities = [...this.productQuantities];

        this.addToCartDisabled = false;
    }

    //Handler to update productQuantities with the new product total from the quantity column
    changeProductQuantityHandler(event){
        let productFound = false;
        for(let i = 0; i < this.productQuantities.length; i++){
            const productQuantity = this.productQuantities[i];

            if(productQuantity.productId === event.detail.productId){
                if(event.detail.quantity){
                    productQuantity.quantity = event.detail.quantity;
                }
                else{
                    productQuantity.quantity = 0;
                }
                this.productQuantities.splice(i, 1, productQuantity);
                productFound = true;
                break;
            }
        }
        if(!productFound){
            let quantity = 0;
            if(event.detail.quantity){
                quantity = event.detail.quantity;
            }
           
            const productQuantity = {
                productId: event.detail.productId,
                quantity: quantity
            }
            this.productQuantities.push(productQuantity);
        }

        let totalProductQuantity = 0;
        this.productQuantities.forEach((pq) =>{
            totalProductQuantity += pq.quantity;
        }) 

        this.totalProductQuantity = totalProductQuantity;
        if(this.totalProductQuantity > 0){
            this.addToCartDisabled = false;
        }
        else{ 
            this.addToCartDisabled = true;  
        }
    }

    //Sends the show table event to render the table along with the search bar, sort and reset buttons
    sendShowTableEvent(){
        const detail = {
            showTable: this.showTable
        };

        const showTableEvent = new CustomEvent('showtableevent', {
            detail: detail,
            bubbles: false,
            composed: false
        });
        this.dispatchEvent(showTableEvent);
    }

    //Handler for the View Cart button that takes the user to the cart detail page
    viewCart(){
        window.open(BASE_PATH + '/' + this.cartURL, '_self');
    }

    paginationEventHandler(event){
        this.pageNumber = (event.detail.pageDirection === 'NEXT' ? this.pageNumber + 1 : this.pageNumber - 1);
        this.filteredOrderProductsCopy = this.filteredOrderProducts;
        this.orders = [];
        this.orderColumns = [];
        this.orderColumnStrings = [];
        this.tableRows = [];
        this.productArray = [];
        this._sortObject = null;
        this.createTable();
        this.showNoOrdersMessage = false;
        this.showTable = true;
    }

    //Handler for the Add to Cart button that sends an event to orderGridMain
    //to call the apex method to add the products to the cart
    addToCart(){
        const detail = {
            cartProducts: this.productQuantities
        };

        const addToCartEvent = new CustomEvent('addtocartevent', {
            detail: detail,
            bubbles: false,
            composed: false
        });
        this.dispatchEvent(addToCartEvent);
    }

    //Uses the OP Ordered Dates to date column headers for the table 
    // createDateColumnHeader(op){
    //     const orderedDateRaw = new Date(op.orderedDate);
    //     const orderedDate = new Date(orderedDateRaw.getTime() + orderedDateRaw.getTimezoneOffset() * 60000); //needed to account for the time offset
        
    //     let columnLabel = this.getMonthString(orderedDate.getMonth()) + ' ';
    //     columnLabel += orderedDate.getDate() + ', ' + orderedDate.getFullYear();

    //     const orderColumn = {
    //         orderId: op.orderId,
    //         label: columnLabel,
    //         date: op.orderedDate
    //     }

    //     if(this.orderColumnStrings.includes(JSON.stringify(orderColumn))){
    //         return;
    //     }

    //     this.orderColumnStrings.push(JSON.stringify(orderColumn));
    //     this.orderColumns.push(orderColumn);
    // }

    //Creates the array of products needed to create the table
    // createProductArray(op){
    //     let productImageURL = '';
    //     if(op.productImageURL){
    //         productImageURL = op.productImageURL;
    //     }
    //     const productObject = {
    //         Id: op.productId,
    //         SKU: op.productSKU,
    //         name: op.productName,
    //         productImageURL: productImageURL,
    //         quantityValues: []
    //     }

    //     const productObjectString = JSON.stringify(productObject);

    //     if(this.productArray.includes(productObjectString)){
    //         return;
    //     }
        
    //     this.productArray.push(productObjectString);
    // }

    //Creates the table row objects needed for the table
    // createTableRows(){
    //     for(let i = 0; i < this.productArray.length; i++){
    //         const productObject = JSON.parse(this.productArray[i]);

    //         for(let b = 0; b < this.orderColumns.length; b++){
    //             const order = this.orderColumns[b];
    //             let matchFound = false;

    //             for(let c = 0; c < this.filteredOrderProducts.length; c++){
    //                 if(this.filteredOrderProducts[c].productId === productObject.Id
    //                     && this.filteredOrderProducts[c].orderId === order.orderId){
    //                         const uniqueQuantityObj = {
    //                             quantity: this.filteredOrderProducts[c].quantity,
    //                             //Used as a unique key for the HTML for each loop
    //                             uniqueQuantity: this.filteredOrderProducts[c].quantity + ' ' + Math.random() 
    //                         };

    //                         productObject.quantityValues.push(uniqueQuantityObj);
    //                         matchFound = true;
    //                         break;
    //                 }
    //             }

    //             //Sets the quantiy to 0 for the order product for this particular order
    //             //if there aren't any of this product in the order
    //             if(!matchFound){
    //                 const uniqueQuantityObj = {
    //                     quantity: 0,
    //                     uniqueQuantity: Math.random()
    //                 };

    //                 productObject.quantityValues.push(uniqueQuantityObj);
    //             }
    //         }
            
    //         this.tableRows.push(productObject);
    //     }
    //     this.tableRowOne = this.tableRows[0];
    // }
}