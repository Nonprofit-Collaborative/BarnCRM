import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { CloseActionScreenEvent } from 'lightning/actions';
import getActionContext from '@salesforce/apex/VolunteerLetterController.getActionContext';
import previewLetter from '@salesforce/apex/VolunteerLetterController.preview';
import generateLetter from '@salesforce/apex/VolunteerLetterController.generate';

import HEADING from '@salesforce/label/c.Volunteers_LetterAction_Heading';
import TEMPLATE from '@salesforce/label/c.Volunteers_LetterAction_Template';
import FROM_DATE from '@salesforce/label/c.Volunteers_LetterAction_From';
import TO_DATE from '@salesforce/label/c.Volunteers_LetterAction_To';
import PREVIEW from '@salesforce/label/c.Volunteers_LetterAction_Preview';
import GENERATE from '@salesforce/label/c.Volunteers_LetterAction_Generate';
import CANCEL from '@salesforce/label/c.Volunteers_LetterAction_Cancel';
import SAVED from '@salesforce/label/c.Volunteers_LetterAction_Saved';
import NOT_A_PERSON from '@salesforce/label/c.Volunteers_Letter_NotAPerson';
import NEED_PERMISSION from '@salesforce/label/c.Volunteers_Letter_NeedManagePermission';
import NO_TEMPLATE from '@salesforce/label/c.Volunteers_Letter_TemplateNotFound';

/** A date as the lightning-input date value: yyyy-mm-dd, in the user's own day. */
function isoDate(value) {
  const month = String(value.getMonth() + 1).padStart(2, '0');
  const day = String(value.getDate()).padStart(2, '0');
  return `${value.getFullYear()}-${month}-${day}`;
}

/**
 * The Volunteer letter action on a contact or person account (V-08): choose a template and a
 * period, preview the letter, then save it as a PDF in the person's Files.
 */
export default class VolunteerLetter extends LightningElement {
  @api recordId;

  labels = {
    heading: HEADING,
    template: TEMPLATE,
    fromDate: FROM_DATE,
    toDate: TO_DATE,
    preview: PREVIEW,
    generate: GENERATE,
    cancel: CANCEL
  };

  context;
  templateId;
  fromDate = isoDate(new Date(new Date().getFullYear(), 0, 1));
  toDate = isoDate(new Date());
  previewBody;
  notice;
  working = false;

  @wire(getActionContext, { recordId: '$recordId' })
  loadContext({ data, error }) {
    if (data) {
      this.context = data;
      if (data.templates && data.templates.length > 0 && !this.templateId) {
        this.templateId = data.templates[0].value;
      }
    } else if (error) {
      this.notice = this.messageOf(error);
    }
  }

  /** Why nothing can be made here, or nothing when the form can be used. */
  get blocker() {
    if (!this.context) {
      return this.notice;
    }
    if (!this.context.isPerson) {
      return NOT_A_PERSON;
    }
    if (!this.context.canManage) {
      return NEED_PERMISSION;
    }
    if (!this.context.templates || this.context.templates.length === 0) {
      return NO_TEMPLATE;
    }
    return undefined;
  }

  get showForm() {
    return Boolean(this.context) && !this.blocker;
  }

  get templateOptions() {
    return this.context ? this.context.templates : [];
  }

  get buttonsDisabled() {
    return this.working || !this.showForm;
  }

  handleTemplateChange(event) {
    this.templateId = event.detail.value;
    this.previewBody = undefined;
  }

  handleFromChange(event) {
    this.fromDate = event.detail.value;
    this.previewBody = undefined;
  }

  handleToChange(event) {
    this.toDate = event.detail.value;
    this.previewBody = undefined;
  }

  handleCancel() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  async handlePreview() {
    const result = await this.call(previewLetter);
    if (result) {
      this.notice = result.skipReason;
      this.previewBody = result.skipReason ? undefined : result.body;
    }
  }

  async handleGenerate() {
    const result = await this.call(generateLetter);
    if (!result) {
      return;
    }
    if (result.skipReason) {
      this.notice = result.skipReason;
      return;
    }
    Toast.show({ label: SAVED, variant: 'success' }, this);
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  async call(method) {
    this.working = true;
    this.notice = undefined;
    try {
      return await method({
        recordId: this.recordId,
        templateId: this.templateId,
        fromDate: this.fromDate,
        toDate: this.toDate
      });
    } catch (error) {
      this.notice = this.messageOf(error);
      return undefined;
    } finally {
      this.working = false;
    }
  }

  messageOf(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return error && error.message ? error.message : String(error);
  }
}
