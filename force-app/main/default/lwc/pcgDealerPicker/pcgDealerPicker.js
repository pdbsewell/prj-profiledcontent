/* eslint-disable no-console */
import { LightningElement , api, track} from 'lwc';

//import method which should be used from Controller
import getAllDealers from '@salesforce/apex/PC_GroupPickerController.getAllDealers';
import getDealers from '@salesforce/apex/PC_GroupPickerController.getDealers';
import assignDealers from '@salesforce/apex/PC_GroupPickerController.assignDealers';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class PcgDealerPicker extends LightningElement {
    
    @track dealerOptionsMaster = [];
    @track dealerOptions = [];
    @track dealerValues = [];
    @track noAssignedDealers = true;
    @track showLoadingSpinner = false;
    @track isSaveDealersModalOpen = false;
    @track dealerListDisabled = true;
    
    availableDealers = [];
    availableDealersMap = new Map();
    assignedDealers = [];
    assignedDealersValuesCurrent = [];
    currentGroupName = '';
    filterTerm = '';
    filterOn = false;

    renderedCallback() {
        console.log(this.isRendered);
        if (this.isRendered) {
            return; 
        }
        this.isRendered = true;
    
        let style = document.createElement('style');
        style.innerText = '.slds-dueling-list__column_responsive {min-width: 45% !important;}';
        this.template.querySelector('[data-id="dealerlist"]').appendChild(style);
    }

    handleFilterChange(evt) {
        console.log('Parent filter change event:' + evt.detail + ':');
        this.showLoadingSpinner = true;
        new Promise(
        (resolve,reject) => {
            setTimeout(()=> {
                this.filterAvailableDealers(evt.detail);
                resolve();
            }, 0);
        }).then(
            () => this.showLoadingSpinner = false
        );
    }

    handleAssignedDealersChange(event) {
        // Get the list of the "value" attribute on all the selected options
        const selectedOptionsList = event.detail.value;
        console.log(`Options selected: ${selectedOptionsList}`);
        this.assignedDealersValuesCurrent = event.detail.value;
        this.noAssignedDealers = (this.assignedDealersValuesCurrent.length > 0) ? false : true;
    }

    filterAvailableDealers(theTerm) {
        if (theTerm.length >= 3) {
            this.filterOn = true;
            this.filterTerm = theTerm;
            let data = this.dealerOptionsMaster,
                term = this.filterTerm,
                results = data, regex;
                console.log('about to filter');
                try {
                    regex = new RegExp(term, "i");
                    // filter checks each row, constructs new array where function returns true
                    results = data.filter(row=>regex.test(row.label));
                } catch(e) {
                    // invalid regex, use full list
                }
                console.log('filtered results found before' + JSON.stringify(results));
                results.push(...this.addAssignedDealerItems());
                console.log('filtered results found after' + JSON.stringify(results));
                this.dealerOptions = results;
                console.log('available dealers list filtering complete');
        } else {
            // remove filter, refresh available dealers list
            if (this.filterOn) {    
                this.filterTerm = '';
                this.filterOn= false;
                console.log('refreshing available dealers list');
                this.refreshAvailableDealersList();
                console.log('refresh complete');
            }

        }
        return this.filterOn;
    }

    addAssignedDealerItems() {
        let items = [];
        for (let i = 0; i < this.assignedDealersValuesCurrent.length; i++) {
            items.push({
                label: this.availableDealersMap.get(this.assignedDealersValuesCurrent[i]),
                value: this.assignedDealersValuesCurrent[i],
            });
        }
        return items;
    }

    @api
    doRefreshDealers(groupName) {
        this.currentGroupName = groupName;
        this.dealerValues = [];
        this.assignedDealers = [];
        if (this.availableDealers.length > 0) { // already got dealer list from server, just refresh the picklist list
            if (groupName === 'resetdealerlist') { 
                this.resetDealersDuelingList();
            } else { 
                this.refreshDealersDuelingList();  
            }
        } else {
            this.doGetAllDealers(); // get list of dealers, before refresh
        }
        this.dealerListDisabled = (groupName === 'resetdealerlist') ? true : false;
    }

    doGetAllDealers() {
        this.showLoadingSpinner = true;
        getAllDealers()
            .then((result) => {
                this.availableDealers = result;
                this.error = undefined;
                this.populateAvailableDealersMap();
                this.refreshDealersDuelingList();
                this.showLoadingSpinner = false;
                return;
            })
            .catch((error) => {
                console.log(error);
                this.availableDealers = undefined;
                this.error = error;
            });
    }

    populateAvailableDealersMap() {
        for (let i = 0; i < this.availableDealers.length; i++) {
            this.availableDealersMap.set(this.availableDealers[i].Id, this.availableDealers[i].Name);
        }
    }

    refreshDealersDuelingList() {
        this.refreshAvailableDealersList();
        this.doGetAssignedDealers(this.currentGroupName);
    }

    resetDealersDuelingList() {
        this.refreshAvailableDealersList();
    }

    refreshAvailableDealersList() {
        if (this.dealerOptionsMaster.length > 0) {
            console.log('restore from master');
            this.dealerOptions = this.dealerOptionsMaster;
        } else {
            this.dealerOptionsMaster = [];
            const items = [];
            for (let i = 0; i < this.availableDealers.length; i++) {
                items.push({
                    label: this.availableDealers[i].Name,
                    value: this.availableDealers[i].Id,
                });
            }
            this.dealerOptionsMaster.push(...items);
            this.dealerOptions = this.dealerOptionsMaster;
        }
    }

    doGetAssignedDealers(groupName) {
        this.showLoadingSpinner = true;
        getDealers({ groupName: groupName })
            .then((result) => {
                this.assignedDealers = result;
                this.error = undefined;
                this.populateAssignedDealersList();
                this.showLoadingSpinner = false;
                return;
            })
            .catch((error) => {
                this.assignedDealers = undefined;
                this.error = error;
            });
    }

    populateAssignedDealersList() {
        for (let i = 0; i < this.assignedDealers.length; i++) {
            console.log(this.assignedDealers[i].Dealer_Name__c);
            this.dealerValues.push(this.assignedDealers[i].Dealer__c);;
        }
        this.assignedDealersValuesCurrent = this.dealerValues;
        this.noAssignedDealers = (this.assignedDealersValuesCurrent.length > 0) ? false : true;
    }

    get numberOfAssignedDealers() {
        return this.assignedDealersValuesCurrent.length;
    }

    get groupName() {
        return this.currentGroupName.substring(4, 99);
    }

    handleSaveDealersClick(event) {
        // alert('new group');
        this.openSaveDealersModal();
    }

    openSaveDealersModal() {
        // to open modal set isModalOpen track value as true
        this.isSaveDealersModalOpen = true;
    }

    closeSaveDealersModal() {
        // to close modal set isModalOpen track value as false
        this.isSaveDealersModalOpen = false;
    }
    submitSaveDealersDetails() {
        if (this.currentGroupName.length > 0 ) {
            this.showLoadingSpinner = true;
            new Promise(
            (resolve,reject) => {
                setTimeout(()=> {
                    this.doAssignDealers(this.currentGroupName, this.assignedDealersValuesCurrent);
                    resolve();
                }, 0);
            }).then(
                () => this.showLoadingSpinner = false
            );
        }
        this.isSaveDealersModalOpen = false;
    }

    doAssignDealers(groupName, dealers) {
        if (!this.assignedDealersValuesCurrent || this.assignedDealersValuesCurrent.length == 0) {
            dealers = null;
        }
        assignDealers({ groupName: groupName, dealers: dealers })
            .then((result) => {
                this.error = undefined;
                const event = new ShowToastEvent({
                    "title": "Success!",
                    "message": "Assigned Dealers Updated",
                    "variant": "success"
                });
                this.dispatchEvent(event);
            })
            .catch((error) => {
                this.error = error;
            });
    }
}