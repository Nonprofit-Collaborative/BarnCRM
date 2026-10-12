import { LightningElement, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getTemplates from '@salesforce/apex/ReceiptController.getTemplates';
import getCanManageTemplates from '@salesforce/apex/ReceiptController.getCanManageTemplates';
import restoreDefaultTemplates from '@salesforce/apex/ReceiptController.restoreDefaultTemplates';
import saveTemplate from '@salesforce/apex/ReceiptController.saveTemplate';
import activateTemplate from '@salesforce/apex/ReceiptController.activateTemplate';
import getRuns from '@salesforce/apex/ReceiptController.getRuns';
import getDefaultStatementYear from '@salesforce/apex/ReceiptController.getDefaultStatementYear';
import startStatementRun from '@salesforce/apex/ReceiptController.startStatementRun';

const TOKENS = [
  '{{OrganizationName}}',
  '{{OrganizationAddress}}',
  '{{OrganizationTaxId}}',
  '{{PlaceOfIssue}}',
  '{{SignerName}}',
  '{{SignerTitle}}',
  '{{DonorName}}',
  '{{ReceiptNumber}}',
  '{{IssueDate}}',
  '{{StatementYear}}',
  '{{Amount}}',
  '{{GiftDate}}',
  '{{GiftType}}',
  '{{GiftLines}}'
];

/**
 * The Receipts panel in the Nonprofit Settings console: the letters, and the year end run.
 *
 * The panel deliberately does not offer a way to edit the tax sentences. They are not on this
 * screen because they are not editable: whatever the letter says, BarnCRM adds what IRS
 * Publication 1771 requires (ADR-0016, R-RC7). The note under the editor says so, so that an
 * administrator looking for them stops looking rather than typing them in twice.
 */
export default class ReceiptSettings extends LightningElement {
  templates = [];
  wiredTemplates;
  runs = [];
  wiredRuns;
  selectedTemplateId;
  draftBody = '';
  statementYear;
  working = false;
  loadError;
  canManage = false;

  tokens = TOKENS;

  @wire(getTemplates)
  handleTemplates(result) {
    this.wiredTemplates = result;
    if (result.data) {
      this.templates = result.data;
      this.loadError = undefined;
      if (!this.selectedTemplateId && this.templates.length > 0) {
        this.selectTemplate(this.templates[0]);
      }
    } else if (result.error) {
      this.loadError = this.messageOf(result.error);
    }
  }

  @wire(getCanManageTemplates)
  handleCanManage({ data }) {
    this.canManage = data === true;
  }

  @wire(getRuns)
  handleRuns(result) {
    this.wiredRuns = result;
    if (result.data) {
      this.runs = result.data;
    }
  }

  @wire(getDefaultStatementYear)
  handleDefaultYear({ data }) {
    if (data && this.statementYear === undefined) {
      this.statementYear = data;
    }
  }

  get templateOptions() {
    return this.templates.map((template) => ({
      label: `${template.name} (${template.type})${template.active ? '' : ', off'}`,
      value: template.id
    }));
  }

  get selectedTemplate() {
    return this.templates.find((template) => template.id === this.selectedTemplateId);
  }

  get selectedIsActive() {
    const template = this.selectedTemplate;
    return !!template && template.active;
  }

  get busy() {
    return this.working;
  }

  /** Saving and switching a letter on both need Manage Nonprofit Settings, so both read this. */
  get cannotEdit() {
    return this.working || !this.canManage;
  }

  get hasTemplates() {
    return this.templates.length > 0;
  }

  get hasRuns() {
    return this.runs.length > 0;
  }

  selectTemplate(template) {
    this.selectedTemplateId = template.id;
    this.draftBody = template.body;
  }

  handleTemplateChange(event) {
    const chosen = this.templates.find((template) => template.id === event.detail.value);
    if (chosen) {
      this.selectTemplate(chosen);
    }
  }

  handleBodyChange(event) {
    this.draftBody = event.detail.value;
  }

  handleYearChange(event) {
    this.statementYear = parseInt(event.detail.value, 10);
  }

  /**
   * The recovery path for an install whose bootstrap step failed. The letters are created at
   * install (ADR-0029); this is the button that says so out loud when they are not there.
   */
  async handleRestore() {
    this.working = true;
    try {
      await restoreDefaultTemplates();
      this.toast('Restored', 'The letters BarnCRM ships are back.', 'success');
      await refreshApex(this.wiredTemplates);
    } catch (error) {
      this.toast('Not restored', this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  async handleSave() {
    this.working = true;
    try {
      await saveTemplate({ templateId: this.selectedTemplateId, body: this.draftBody });
      this.toast('Saved', 'Your receipt letter has been saved.', 'success');
      await refreshApex(this.wiredTemplates);
    } catch (error) {
      this.toast('Not saved', this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  async handleActivate() {
    this.working = true;
    try {
      await activateTemplate({ templateId: this.selectedTemplateId });
      this.toast('Switched on', 'This letter is now the one BarnCRM uses.', 'success');
      await refreshApex(this.wiredTemplates);
    } catch (error) {
      this.toast('Not switched on', this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  async handleGenerate() {
    this.working = true;
    try {
      await startStatementRun({ statementYear: this.statementYear });
      this.toast(
        'Started',
        'Year end statements are being generated. Watch the run below for progress.',
        'success'
      );
      await refreshApex(this.wiredRuns);
    } catch (error) {
      this.toast('Not started', this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  async handleRefreshRuns() {
    await refreshApex(this.wiredRuns);
  }

  messageOf(error) {
    if (!error) {
      return 'Something went wrong.';
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message || 'Something went wrong.';
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
