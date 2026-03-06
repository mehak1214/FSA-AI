import { LightningElement, track } from 'lwc';

export default class OrderEntry extends LightningElement {

    productOptions = [
        {
            label: 'Burlington Textiles Corp of America',
            value: 'burlington'
        },
        {
            label: 'Dickenson plc',
            value: 'dickenson'
        },
        {
            label: 'Edge Communication',
            value: 'edge'
        }];

    @track orderItems = [
        { id: 1, productName: '', quantity: 1 }
    ];

    nextId = 2;

    addRow() {
        this.orderItems = [
            ...this.orderItems,
            { id: this.nextId++, productName: '', quantity: 1 }
        ];
    }

    removeRow(event) {
        const id = event.target.dataset.id;
        this.orderItems = this.orderItems.filter(item => item.id != id);
    }

    handleChange(event) {
        const id = event.target.dataset.id;
        const field = event.target.dataset.field;

        this.orderItems = this.orderItems.map(item => {
            if (item.id == id) {
                return { ...item, [field]: event.target.value };
            }
            return item;
        });
        console.log('OrderItem:::', JSON.stringify(this.orderItems));
    }

    submitOrder() {
        // Basic validation
        const invalid = this.orderItems.some(
            item => !item.productName || item.quantity <= 0
        );

        if (invalid) {
            alert('Please enter valid product name and quantity.');
            return;
        }

        // Payload ready for Apex / Flow
        console.log('Order Submitted:', JSON.stringify(this.orderItems));

        // Example: call Apex or dispatch event
    }
}