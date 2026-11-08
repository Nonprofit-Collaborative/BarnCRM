import { LightningElement, api } from 'lwc';
import getSubmission from '@salesforce/apex/FormSubmissionController.getSubmission';
import processAgain from '@salesforce/apex/FormSubmissionController.processAgain';
import { HELP, KIND_LABELS, LABELS, actionText, messageFrom, resultText } from 'c/formText';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * The Submission panel on a form submission (C-42a; canonical model 29ZY): the answers by
 * question, as the version filled in asked them, the records written or found, and Process
 * Again for a submission held for review or failed, after the right person or organization is
 * chosen on it (R-FS2).
 */
export default class FormSubmission extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP);
  labels = LABELS;
  view;
  loading = true;
  busy = false;
  errorMessage;
  resultMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.view = await getSubmission({ submissionId: this.recordId });
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
    this.loading = false;
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
      await this.load();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
    this.busy = false;
  }
}
