import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { gql, graphql } from 'lightning/graphql';
import { notifyRecordUpdateAvailable, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import LOCALE from '@salesforce/i18n/locale';

import ADDRESS_SCHEMA from '@salesforce/schema/Address__c';
import ID_FIELD from '@salesforce/schema/Address__c.Id';
import IS_DEFAULT_FIELD from '@salesforce/schema/Address__c.Is_Default__c';

import PANEL_TITLE from '@salesforce/label/c.Core_Address_PanelTitle';
import ADD_BUTTON from '@salesforce/label/c.Core_Address_AddButton';
import ADD_FORM_TITLE from '@salesforce/label/c.Core_Address_AddFormTitle';
import CANCEL_BUTTON from '@salesforce/label/c.Core_Address_CancelButton';
import DEFAULT_BADGE from '@salesforce/label/c.Core_Address_DefaultBadge';
import EMPTY_MESSAGE from '@salesforce/label/c.Core_Address_Empty';
import LOAD_FAILED from '@salesforce/label/c.Core_Address_LoadFailed';
import LOADING from '@salesforce/label/c.Core_Address_Loading';
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
const SEASONAL_TYPE = 'Seasonal';

/**
 * The record's addresses, read as the user through the platform, so field security and
 * sharing apply and the card picks up edits made elsewhere on the page. The record is a
 * household or organization (Account__c), a person stored as a contact (Contact__c) or a
 * person stored as an account (Person_Account__c); all three lookups exist in every org.
 * At most 2,000, the most a query returns at once.
 */
const ADDRESSES_QUERY = gql`
  query addressPanel($ownerId: ID) {
    uiapi {
      query {
        Address__c(
          where: {
            or: [
              { Account__c: { eq: $ownerId } }
              { Contact__c: { eq: $ownerId } }
              { Person_Account__c: { eq: $ownerId } }
            ]
          }
          orderBy: { CreatedDate: { order: DESC } }
          first: 2000
        ) {
          edges {
            node {
              Id
              Type__c {
                value
                displayValue
              }
              Street__c {
                value
              }
              City__c {
                value
              }
              State__c {
                value
              }
              Postal_Code__c {
                value
              }
              Country__c {
                value
              }
              Is_Default__c {
                value
              }
              Seasonal_Start_Month__c {
                value
              }
              Seasonal_Start_Day__c {
                value
              }
              Seasonal_End_Month__c {
                value
              }
              Seasonal_End_Day__c {
                value
              }
            }
          }
        }
      }
    }
  }
`;

function read(field) {
  return field ? field.value : null;
}

/** "January 1", in the reader's own language, from the two numbers we store. */
function monthAndDay(month, day) {
  if (!(month >= 1 && month <= 12 && day >= 1 && day <= 31)) {
    return null;
  }
  const name = new Intl.DateTimeFormat(LOCALE, { month: 'long', timeZone: 'UTC' }).format(
    new Date(Date.UTC(2001, Math.trunc(month) - 1, 1))
  );
  return `${name} ${Math.trunc(day)}`;
}

/** One address as the card draws it. */
function toView(node) {
  const type = node.Type__c || {};
  return {
    id: node.Id,
    addressType: type.displayValue || type.value || null,
    street: read(node.Street__c),
    city: read(node.City__c),
    state: read(node.State__c),
    postalCode: read(node.Postal_Code__c),
    country: read(node.Country__c),
    isDefault: read(node.Is_Default__c) === true,
    isSeasonal: type.value === SEASONAL_TYPE,
    seasonalStart: monthAndDay(
      read(node.Seasonal_Start_Month__c),
      read(node.Seasonal_Start_Day__c)
    ),
    seasonalEnd: monthAndDay(read(node.Seasonal_End_Month__c), read(node.Seasonal_End_Day__c))
  };
}

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
    loading: LOADING,
    setDefaultButton: SET_DEFAULT_BUTTON
  };

  addressObject = ADDRESS_OBJECT;
  formFields = FORM_FIELDS;
  showForm = false;
  errorMessage;

  addresses = [];
  loaded = false;
  refreshAddresses;

  get queryVariables() {
    return this.recordId ? { ownerId: this.recordId } : undefined;
  }

  @wire(graphql, { query: ADDRESSES_QUERY, variables: '$queryVariables' })
  receiveAddresses(result) {
    this.refreshAddresses = result.refresh;
    if (result.errors && result.errors.length) {
      this.addresses = [];
      this.errorMessage = LOAD_FAILED;
      this.loaded = true;
    } else if (result.data) {
      const views = result.data.uiapi.query.Address__c.edges.map((edge) => toView(edge.node));
      // The address in use first, then newest first (a stable sort keeps the query's order).
      views.sort((a, b) => Number(b.isDefault) - Number(a.isDefault));
      this.addresses = views.map((address) => this.decorate(address));
      this.errorMessage = undefined;
      this.loaded = true;
    }
  }

  /** What the user may do with addresses; nothing is offered until it is known. */
  addressInfo;

  @wire(getObjectInfo, { objectApiName: ADDRESS_SCHEMA })
  receiveAddressInfo({ data }) {
    if (data) {
      this.addressInfo = data;
    }
  }

  /** Add address, only for someone who can create addresses (Read Only cannot). */
  get canAdd() {
    return Boolean(this.addressInfo && this.addressInfo.createable);
  }

  /** Set as Primary writes Is Default (labelled Primary), so it needs edit on addresses and on that field. */
  get canSetDefault() {
    const info = this.addressInfo;
    const field = info && info.fields && info.fields[IS_DEFAULT_FIELD.fieldApiName];
    return Boolean(info && info.updateable && field && field.updateable);
  }

  get isLoading() {
    return !this.loaded;
  }

  get hasAddresses() {
    return this.addresses.length > 0;
  }

  get isEmpty() {
    return this.loaded && !this.hasAddresses && !this.errorMessage;
  }

  /**
   * The first address the record gets is the one in use (PEOPLE-49), so the form saves it as
   * the default. Only when the list was read and is empty: a failed read proves nothing.
   */
  get isFirstAddress() {
    return this.loaded && !this.errorMessage && !this.hasAddresses;
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
      // Clearing the old default and copying this one into the record's own address fields
      // is the trigger's work.
      await updateRecord({
        fields: { [ID_FIELD.fieldApiName]: addressId, [IS_DEFAULT_FIELD.fieldApiName]: true }
      });
      this.errorMessage = undefined;
      this.notify(SET_DEFAULT_SUCCESS, 'success');
      this.refresh();
    } catch {
      this.errorMessage = SET_DEFAULT_FAILED;
      this.notify(SET_DEFAULT_FAILED, 'error');
    }
  }

  /**
   * Reads the card again, and tells the record page its own address fields may have changed,
   * since a new or moved default is copied into them by the trigger.
   */
  refresh() {
    const reads = [notifyRecordUpdateAvailable([{ recordId: this.recordId }])];
    if (this.refreshAddresses) {
      reads.push(this.refreshAddresses());
    }
    return Promise.all(reads);
  }

  notify(message, variant) {
    Toast.show({ label: message, variant }, this);
  }
}
