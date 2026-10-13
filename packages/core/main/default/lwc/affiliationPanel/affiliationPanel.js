import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import Toast from 'lightning/toast';

import getAffiliations from '@salesforce/apex/AffiliationController.getAffiliations';
import makePrimary from '@salesforce/apex/AffiliationController.makePrimary';

import PANEL_TITLE from '@salesforce/label/c.Core_Affiliation_PanelTitle';
import ADD_BUTTON from '@salesforce/label/c.Core_Affiliation_AddButton';
import ADD_FORM_TITLE from '@salesforce/label/c.Core_Affiliation_AddFormTitle';
import CANCEL_BUTTON from '@salesforce/label/c.Core_Affiliation_CancelButton';
import EMPTY_MESSAGE from '@salesforce/label/c.Core_Affiliation_Empty';
import FORMER_BADGE from '@salesforce/label/c.Core_Affiliation_FormerBadge';
import LOAD_FAILED from '@salesforce/label/c.Core_Affiliation_LoadFailed';
import MAKE_PRIMARY_BUTTON from '@salesforce/label/c.Core_Affiliation_MakePrimaryButton';
import MAKE_PRIMARY_FAILED from '@salesforce/label/c.Core_Affiliation_MakePrimaryFailed';
import MAKE_PRIMARY_SUCCESS from '@salesforce/label/c.Core_Affiliation_MakePrimarySuccess';
import PRIMARY_BADGE from '@salesforce/label/c.Core_Affiliation_PrimaryBadge';
import SAVE_FAILED from '@salesforce/label/c.Core_Affiliation_SaveFailed';
import SAVE_SUCCESS from '@salesforce/label/c.Core_Affiliation_SaveSuccess';

const AFFILIATION_OBJECT = 'Affiliation__c';
const FORM_FIELDS = [
  'Role__c',
  'Status__c',
  'Is_Primary__c',
  'Start_Date__c',
  'End_Date__c',
  'Description__c'
];

/**
 * The organizations one person is connected to, or the people connected to one organization,
 * with the primary one badged and a form that adds another.
 *
 * A row shows the end of the connection the reader is not already looking at: on a person's
 * record it names the organization, and on an organization's record it names the person. The
 * server decides which, because an account is an organization in one org and a person in
 * another.
 */
export default class AffiliationPanel extends LightningElement {
  @api recordId;
  @api objectApiName;

  labels = {
    panelTitle: PANEL_TITLE,
    addButton: ADD_BUTTON,
    addFormTitle: ADD_FORM_TITLE,
    cancelButton: CANCEL_BUTTON,
    emptyMessage: EMPTY_MESSAGE,
    formerBadge: FORMER_BADGE,
    makePrimaryButton: MAKE_PRIMARY_BUTTON,
    primaryBadge: PRIMARY_BADGE
  };

  affiliationObject = AFFILIATION_OBJECT;
  formFields = FORM_FIELDS;
  showForm = false;
  errorMessage;

  affiliations = [];
  wiredResult;

  @wire(getAffiliations, { ownerId: '$recordId' })
  receiveAffiliations(result) {
    this.wiredResult = result;
    if (result.data) {
      this.affiliations = result.data.map((affiliation) => this.decorate(affiliation));
      this.errorMessage = undefined;
    } else if (result.error) {
      this.affiliations = [];
      this.errorMessage = LOAD_FAILED;
    }
  }

  get hasAffiliations() {
    return this.affiliations.length > 0;
  }

  get isEmpty() {
    return !this.hasAffiliations && !this.errorMessage;
  }

  /** The lookup a new affiliation fills in for the record the card sits on. */
  get ownerFieldName() {
    if (this.objectApiName === 'Contact') {
      return 'Contact__c';
    }
    return this.isOrganizationRecord ? 'Organization__c' : 'Person_Account__c';
  }

  /** The lookup for the other end of a new affiliation. */
  get otherEndFieldName() {
    return this.ownerFieldName === 'Organization__c' ? 'Person_Account__c' : 'Organization__c';
  }

  /**
   * Whether the record this card sits on is being read as an organization. Everything already
   * on file is the evidence: if any affiliation names this record as its organization, this is
   * an organization's card.
   */
  get isOrganizationRecord() {
    return this.affiliations.some((affiliation) => affiliation.readFromOrganization);
  }

  decorate(affiliation) {
    return {
      ...affiliation,
      headline: affiliation.readFromOrganization
        ? affiliation.personName
        : affiliation.organizationName,
      showMakePrimary: !affiliation.isPrimary && !affiliation.isFormer,
      cardClass: affiliation.isFormer
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

  async handleMakePrimary(event) {
    const affiliationId = event.target.dataset.id;
    try {
      const updated = await makePrimary({ affiliationId, ownerId: this.recordId });
      this.affiliations = updated.map((affiliation) => this.decorate(affiliation));
      this.errorMessage = undefined;
      this.notify(MAKE_PRIMARY_SUCCESS, 'success');
      this.refresh();
    } catch {
      this.errorMessage = MAKE_PRIMARY_FAILED;
      this.notify(MAKE_PRIMARY_FAILED, 'error');
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
