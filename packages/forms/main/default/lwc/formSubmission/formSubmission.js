import { LightningElement, api, wire } from 'lwc';
import { gql, graphql } from 'lightning/graphql';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import FORM_SUBMISSION_OBJECT from '@salesforce/schema/Form_Submission__c';
import processAgain from '@salesforce/apex/FormSubmissionController.processAgain';
import { HELP, KIND_LABELS, LABELS, actionText, messageFrom, resultText } from 'c/formText';
import { submissionView } from 'c/formSubmissionModel';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';

/** The submission, with its form's name and the version it answered, read as the person. */
const SUBMISSION = gql`
  query formSubmission($submissionId: ID) {
    uiapi {
      query {
        Form_Submission__c(where: { Id: { eq: $submissionId } }, first: 1) {
          edges {
            node {
              Id
              Form_Name__c {
                value
              }
              Form_Version__c {
                value
              }
              Status__c {
                value
              }
              Message__c {
                value
              }
              Answers__c {
                value
              }
              Outcome__c {
                value
              }
              Form__r {
                Name {
                  value
                }
              }
              Form_Version__r {
                Definition__c {
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
    formName: (node.Form__r && valueOf(node.Form__r.Name)) || valueOf(node.Form_Name__c),
    formVersionId: valueOf(node.Form_Version__c),
    status: valueOf(node.Status__c),
    message: valueOf(node.Message__c),
    answersJson: valueOf(node.Answers__c),
    outcomeJson: valueOf(node.Outcome__c),
    definitionJson: node.Form_Version__r ? valueOf(node.Form_Version__r.Definition__c) : null
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
      const edges = data.uiapi.query.Form_Submission__c.edges;
      this.submission = submissionOf(edges.length ? edges[0].node : null);
      this.loading = false;
    } else if (errors) {
      this.errorMessage = messageFrom(errors);
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
