import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { gql, graphql } from 'lightning/graphql';
import { notifyRecordUpdateAvailable, updateRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

import AFFILIATION_SCHEMA from '@salesforce/schema/Affiliation__c';
import ID_FIELD from '@salesforce/schema/Affiliation__c.Id';
import IS_PRIMARY_FIELD from '@salesforce/schema/Affiliation__c.Is_Primary__c';
import getCardContext from '@salesforce/apex/AffiliationController.getCardContext';

import PANEL_TITLE from '@salesforce/label/c.Core_Affiliation_PanelTitle';
import ADD_BUTTON from '@salesforce/label/c.Core_Affiliation_AddButton';
import ADD_FORM_TITLE from '@salesforce/label/c.Core_Affiliation_AddFormTitle';
import CANCEL_BUTTON from '@salesforce/label/c.Core_Affiliation_CancelButton';
import EMPTY_MESSAGE from '@salesforce/label/c.Core_Affiliation_Empty';
import FORMER_BADGE from '@salesforce/label/c.Core_Affiliation_FormerBadge';
import LOAD_FAILED from '@salesforce/label/c.Core_Affiliation_LoadFailed';
import LOADING from '@salesforce/label/c.Core_Affiliation_Loading';
import MAKE_PRIMARY_BUTTON from '@salesforce/label/c.Core_Affiliation_MakePrimaryButton';
import MAKE_PRIMARY_FAILED from '@salesforce/label/c.Core_Affiliation_MakePrimaryFailed';
import MAKE_PRIMARY_SUCCESS from '@salesforce/label/c.Core_Affiliation_MakePrimarySuccess';
import PRIMARY_BADGE from '@salesforce/label/c.Core_Affiliation_PrimaryBadge';
import SAVE_FAILED from '@salesforce/label/c.Core_Affiliation_SaveFailed';
import SAVE_SUCCESS from '@salesforce/label/c.Core_Affiliation_SaveSuccess';
import UNNAMED_PERSON from '@salesforce/label/c.Core_Affiliation_UnnamedPerson';

const AFFILIATION_OBJECT = 'Affiliation__c';
const FORM_FIELDS = [
  'Role__c',
  'Status__c',
  'Is_Primary__c',
  'Start_Date__c',
  'End_Date__c',
  'Description__c'
];
const CURRENT_STATUS = 'Current';

/**
 * Every affiliation naming the record, read as the user through the platform, so field
 * security and sharing apply. The record is the person (Contact__c, or Person_Account__c
 * where people are accounts; both lookups exist in every org) or the organization
 * (Organization__c). At most 2,000, the most a query returns at once.
 */
const AFFILIATIONS_QUERY = gql`
  query affiliationPanel($recordId: ID) {
    uiapi {
      query {
        Affiliation__c(
          where: {
            or: [
              { Contact__c: { eq: $recordId } }
              { Person_Account__c: { eq: $recordId } }
              { Organization__c: { eq: $recordId } }
            ]
          }
          orderBy: { CreatedDate: { order: DESC } }
          first: 2000
        ) {
          edges {
            node {
              Id
              Contact__c {
                value
              }
              Contact__r {
                Name {
                  value
                }
              }
              Person_Account__c {
                value
              }
              Person_Account__r {
                Name {
                  value
                }
              }
              Organization__c {
                value
              }
              Organization__r {
                Name {
                  value
                }
              }
              Role__c {
                value
              }
              Status__c {
                value
              }
              Is_Primary__c {
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

/** Salesforce IDs compare on their first 15 characters. */
function sameId(left, right) {
  return Boolean(left && right) && left.substring(0, 15) === right.substring(0, 15);
}

/** One affiliation as the card draws it, read from the end the record is not. */
function toView(node, recordId) {
  const status = read(node.Status__c);
  return {
    id: node.Id,
    personId: read(node.Contact__c) || read(node.Person_Account__c),
    personName: nameOf(node.Contact__r) || nameOf(node.Person_Account__r) || UNNAMED_PERSON,
    organizationId: read(node.Organization__c),
    organizationName: nameOf(node.Organization__r),
    role: read(node.Role__c),
    status,
    isFormer: status !== CURRENT_STATUS,
    isPrimary: read(node.Is_Primary__c) === true,
    description: read(node.Description__c),
    readFromOrganization: sameId(read(node.Organization__c), recordId)
  };
}

/**
 * The person's own affiliations first, then the organization's, as the card always listed
 * them. Within each, current before former, and on the person's side the primary one first.
 * The query already sorts newest first and the sort is stable, so that order holds within.
 */
function byCardOrder(a, b) {
  return (
    Number(a.readFromOrganization) - Number(b.readFromOrganization) ||
    Number(a.isFormer) - Number(b.isFormer) ||
    (a.readFromOrganization ? 0 : Number(b.isPrimary) - Number(a.isPrimary))
  );
}

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
    loading: LOADING,
    makePrimaryButton: MAKE_PRIMARY_BUTTON,
    primaryBadge: PRIMARY_BADGE
  };

  affiliationObject = AFFILIATION_OBJECT;
  formFields = FORM_FIELDS;
  showForm = false;
  errorMessage;

  affiliations = [];
  loaded = false;
  refreshAffiliations;

  get queryVariables() {
    return this.recordId ? { recordId: this.recordId } : undefined;
  }

  @wire(graphql, { query: AFFILIATIONS_QUERY, variables: '$queryVariables' })
  receiveAffiliations(result) {
    this.refreshAffiliations = result.refresh;
    if (result.errors && result.errors.length) {
      this.affiliations = [];
      this.errorMessage = LOAD_FAILED;
      this.loaded = true;
    } else if (result.data) {
      const views = result.data.uiapi.query.Affiliation__c.edges.map((edge) =>
        toView(edge.node, this.recordId)
      );
      views.sort(byCardOrder);
      this.affiliations = views.map((affiliation) => this.decorate(affiliation));
      this.errorMessage = undefined;
      this.loaded = true;
    }
  }

  /** What the user may do with affiliations; nothing is offered until it is known. */
  affiliationInfo;

  @wire(getObjectInfo, { objectApiName: AFFILIATION_SCHEMA })
  receiveAffiliationInfo({ data }) {
    if (data) {
      this.affiliationInfo = data;
    }
  }

  /** Add affiliation, only for someone who can create affiliations (Read Only cannot). */
  get canAdd() {
    return Boolean(this.affiliationInfo && this.affiliationInfo.createable);
  }

  /** Make primary writes Is Primary, so it needs edit on affiliations and on that field. */
  get canMakePrimary() {
    const info = this.affiliationInfo;
    const field = info && info.fields && info.fields[IS_PRIMARY_FIELD.fieldApiName];
    return Boolean(info && info.updateable && field && field.updateable);
  }

  get isLoading() {
    return !this.loaded;
  }

  get hasAffiliations() {
    return this.affiliations.length > 0;
  }

  get isEmpty() {
    return this.loaded && !this.hasAffiliations && !this.errorMessage;
  }

  /**
   * Which lookups a new affiliation fills in, decided by the server from the record itself:
   * an organization with no affiliations yet is still an organization.
   */
  @wire(getCardContext, { recordId: '$recordId' })
  cardContext;

  /** The lookup a new affiliation fills in for the record the card sits on. */
  get ownerFieldName() {
    const context = this.cardContext && this.cardContext.data;
    if (context) {
      return context.ownerField;
    }
    return this.objectApiName === 'Contact' ? 'Contact__c' : 'Organization__c';
  }

  /** The lookup for the other end of a new affiliation. */
  get otherEndFieldName() {
    const context = this.cardContext && this.cardContext.data;
    if (context) {
      return context.otherEndField;
    }
    return this.ownerFieldName === 'Organization__c' ? 'Contact__c' : 'Organization__c';
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
    const affiliation = this.affiliations.find((row) => row.id === affiliationId);
    try {
      // Clearing the person's other primary and copying the organization to their Primary
      // Affiliation field is the trigger's work.
      await updateRecord({
        fields: { [ID_FIELD.fieldApiName]: affiliationId, [IS_PRIMARY_FIELD.fieldApiName]: true }
      });
      this.errorMessage = undefined;
      this.notify(MAKE_PRIMARY_SUCCESS, 'success');
      this.refresh(affiliation ? [affiliation.personId] : []);
    } catch {
      this.errorMessage = MAKE_PRIMARY_FAILED;
      this.notify(MAKE_PRIMARY_FAILED, 'error');
    }
  }

  /**
   * Reads the card again, and tells the record page (and any person whose primary moved)
   * that their fields may have changed, since the trigger writes the Primary Affiliation.
   */
  refresh(otherRecordIds = []) {
    const recordIds = [this.recordId, ...otherRecordIds].filter(
      (id, index, all) => id && all.indexOf(id) === index
    );
    const reads = [notifyRecordUpdateAvailable(recordIds.map((recordId) => ({ recordId })))];
    if (this.refreshAffiliations) {
      reads.push(this.refreshAffiliations());
    }
    return Promise.all(reads);
  }

  notify(message, variant) {
    Toast.show({ label: message, variant }, this);
  }
}
