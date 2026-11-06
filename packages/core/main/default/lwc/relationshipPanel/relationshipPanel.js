import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { NavigationMixin } from 'lightning/navigation';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { gql, graphql } from 'lightning/graphql';
import { deleteRecord, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import getTurnedOffTypes from '@salesforce/apex/RelationshipController.getTurnedOffTypes';
import BarnConfirmModal from 'c/barnConfirmModal';
import { iconFor } from 'c/barnIcons';
import { localIsoDate } from 'c/findCsv';
import { initialsOf, opensElsewhere, recordHref } from 'c/recordRows';
import { followLinkInWorkspace } from 'c/workspaceTabs';

import RELATIONSHIP_SCHEMA from '@salesforce/schema/Relationship__c';
import END_DATE_FIELD from '@salesforce/schema/Relationship__c.End_Date__c';
import TYPE_FIELD from '@salesforce/schema/Relationship__c.Type__c';

import ACTIONS_FOR from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';
import EDIT_ACTION from '@salesforce/label/c.Core_CmdtManager_EditAction';
import END_ACTION from '@salesforce/label/c.Core_Relationship_EndAction';
import PANEL_TITLE from '@salesforce/label/c.Core_Feature_Relationships_Name';
import ADD_BUTTON from '@salesforce/label/c.Core_Relationship_AddButton';
import ADD_FORM_TITLE from '@salesforce/label/c.Core_Relationship_AddFormTitle';
import CANCEL_BUTTON from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import EMPTY_HEADING from '@salesforce/label/c.Core_Relationship_EmptyHeading';
import FORMER_BADGE from '@salesforce/label/c.Core_Affiliation_FormerBadge';
import LOADING from '@salesforce/label/c.Core_Relationship_Loading';
import REMOVE_BUTTON from '@salesforce/label/c.Core_Find_Remove';
import UNNAMED_PERSON from '@salesforce/label/c.Core_Affiliation_UnnamedPerson';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const RELATIONSHIP_OBJECT = 'Relationship__c';
// Type is a picker of its own, so a type the administrator turned off is not offered.
const FORM_FIELDS = ['Status__c', 'Start_Date__c', 'End_Date__c', 'Description__c'];
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
export default class RelationshipPanel extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  @wire(EnclosingTabId) enclosingTabId;

  icons = { relationship: iconFor('Relationship__c') };

  /** True while a row action is being saved, so its menu cannot start a second one. */
  busy = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  @api recordId;
  @api objectApiName;

  labels = {
    panelTitle: PANEL_TITLE,
    addButton: ADD_BUTTON,
    addFormTitle: ADD_FORM_TITLE,
    cancelButton: CANCEL_BUTTON,
    get emptyMessage() {
      return helpText('Core', 'Core_Relationship_Empty');
    },
    emptyHeading: EMPTY_HEADING,
    formerBadge: FORMER_BADGE,
    loading: LOADING,
    removeButton: REMOVE_BUTTON,
    editAction: EDIT_ACTION,
    endAction: END_ACTION
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
      this.errorMessage = helpText('Core', 'Core_Relationship_LoadFailed');
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

  typeValues = [];
  turnedOffTypes = [];
  typeValue;

  @wire(getPicklistValues, {
    recordTypeId: '$relationshipInfo.defaultRecordTypeId',
    fieldApiName: TYPE_FIELD
  })
  receiveTypeValues({ data }) {
    if (data) {
      this.typeValues = data.values;
    }
  }

  // Lower case Type values turned off (ADR-0170); the server refuses them anyway.
  @wire(getTurnedOffTypes)
  receiveTurnedOffTypes({ data }) {
    if (data) {
      this.turnedOffTypes = data;
    }
  }

  get typeLabel() {
    const field = this.relationshipInfo && this.relationshipInfo.fields[TYPE_FIELD.fieldApiName];
    return field ? field.label : '';
  }

  /** The Type choices for a new relationship: every active value not turned off. */
  get typeOptions() {
    const off = new Set(this.turnedOffTypes);
    return this.typeValues
      .filter((entry) => !off.has(String(entry.value).toLowerCase()))
      .map((entry) => ({ label: entry.label, value: entry.value }));
  }

  handleTypeChange(event) {
    this.typeValue = event.detail.value;
  }

  /** Adds the chosen type to the fields the form saves. */
  handleFormSubmit(event) {
    event.preventDefault();
    const picker = this.template.querySelector('[data-id="type"]');
    if (picker && !picker.reportValidity()) {
      return;
    }
    const fields = { ...event.detail.fields, [TYPE_FIELD.fieldApiName]: this.typeValue };
    this.template.querySelector('lightning-record-edit-form').submit(fields);
  }

  /** Add relationship, only for someone who can create relationships (Read Only cannot). */
  get canAdd() {
    return Boolean(this.relationshipInfo && this.relationshipInfo.createable);
  }

  /** Remove, only for someone who can delete relationships. */
  get canRemove() {
    return Boolean(this.relationshipInfo && this.relationshipInfo.deletable);
  }

  /** Edit, only for someone who can edit relationships. */
  get canEdit() {
    return Boolean(this.relationshipInfo && this.relationshipInfo.updateable);
  }

  /** End It writes End Date, so it needs edit on relationships and on that field. */
  get canEndRelationships() {
    const info = this.relationshipInfo;
    const field = info && info.fields && info.fields[END_DATE_FIELD.fieldApiName];
    return Boolean(info && info.updateable && field && field.updateable);
  }

  /**
   * The rows with the actions this user may take on each, worked out on the way to the
   * screen because access arrives on its own wire, before or after the relationships.
   */
  get rows() {
    const canEnd = this.canEndRelationships;
    const canEdit = this.canEdit;
    const canRemove = this.canRemove;
    return this.relationships.map((relationship) => {
      const rowCanEnd = canEnd && !relationship.isFormer;
      return {
        ...relationship,
        canEnd: rowCanEnd,
        hasActions: canEdit || rowCanEnd || canRemove
      };
    });
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
      initials: initialsOf(relationship.relatedPersonName),
      href: recordHref(relationship.id),
      actionsLabel: ACTIONS_FOR.replace('{0}', relationship.relatedPersonName),
      rowClass: relationship.isFormer ? 'slds-item slds-theme_shade' : 'slds-item'
    };
  }

  /** A row's name opens the relationship; in a console, as a subtab beside the person. */
  handleOpenRecord(event) {
    const recordId = event.currentTarget.dataset.recordId;
    const pageReference = {
      type: 'standard__recordPage',
      attributes: { recordId, actionName: 'view' }
    };
    const navigate = () => this[NavigationMixin.Navigate](pageReference);
    if (followLinkInWorkspace(this, event, { recordId }, navigate) || opensElsewhere(event)) {
      return;
    }
    event.preventDefault();
    navigate();
  }

  /** A choice from a row's menu: Edit, End It or Remove. */
  handleRowAction(event) {
    const relationshipId = event.target.dataset.recordId;
    const action = event.detail.value;
    if (action === 'edit') {
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: {
          recordId: relationshipId,
          objectApiName: RELATIONSHIP_OBJECT,
          actionName: 'edit'
        }
      });
      return undefined;
    }
    if (action === 'end') {
      return this.endRelationship(relationshipId);
    }
    return this.removeRelationship(relationshipId);
  }

  /** Sets End Date to today after a confirm; the save makes it Former on both people. */
  async endRelationship(relationshipId) {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: helpText('Core', 'Core_Relationship_EndConfirmTitle'),
      message: helpText('Core', 'Core_Relationship_EndConfirm'),
      confirmLabel: END_ACTION,
      cancelLabel: CANCEL_BUTTON
    });
    if (!confirmed) {
      return;
    }
    this.busy = true;
    try {
      await updateRecord({
        fields: { Id: relationshipId, [END_DATE_FIELD.fieldApiName]: localIsoDate(new Date()) }
      });
      this.errorMessage = undefined;
      this.notify(helpText('Core', 'Core_Relationship_EndSuccess'), 'success');
      this.refresh();
    } catch {
      this.errorMessage = helpText('Core', 'Core_Relationship_EndFailed');
      this.notify(this.errorMessage, 'error');
    }
    this.busy = false;
  }

  handleAdd() {
    this.typeValue = undefined;
    this.showForm = true;
  }

  handleCancel() {
    this.showForm = false;
  }

  handleFormSuccess() {
    this.showForm = false;
    this.notify(helpText('Core', 'Core_Relationship_SaveSuccess'), 'success');
    this.refresh();
  }

  handleFormError() {
    this.errorMessage = helpText('Core', 'Core_Relationship_SaveFailed');
  }

  /** Removes both sides, after a confirm that points to End It for a relationship that ended. */
  async removeRelationship(relationshipId) {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: helpText('Core', 'Core_Relationship_RemoveConfirmTitle'),
      message: helpText('Core', 'Core_Relationship_RemoveConfirm'),
      confirmLabel: REMOVE_BUTTON,
      cancelLabel: CANCEL_BUTTON,
      confirmVariant: 'destructive'
    });
    if (!confirmed) {
      return;
    }
    try {
      // Deleting the other person's side is the trigger's work.
      await deleteRecord(relationshipId);
      this.errorMessage = undefined;
      this.notify(helpText('Core', 'Core_Relationship_RemoveSuccess'), 'success');
      this.refresh();
    } catch {
      this.errorMessage = helpText('Core', 'Core_Relationship_RemoveFailed');
      this.notify(helpText('Core', 'Core_Relationship_RemoveFailed'), 'error');
    }
  }

  refresh() {
    return this.refreshRelationships ? this.refreshRelationships() : Promise.resolve();
  }

  notify(message, variant) {
    Toast.show({ label: message, variant }, this);
  }
}
