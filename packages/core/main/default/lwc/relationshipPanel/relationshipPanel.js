import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { gql, graphql } from 'lightning/graphql';
import { deleteRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

import RELATIONSHIP_SCHEMA from '@salesforce/schema/Relationship__c';

import PANEL_TITLE from '@salesforce/label/c.Core_Relationship_PanelTitle';
import ADD_BUTTON from '@salesforce/label/c.Core_Relationship_AddButton';
import ADD_FORM_TITLE from '@salesforce/label/c.Core_Relationship_AddFormTitle';
import CANCEL_BUTTON from '@salesforce/label/c.Core_Relationship_CancelButton';
import EMPTY_MESSAGE from '@salesforce/label/c.Core_Relationship_Empty';
import EMPTY_HEADING from '@salesforce/label/c.Core_Relationship_EmptyHeading';
import FORMER_BADGE from '@salesforce/label/c.Core_Relationship_FormerBadge';
import LOAD_FAILED from '@salesforce/label/c.Core_Relationship_LoadFailed';
import LOADING from '@salesforce/label/c.Core_Relationship_Loading';
import REMOVE_BUTTON from '@salesforce/label/c.Core_Relationship_RemoveButton';
import REMOVE_FAILED from '@salesforce/label/c.Core_Relationship_RemoveFailed';
import REMOVE_SUCCESS from '@salesforce/label/c.Core_Relationship_RemoveSuccess';
import SAVE_FAILED from '@salesforce/label/c.Core_Relationship_SaveFailed';
import SAVE_SUCCESS from '@salesforce/label/c.Core_Relationship_SaveSuccess';
import UNNAMED_PERSON from '@salesforce/label/c.Core_Relationship_UnnamedPerson';

const RELATIONSHIP_OBJECT = 'Relationship__c';
const FORM_FIELDS = ['Type__c', 'Status__c', 'Start_Date__c', 'End_Date__c', 'Description__c'];
const CURRENT_STATUS = 'Current';

/**
 * The relationships described from this person's side, read as the user through the
 * platform, so field security and sharing apply. The person is a contact (Contact__c) or an
 * account (Person_Account__c); both lookups exist in every org. At most 2,000, the most a
 * query returns at once.
 */
const RELATIONSHIPS_QUERY = gql`
  query relationshipPanel($personId: ID) {
    uiapi {
      query {
        Relationship__c(
          where: {
            or: [{ Contact__c: { eq: $personId } }, { Person_Account__c: { eq: $personId } }]
          }
          orderBy: { CreatedDate: { order: DESC } }
          first: 2000
        ) {
          edges {
            node {
              Id
              Related_Contact__r {
                Name {
                  value
                }
              }
              Related_Person_Account__r {
                Name {
                  value
                }
              }
              Type__c {
                value
                displayValue
              }
              Status__c {
                value
              }
              Description__c {
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

function nameOf(parent) {
  return parent && parent.Name ? parent.Name.value : null;
}

/** One relationship as the card draws it, from this person's side. */
function toView(node) {
  const type = node.Type__c || {};
  return {
    id: node.Id,
    relatedPersonName:
      nameOf(node.Related_Contact__r) || nameOf(node.Related_Person_Account__r) || UNNAMED_PERSON,
    relationshipType: type.displayValue || type.value || null,
    isFormer: read(node.Status__c) !== CURRENT_STATUS,
    description: read(node.Description__c)
  };
}

/**
 * Every relationship one person has, read from their side, with a form that adds another.
 *
 * The card never asks whether the person it is sitting on is held as a contact or as an
 * account. It reads the record's object name once, to decide which pair of lookups a new
 * relationship should fill in; the query reads both lookups.
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
    emptyHeading: EMPTY_HEADING,
    formerBadge: FORMER_BADGE,
    loading: LOADING,
    removeButton: REMOVE_BUTTON
  };

  relationshipObject = RELATIONSHIP_OBJECT;
  formFields = FORM_FIELDS;
  showForm = false;
  errorMessage;

  relationships = [];
  loaded = false;
  refreshRelationships;

  get queryVariables() {
    return this.recordId ? { personId: this.recordId } : undefined;
  }

  @wire(graphql, { query: RELATIONSHIPS_QUERY, variables: '$queryVariables' })
  receiveRelationships(result) {
    this.refreshRelationships = result.refresh;
    if (result.errors && result.errors.length) {
      this.relationships = [];
      this.errorMessage = LOAD_FAILED;
      this.loaded = true;
    } else if (result.data) {
      const views = result.data.uiapi.query.Relationship__c.edges.map((edge) => toView(edge.node));
      // Current ones first, then newest first (a stable sort keeps the query's order).
      views.sort((a, b) => Number(a.isFormer) - Number(b.isFormer));
      this.relationships = views.map((relationship) => this.decorate(relationship));
      this.errorMessage = undefined;
      this.loaded = true;
    }
  }

  /** What the user may do with relationships; nothing is offered until it is known. */
  relationshipInfo;

  @wire(getObjectInfo, { objectApiName: RELATIONSHIP_SCHEMA })
  receiveRelationshipInfo({ data }) {
    if (data) {
      this.relationshipInfo = data;
    }
  }

  /** Add relationship, only for someone who can create relationships (Read Only cannot). */
  get canAdd() {
    return Boolean(this.relationshipInfo && this.relationshipInfo.createable);
  }

  /** Remove, only for someone who can delete relationships. */
  get canRemove() {
    return Boolean(this.relationshipInfo && this.relationshipInfo.deletable);
  }

  get isLoading() {
    return !this.loaded;
  }

  get hasRelationships() {
    return this.relationships.length > 0;
  }

  get isEmpty() {
    return this.loaded && !this.hasRelationships && !this.errorMessage;
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
      // Deleting the other person's side is the trigger's work.
      await deleteRecord(relationshipId);
      this.errorMessage = undefined;
      this.notify(REMOVE_SUCCESS, 'success');
      this.refresh();
    } catch {
      this.errorMessage = REMOVE_FAILED;
      this.notify(REMOVE_FAILED, 'error');
    }
  }

  refresh() {
    return this.refreshRelationships ? this.refreshRelationships() : Promise.resolve();
  }

  notify(message, variant) {
    Toast.show({ label: message, variant }, this);
  }
}
