import { LightningElement, track } from 'lwc';
import startDay from '@salesforce/apex/VisitController.startDay';

export default class StartDay extends LightningElement {

    @track error;
    isStarted = false;

    handleStartDay() {
        navigator.geolocation.getCurrentPosition(
            position => {
                const lat = position.coords.latitude.toString();
                const lon = position.coords.longitude.toString();

                startDay({ lat: lat, lon: lon })
                    .then(() => {
                        this.isStarted = true;
                        this.error = null;
                    })
                    .catch(err => {
                        this.error = err.body ? err.body.message : err.message;
                    });
            },
            error => {
                this.error = 'Location permission denied.';
            },
            { enableHighAccuracy: true }
        );
    }
}