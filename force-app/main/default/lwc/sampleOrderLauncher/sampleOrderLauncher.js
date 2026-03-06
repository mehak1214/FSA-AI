import { LightningElement, api } from 'lwc';

export default class SampleOrderLauncher extends LightningElement {
    @api recordId;
    isOpen = false;

    open() {
        this.isOpen = true;
    }

    close() {
        this.isOpen = false;
    }
}