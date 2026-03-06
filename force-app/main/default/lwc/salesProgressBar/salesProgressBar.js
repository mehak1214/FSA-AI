import { LightningElement, wire } from 'lwc';
import getSalesProgress from '@salesforce/apex/SalesProgressController.getSalesProgress';
import USER_ID from '@salesforce/user/Id';

export default class SalesProgressBar extends LightningElement {
    actual = 0;
    target = 0;
    progress = 0;
    isLoading = true;
    error = undefined;

    get actualFormatted() {
        return new Intl.NumberFormat('en-IN').format(this.actual);
    }

    get targetFormatted() {
        return new Intl.NumberFormat('en-IN').format(this.target);
    }

    get midFormatted() {
        const midValue = this.target ? this.target / 2 : 0;
        return new Intl.NumberFormat('en-IN').format(Math.round(midValue));
    }

    // Dynamic style for progress bar fill
    get progressStyle() {
        return `width:${this.progress}%; background:${this.progressGradient}`;
    }

    // Gradient color thresholds for smoother look
    get progressGradient() {
        if (this.progress < 30) {
            return 'linear-gradient(90deg, #e53935, #ef5350)'; // red shades
        } else if (this.progress < 70) {
            return 'linear-gradient(90deg, #fb8c00, #fdd835)'; // orange-yellow
        } else {
            return 'linear-gradient(90deg, #43a047, #66bb6a)'; // green shades
        }
    }

    // Label with arrow
    get progressLabel() {
        return `▲ ${this.progress}%`;
    }

    get currentMonth() {
        const today = new Date();
        const year = today.getFullYear();
        const month = String(today.getMonth() + 1).padStart(2, '0');
        const day = '01';
        return `${year}-${month}-${day}`;
    }

    @wire(getSalesProgress, {
        userId: USER_ID,
        monthDate: '$currentMonth'
    })
    wiredData({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.actual = data.actual || 0;
            this.target = data.target || 0;
            this.progress = data.progress || 0;
            this.error = undefined;
        } else if (error) {
            this.error = error;
        }
    }
}