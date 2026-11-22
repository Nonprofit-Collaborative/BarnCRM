import { LightningElement, api, wire } from 'lwc';
import { gql, graphql } from 'lightning/graphql';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import FORM_SUBMISSION_OBJECT from '@salesforce/schema/Form_Submission__c';
import FORM_NAME_FIELD from '@salesforce/schema/Form_Submission__c.Form_Name__c';
import FORM_VERSION_FIELD from '@salesforce/schema/Form_Submission__c.Form_Version__c';
import STATUS_FIELD from '@salesforce/schema/Form_Submission__c.Status__c';
import MESSAGE_FIELD from '@salesforce/schema/Form_Submission__c.Message__c';
import ANSWERS_FIELD from '@salesforce/schema/Form_Submission__c.Answers__c';
import OUTCOME_FIELD from '@salesforce/schema/Form_Submission__c.Outcome__c';
import FORM_FIELD from '@salesforce/schema/Form_Submission__c.Form__c';
import DEFINITION_FIELD from '@salesforce/schema/Form_Version__c.Definition__c';
import processAgain from '@salesforce/apex/FormSubmissionController.processAgain';
import {
  HELP,
  KIND_LABELS,
  LABELS,
  actionText,
  graphqlMessage,
  messageFrom,
  resultText
} from 'c/formText';
import { submissionView } from 'c/formSubmissionModel';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';

// Every name comes from a schema import (ADR-0093 A1), so the query works with any namespace.
const SUBMISSION_OBJECT = FORM_SUBMISSION_OBJECT.objectApiName;
const FORM_NAME = FORM_NAME_FIELD.fieldApiName;
const FORM_VERSION = FORM_VERSION_FIELD.fieldApiName;
const STATUS = STATUS_FIELD.fieldApiName;
const MESSAGE = MESSAGE_FIELD.fieldApiName;
const ANSWERS = ANSWERS_FIELD.fieldApiName;
const OUTCOME = OUTCOME_FIELD.fieldApiName;
const DEFINITION = DEFINITION_FIELD.fieldApiName;
const parentOf = (fieldApiName) => fieldApiName.replace(/__c$/, '__r');
const FORM_PARENT = parentOf(FORM_FIELD.fieldApiName);
const VERSION_PARENT = parentOf(FORM_VERSION);

/** The submission, with its form's name and the version it answered, read as the person. */
const SUBMISSION = gql`
  query formSubmission($submissionId: ID) {
    uiapi {
      query {
        ${SUBMISSION_OBJECT}(where: { Id: { eq: $submissionId } }, first: 1) {
          edges {
            node {
              Id
              ${FORM_NAME} {
                value
              }
              ${FORM_VERSION} {
                value
              }
              ${STATUS} {
                value
              }
              ${MESSAGE} {
                value
              }
              ${ANSWERS} {
                value
              }
              ${OUTCOME} {
                value
              }
              ${FORM_PARENT} {
                Name {
                  value
                }
              }
              ${VERSION_PARENT} {
                ${DEFINITION} {
                  value
                }
              }
            }
          }
        }
      }
    }
  }
`;

const valueOf = (cell) => (cell ? cell.value : null);

/** A GraphQL submission node as the plain shape `c/formSubmissionModel` takes. */
function submissionOf(node) {
  if (!node) {
    return null;
  }
  return {
    id: node.Id,
    formName: (node[FORM_PARENT] && valueOf(node[FORM_PARENT].Name)) || valueOf(node[FORM_NAME]),
    formVersionId: valueOf(node[FORM_VERSION]),
    status: valueOf(node[STATUS]),
    message: valueOf(node[MESSAGE]),
    answersJson: valueOf(node[ANSWERS]),
    outcomeJson: valueOf(node[OUTCOME]),
    definitionJson: node[VERSION_PARENT] ? valueOf(node[VERSION_PARENT][DEFINITION]) : null
  };
}

/**
 * The Submission panel on a form submission (C-42a; canonical model 29ZY): the answers by
 * question, as the version filled in asked them, the records written or found, and Process
 * Again for a submission held for review or failed, after the right person or organization is
 * chosen on it (R-FS2). The submission is read through GraphQL and shaped by
 * `c/formSubmissionModel` (ADR-0093); Process Again stays on the server.
 */
export default class FormSubmission extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP);
  labels = LABELS;
  submission;
  canEdit = false;
  loading = true;
  busy = false;
  errorMessage;
  resultMessage;
  refreshSubmission;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
  }

  get submissionVariables() {
    return { submissionId: this.recordId };
  }

  @wire(graphql, { query: SUBMISSION, variables: '$submissionVariables' })
  wiredSubmission(result) {
    const { data, errors } = result;
    this.refreshSubmission = result.refresh;
    if (data) {
      const edges = data.uiapi.query[SUBMISSION_OBJECT].edges;
      this.submission = submissionOf(edges.length ? edges[0].node : null);
      this.loading = false;
    } else if (errors) {
      this.errorMessage = graphqlMessage(errors);
      this.loading = false;
    }
  }

  @wire(getObjectInfo, { objectApiName: FORM_SUBMISSION_OBJECT })
  wiredObjectInfo({ data }) {
    this.canEdit = Boolean(data && data.updateable);
  }

  get view() {
    return submissionView(this.submission, this.canEdit);
  }

  get loaded() {
    return !this.loading && Boolean(this.view);
  }

  get answers() {
    return (this.view.answers || []).map((row) => ({ ...row, shown: row.value || '' }));
  }

  get hasAnswers() {
    return this.answers.length > 0;
  }

  get records() {
    return (this.view.records || []).map((record) => ({
      key: record.key,
      url: `/lightning/r/${record.recordId}/view`,
      label: `${record.key} (${KIND_LABELS[record.kind] || record.objectName})`,
      action: actionText(record.action)
    }));
  }

  get hasRecords() {
    return this.records.length > 0;
  }

  get statusVariant() {
    if (this.view.status === 'Processed') {
      return 'success';
    }
    return this.view.status === 'Failed' ? 'error' : 'warning';
  }

  get canProcess() {
    return Boolean(this.view && this.view.canProcess);
  }

  async handleProcessAgain() {
    this.busy = true;
    this.errorMessage = '';
    try {
      const result = await processAgain({ submissionId: this.recordId });
      this.resultMessage = resultText(result);
      if (this.refreshSubmission) {
        await this.refreshSubmission();
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
    this.busy = false;
  }
}
