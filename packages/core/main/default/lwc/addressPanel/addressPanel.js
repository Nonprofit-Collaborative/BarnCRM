import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import Toast from 'lightning/toast';

import getAddresses from '@salesforce/apex/AddressController.getAddresses';
import setDefault from '@salesforce/apex/AddressController.setDefault';

import PANEL_TITLE from '@salesforce/label/c.Core_Address_PanelTitle';
import ADD_BUTTON from '@salesforce/label/c.Core_Address_AddButton';
import ADD_FORM_TITLE from '@salesforce/label/c.Core_Address_AddFormTitle';
import CANCEL_BUTTON from '@salesforce/label/c.Core_Address_CancelButton';
import DEFAULT_BADGE from '@salesforce/label/c.Core_Address_DefaultBadge';
import EMPTY_MESSAGE from '@salesforce/label/c.Core_Address_Empty';
import LOAD_FAILED from '@salesforce/label/c.Core_Address_LoadFailed';
import SAVE_FAILED from '@salesforce/label/c.Core_Address_SaveFailed';
import SAVE_SUCCESS from '@salesforce/label/c.Core_Address_SaveSuccess';
import SEASONAL_RANGE from '@salesforce/label/c.Core_Address_SeasonalRange';
import SEASONAL_RANGE_TO from '@salesforce/label/c.Core_Address_SeasonalRangeTo';
import SET_DEFAULT_BUTTON from '@salesforce/label/c.Core_Address_SetDefaultButton';
import SET_DEFAULT_FAILED from '@salesforce/label/c.Core_Address_SetDefaultFailed';
import SET_DEFAULT_SUCCESS from '@salesforce/label/c.Core_Address_SetDefaultSuccess';

const ADDRESS_OBJECT = 'Address__c';
const FORM_FIELDS = [
  'Type__c',
  'Street__c',
  'City__c',
  'State__c',
  'Postal_Code__c',
  'Country__c',
  'Seasonal_Start_Month__c',
  'Seasonal_Start_Day__c',
  'Seasonal_End_Month__c',
  'Seasonal_End_Day__c'
];

/**
 * Every address a household, an organization, or a person has on file, with the one in use
 * badged, a way to move that badge, and a form to add another.
 */
export default class AddressPanel extends LightningElement {
  @api recordId;
  @api objectApiName;

  labels = {
    panelTitle: PANEL_TITLE,
    addButton: ADD_BUTTON,
    addFormTitle: ADD_FORM_TITLE,
    cancelButton: CANCEL_BUTTON,
    defaultBadge: DEFAULT_BADGE,
    emptyMessage: EMPTY_MESSAGE,
    setDefaultButton: SET_DEFAULT_BUTTON
  };

  addressObject = ADDRESS_OBJECT;
  formFields = FORM_FIELDS;
  showForm = false;
  errorMessage;

  addresses = [];
  wiredResult;

  @wire(getAddresses, { ownerId: '$recordId' })
  receiveAddresses(result) {
    this.wiredResult = result;
    if (result.data) {
      this.addresses = result.data.map((address) => this.decorate(address));
      this.errorMessage = undefined;
    } else if (result.error) {
      this.addresses = [];
      this.errorMessage = LOAD_FAILED;
    }
  }

  get hasAddresses() {
    return this.addresses.length > 0;
  }

  get isEmpty() {
    return !this.hasAddresses && !this.errorMessage;
  }

  /** The lookup that ties a new address to the record the panel is sitting on. */
  get ownerFieldName() {
    return this.objectApiName === 'Contact' ? 'Contact__c' : 'Account__c';
  }

  decorate(address) {
    const lines = [address.city, address.state, address.postalCode]
      .filter((part) => part)
      .join(' ');
    let seasonalText;
    if (address.isSeasonal && address.seasonalStart && address.seasonalEnd) {
      seasonalText = `${SEASONAL_RANGE} ${address.seasonalStart} ${SEASONAL_RANGE_TO} ${address.seasonalEnd}`;
    }
    return {
      ...address,
      cityLine: lines,
      seasonalText,
      showSetDefault: !address.isDefault,
      cardClass: address.isDefault
        ? 'slds-box slds-m-bottom_x-small slds-theme_shade'
        : 'slds-box slds-m-bottom_x-small'
    };
  }

  handleAdd() {
    this.showForm = true;
  }

  handleCancel() {
    this.showForm = false;
  }

  handleFormSuccess() {
    this.showForm = false;
    this.notify(SAVE_SUCCESS, 'success');
    this.refresh();
  }

  handleFormError() {
    this.errorMessage = SAVE_FAILED;
  }

  async handleSetDefault(event) {
    const addressId = event.target.dataset.id;
    try {
      const updated = await setDefault({ addressId });
      this.addresses = updated.map((address) => this.decorate(address));
      this.errorMessage = undefined;
      this.notify(SET_DEFAULT_SUCCESS, 'success');
      this.refresh();
    } catch {
      this.errorMessage = SET_DEFAULT_FAILED;
      this.notify(SET_DEFAULT_FAILED, 'error');
    }
  }

  refresh() {
    if (this.wiredResult) {
      refreshApex(this.wiredResult);
    }
  }

  notify(message, variant) {
    Toast.show({ label: message, variant }, this);
  }
}
