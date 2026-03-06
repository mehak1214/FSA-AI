import { LightningElement, api, track } from 'lwc';

export default class VisitMap extends LightningElement {

    @api visits = [];

    @track mapMarkers = [];
    @track mapCenter;
    userMarker = null;

    connectedCallback() {
        this.loadCurrentLocation();
    }

    renderedCallback() {
        this.prepareVisitMarkers();
    }

    loadCurrentLocation() {
        if (!navigator.geolocation) return;

        navigator.geolocation.getCurrentPosition(
            pos => {
                const lat = pos.coords.latitude;
                const lon = pos.coords.longitude;

                this.mapCenter = {
                    Latitude: lat,
                    Longitude: lon
                };

                const userMarker = {
                    location: { Latitude: lat, Longitude: lon },
                    title: 'You are here',
                    icon: 'utility:user'
                };

                this.userMarker = userMarker;
                this.prepareVisitMarkers();
            },
            () => {},
            { enableHighAccuracy: true }
        );
    }

    prepareVisitMarkers() {
        const visitMarkers = (this.visits || [])
            .map((visit) => {
                const outlet = this._getOutlet(visit);
                if (!outlet?.BillingLatitude || !outlet?.BillingLongitude) return null;
                return {
                location: {
                        Latitude: outlet.BillingLatitude,
                        Longitude: outlet.BillingLongitude
                },
                    title: outlet.Name || 'Outlet',
                    description: `Status: ${this._getVisitStatus(visit) || 'Unknown'}`
                };
            })
            .filter((marker) => marker !== null);

        this.mapMarkers = this.userMarker
            ? [this.userMarker, ...visitMarkers]
            : visitMarkers;
    }

    _getOutlet(visit) {
        return visit?.ibfsa__Outlet1__r
            || visit?.Outlet1__r
            || visit?.ibfsa__Outlet__r
            || visit?.Outlet__r
            || null;
    }

    _getVisitStatus(visit) {
        return visit?.ibfsa__Visit_Status__c
            || visit?.Visit_Status__c
            || '';
    }
}