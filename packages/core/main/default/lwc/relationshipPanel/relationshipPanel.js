import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import Toast from 'lightning/toast';

import getRelationships from '@salesforce/apex/RelationshipController.getRelationships';
import removeRelationship from '@salesforce/apex/RelationshipController.removeRelationship';

import PANEL_TITLE from '@salesforce/label/c.Core_Relationship_PanelTitle';
import ADD_BUTTON from '@salesforce/label/c.Core_Relationship_AddButton';
import ADD_FORM_TITLE from '@salesforce/label/c.Core_Relationship_AddFormTitle';
import CANCEL_BUTTON from '@salesforce/label/c.Core_Relationship_CancelButton';
import EMPTY_MESSAGE from '@salesforce/label/c.Core_Relationship_Empty';
import FORMER_BADGE from '@salesforce/label/c.Core_Relationship_FormerBadge';
import LOAD_FAILED from '@salesforce/label/c.Core_Relationship_LoadFailed';
import REMOVE_BUTTON from '@salesforce/label/c.Core_Relationship_RemoveButton';
import REMOVE_FAILED from '@salesforce/label/c.Core_Relationship_RemoveFailed';
import REMOVE_SUCCESS from '@salesforce/label/c.Core_Relationship_RemoveSuccess';
import SAVE_FAILED from '@salesforce/label/c.Core_Relationship_SaveFailed';
import SAVE_SUCCESS from '@salesforce/label/c.Core_Relationship_SaveSuccess';

const RELATIONSHIP_OBJECT = 'Relationship__c';
const FORM_FIELDS = ['Type__c', 'Status__c', 'Start_Date__c', 'End_Date__c', 'Description__c'];

/**
 * Every relationship one person has, read from their side, with a form that adds another.
 *
 * The card never asks whether the person it is sitting on is held as a contact or as an
 * account. It reads the record's object name once, to decide which pair of lookups a new
 * relationship should fill in, and the server does the rest.
 */
export default class RelationshipPanel extends LightningElement {
  @api recordId;
  @api objectApiName;

  labels = {
    panelTitle: PANEL_TITLE,
    addButton: ADD_BUTTON,
    addFormTitle: ADD_FORM_TITLE,
    cancelButton: CANCEL_BUTTON,
    emptyMessage: EMPTY_MESSAGE,
    formerBadge: FORMER_BADGE,
    removeButton: REMOVE_BUTTON
  };

  relationshipObject = RELATIONSHIP_OBJECT;
  formFields = FORM_FIELDS;
  showForm = false;
  errorMessage;

  relationships = [];
  wiredResult;

  @wire(getRelationships, { personId: '$recordId' })
  receiveRelationships(result) {
    this.wiredResult = result;
    if (result.data) {
      this.relationships = result.data.map((relationship) => this.decorate(relationship));
      this.errorMessage = undefined;
    } else if (result.error) {
      this.relationships = [];
      this.errorMessage = LOAD_FAILED;
    }
  }

  get hasRelationships() {
    return this.relationships.length > 0;
  }

  get isEmpty() {
    return !this.hasRelationships && !this.errorMessage;
  }

  /** The lookup that ties this side of a new relationship to the record the card sits on. */
  get personFieldName() {
    return this.objectApiName === 'Contact' ? 'Contact__c' : 'Person_Account__c';
  }

  /** The lookup for the other person, on the same object as this one. */
  get relatedPersonFieldName() {
    return this.objectApiName === 'Contact' ? 'Related_Contact__c' : 'Related_Person_Account__c';
  }

  decorate(relationship) {
    return {
      ...relationship,
      cardClass: relationship.isFormer
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

  async handleRemove(event) {
    const relationshipId = event.target.dataset.id;
    try {
      const remaining = await removeRelationship({ relationshipId, personId: this.recordId });
      this.relationships = remaining.map((relationship) => this.decorate(relationship));
      this.errorMessage = undefined;
      this.notify(REMOVE_SUCCESS, 'success');
      this.refresh();
    } catch {
      this.errorMessage = REMOVE_FAILED;
      this.notify(REMOVE_FAILED, 'error');
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
