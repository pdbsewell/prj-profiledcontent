/* eslint-disable no-console */
import { LightningElement , wire, track} from 'lwc';

//import method which should be used from Controller
import initAdmin from '@salesforce/apex/PC_GroupPickerController.initAdmin';
import getGroups from '@salesforce/apex/PC_GroupPickerController.getGroups';
import refreshGroups from '@salesforce/apex/PC_GroupPickerController.refreshGroups';
import addGroup from '@salesforce/apex/PC_GroupPickerController.addGroup';
import cloneGroup from '@salesforce/apex/PC_GroupPickerController.cloneGroup';
import copyDealers from '@salesforce/apex/PC_GroupPickerController.copyDealers';
import deleteGroup from '@salesforce/apex/PC_GroupPickerController.deleteGroup';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

let i=0;
export default class pcgGroupPicker extends LightningElement {

    @track items = []; //this will hold key, value pair
    @track value = ''; //initialize combo box value

    @track chosenValue = '';
    @track isNewGroupModalOpen = false;
    @track isCloneGroupModalOpen = false;
    @track isConfirmModalOpen = false;
    @track theInputs = {};
    @track deleteButtonDisabled = true;
    @track cloneButtonDisabled = true;

    error;
    initResult;

    /*
    @wire(getGroups)
    wiredGroups({ error, data }) {
        if (data) {
            //create array with elements retrieved from controller
            //here value will be Group name and label of combobox will be Name (Less 'PCG ')
            console.log('got data from wire - length of data is ', data.length);
            for(let i=0; i<data.length; i++)  {
                console.log(data[i].Name);
                this.items = [...this.items ,{value: data[i].Name , label: data[i].Name.substring(4, 99)} ];                                   
            }                
            this.error = undefined;
        } else if (error) {
            this.error = error;

        }
    }
    */

    // Called when component is inserted into DOM
    connectedCallback(){
        // Setup some stuff before we get going
        initAdmin()
        .then(result => {
            this.initResult = result;
            this.error = undefined;
        })
        .catch(error => {
            this.error = error;
            this.initResult = undefined;
        });
        this.doRefreshGroupsAll();
    } 

    //getter to return items mapped with options attribute
    get groupOptions() {
        return this.items;
    }

    handleChange(event) {
        // Get the string of the "value" attribute on the selected option
        const selectedOption = event.detail.value;
        console.log('selected value=' + selectedOption);
        this.chosenValue = selectedOption;
        this.fireGroupChangeEvent(selectedOption);
    }

    fireGroupChangeEvent(group) {
        this.deleteButtonDisabled = (group != null) ? false : true;
        this.cloneButtonDisabled = (group != null) ? false : true;
        const selectEvent = new CustomEvent('groupchange', {
            detail: (group != null) ? group : "resetdealerlist"
        });
        console.log('about to dispatch change group event'); 
        this.dispatchEvent(selectEvent);
        console.log('dispatched change group event'); 

    }

    handleFormInputBlur(event){
        // Assign the value to the property
        this.theInputs[event.target.name] = event.target.value;
        console.log(event.target.name + ' now is set to ' + event.target.value);
    }

    createNewGroup(groupName) {
        addGroup({ groupName: groupName })
            .then((result) => {
                this.error = undefined;
                const event = new ShowToastEvent({
                    "title": "Success!",
                    "message": "New Profile Created " + groupName,
                    "variant": "success"
                });
                this.dispatchEvent(event);
                this.doRefreshGroups(groupName);
            })
            .catch((error) => {
                this.error = error;
            });
    }

    createCloneGroup(sourceGroupName, targetGroupName) {
        addGroup({ groupName: targetGroupName })
        .then((result) => {
            console.log('added cloned group');
            copyDealers({ sourceGroupName: sourceGroupName,  targetGroupName: targetGroupName})
            .then((result) => {
                console.log('copied dealers from ' + sourceGroupName + 'to ' + targetGroupName);
                this.error = undefined;
                const event = new ShowToastEvent({
                    "title": "Success!",
                    "message": "Cloned Profile Created " + targetGroupName,
                    "variant": "success"
                });
                this.dispatchEvent(event);
                this.doRefreshGroups(targetGroupName);
            })
            .catch((error) => {
                this.error = error;
            });
        })
        .catch((error) => {
            this.error = error;
        });
    }

    deleteOldGroup(groupName) {
        deleteGroup({ groupName: groupName })
            .then((result) => {
                this.error = undefined;
                const event = new ShowToastEvent({
                    "title": "Success!",
                    "message": groupName + " Deleted",
                    "variant": "success"
                });
                this.dispatchEvent(event);
                this.removeGroupFromList(groupName);
            })
            .catch((error) => {
                this.error = error;
            });
    }

    removeGroupFromList(groupName) { 
        this.showLoadingSpinner = true;
        this.value = null; 
        this.chosenValue = '';  
        console.log('removing from list ', groupName);
        let newItems = [];
        let itemsInBox = this.items.length;
        for(let i=0; i<itemsInBox; i++)  {
            if (this.items[i].value === groupName) { 
                console.log('*** removed');
            } else { 
                newItems.push(this.items[i]);  
            } 
        }  
        this.items = newItems;
        this.fireGroupChangeEvent(this.value);
        this.showLoadingSpinner = false;
    }

    doRefreshGroups(groupName){
        this.showLoadingSpinner = true;
        if (groupName != null) { 
            refreshGroups()
            .then(result => {
                if (result) {
                    //create array with elements retrieved from controller
                    //here value will be Group name and label of combobox will be Name (Less 'PCG ')
                    console.log('got data via refresh - length of data is ', result.length);
                    this.items = [];
                    for(i=0; i<result.length; i++)  {
                        console.log(result[i].Name);
                        this.items = [...this.items ,{value: result[i].Name , label: result[i].Name.substring(4, 99)} ];                                   
                    }  
                    this.value = 'PCG ' + groupName; 
                    this.chosenValue = this.value;  
                    this.fireGroupChangeEvent(this.value);
                    // this.selectGroup (groupName); 
                    this.error = undefined;
                } else if (error) {
                    this.error = error;
                }
                this.showLoadingSpinner = false;
                return;
            })
            .catch(error => {
                console.log('Refresh error ====> '+error);
            });
        }
    }

    doRefreshGroupsAll(){
        this.showLoadingSpinner = true;
        refreshGroups()
        .then(result => {
            if (result) {
                //create array with elements retrieved from controller
                //here value will be Group name and label of combobox will be Name (Less 'PCG ')
                console.log('got data via refresh all - length of data is ', result.length);
                this.items = [];
                for(i=0; i<result.length; i++)  {
                    console.log(result[i].Name);
                    this.items = [...this.items ,{value: result[i].Name , label: result[i].Name.substring(4, 99)} ];                                   
                }  
                this.value = null; 
                this.chosenValue = '';  
                this.fireGroupChangeEvent(this.value);
                // this.selectGroup (groupName); 
                this.error = undefined;
            } else if (error) {
                this.error = error;
            }
            this.showLoadingSpinner = false;
            return;
        })
        .catch(error => {
            console.log('Refresh error ====> '+error);
        });
    }

    selectGroup (groupName) {
        if (this.isValidGroupValue(groupName)) {
            console.log('changing group to ' + groupName);
            this.value = 'PCG ' + groupName;  // select new group
        }
    } 

    isValidGroupValue(groupName) {
        if (groupName && groupName.length > 0) {
            for (i=0 ; i < this.items.length; i++) {
                console.log('comparing group of ' + groupName + ' to ' + items[i].value)
                if (groupName === items[i].value) {
                    return true;
                }
            }
        }
        return false;
    }

    //this value will be shown as selected value of combobox item
    get selectedValue(){
        return this.chosenValue;
    }

    get selectedLabel(){
        return this.chosenValue.substring(4, 99);
    }

    handleNewGroupClick(event) {
        // alert('new group');
        this.openNewGroupModal();
    }

    openNewGroupModal() {
        // to open modal set isModalOpen track value as true
        this.theInputs.groupName = '';
        this.isNewGroupModalOpen = true;
    }

    closeNewGroupModal() {
        // to close modal set isModalOpen track value as false
        this.isNewGroupModalOpen = false;
    }
    submitNewGroupDetails() {
        if (this.theInputs.groupName && this.theInputs.groupName.length > 0) {
            this.createNewGroup(this.theInputs.groupName);
            this.isNewGroupModalOpen = false;
        } else {
            // focus on input box with red border
        }
    }

    handleCloneGroupClick(event) {
        this.openCloneGroupModal();
    }

    openCloneGroupModal() {
        this.theInputs.groupName = '';
        this.isCloneGroupModalOpen = true;
    }

    closeCloneGroupModal() {
        this.isCloneGroupModalOpen = false;
    }

    submitCloneGroupDetails() {
        // let cloneSource = this.chosenValue.substring(4, 99);
        let cloneSource = this.chosenValue;
        if (this.theInputs.cloneName && this.theInputs.cloneName.length > 0) {
            this.createCloneGroup(cloneSource, this.theInputs.cloneName);
            this.isCloneGroupModalOpen = false;
            console.log('cloning ' + cloneSource + '->' + this.theInputs.cloneName);
        } else {
            // focus on input box with red border
        }
    }

    handleDeleteButtonClick(event) {
        // alert('new group');
        this.openConfirmModal();
    }

    openConfirmModal() {
        // to open modal set isModalOpen track value as true
        this.isConfirmModalOpen = true;
    }

    closeConfirmModal() {
        // to close modal set isModalOpen track value as false
        this.isConfirmModalOpen = false;
    }

    submitDeleteGroupDetails() {
        this.deleteOldGroup(this.chosenValue);
        this.isConfirmModalOpen = false;
    }
}