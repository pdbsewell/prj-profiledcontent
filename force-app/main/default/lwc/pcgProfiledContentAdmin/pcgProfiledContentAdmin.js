import { LightningElement, track, api } from 'lwc';
import hasPermission from '@salesforce/customPermission/CP_ProfiledContentAdmin';

export default class pcgProfiledContentAdmin extends LightningElement {
    
    @track groupName;

    get hasPermission() {
        return hasPermission;
    }

    handleGroupChange(event) {
        console.log('got event from child');
        const textVal = event.detail;
        this.groupName = textVal;
        this.template.querySelector('c-pcg-dealer-picker').doRefreshDealers(this.groupName);
        console.log('called for dealer refresh');
    }

    // SELECT Dealer_Name__c, Dealer_Code__c FROM DealerGroupRelationship__c WHERE Profile_Group__c = 'PCG Mobile'
}