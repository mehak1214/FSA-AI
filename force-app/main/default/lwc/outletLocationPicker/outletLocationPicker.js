import { LightningElement, api, track } from 'lwc';
import saveOutletLocation from '@salesforce/apex/OutletLocationController.saveOutletLocation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class OutletLocationPicker extends LightningElement {

    @api recordId;

    @track latitude;
    @track longitude;
    @track mapCenter;
    @track mapMarkers = [];

    get disableSave() {
        return !(this.latitude && this.longitude);
    }

    connectedCallback() {
        // Show the map even before a location is picked
        if (!this.mapCenter) {
            this.mapCenter = { Latitude: 0, Longitude: 0 };
        }
    }

    /* =========================
       CURRENT LOCATION
    ========================= */
    useCurrentLocation() {
        if (!navigator.geolocation) {
            this.toast('Error', 'Geolocation not supported', 'error');
            return;
        }

        navigator.geolocation.getCurrentPosition(
            pos => {
                this.setLocation(
                    pos.coords.latitude,
                    pos.coords.longitude,
                    'Current Location'
                );
            },
            () => this.toast('Error', 'Location permission denied', 'error'),
            { enableHighAccuracy: true }
        );
    }

    /* =========================
       MAP CLICK (MANUAL PICK)
    ========================= */
    handleMapClick(event) {
        const lat = event.detail.latitude;
        const lon = event.detail.longitude;
        this.setLocation(lat, lon, 'Selected Location');
    }

    setLocation(lat, lon, title) {
        this.latitude = lat;
        this.longitude = lon;

        this.mapCenter = { Latitude: lat, Longitude: lon };
        this.mapMarkers = [{
            location: { Latitude: lat, Longitude: lon },
            title
        }];
    }

    /* =========================
       SAVE TO OUTLET
    ========================= */
    async saveLocation() {
        try {
            await saveOutletLocation({
                outletId: this.recordId,
                latitude: this.latitude,
                longitude: this.longitude
            });

            this.toast('Success', 'Outlet location saved', 'success');
        } catch (e) {
            this.toast(
                'Error',
                e?.body?.message || 'Failed to save location',
                'error'
            );
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}