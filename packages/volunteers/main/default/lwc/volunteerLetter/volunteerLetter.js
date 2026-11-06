import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { CloseActionScreenEvent } from 'lightning/actions';
import getActionContext from '@salesforce/apex/VolunteerLetterController.getActionContext';
import previewLetter from '@salesforce/apex/VolunteerLetterController.preview';
import generateLetter from '@salesforce/apex/VolunteerLetterController.generate';
import { CUSTOM, THIS_YEAR, periodDates, periodOptions } from 'c/volunteerPeriods';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

import HEADING from '@salesforce/label/c.Volunteers_LetterAction_Heading';
import TEMPLATE from '@salesforce/label/c.Core_Import_StepTemplate';
import FROM_DATE from '@salesforce/label/c.Core_SetupChanges_From';
import TO_DATE from '@salesforce/label/c.Core_SetupChanges_To';
import PREVIEW from '@salesforce/label/c.Core_BulkUpdate_Preview';
import GENERATE from '@salesforce/label/c.Core_Shared_Generate';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import SAVED from '@salesforce/label/c.Volunteers_LetterAction_Saved';
import NOT_A_PERSON from '@salesforce/label/c.Volunteers_Letter_NotAPerson';
import NEED_PERMISSION from '@salesforce/label/c.Volunteers_Letter_NeedManagePermission';
import NO_TEMPLATE from '@salesforce/label/c.Volunteers_Letter_NoActiveTemplate';
import BAD_PERIOD from '@salesforce/label/c.Volunteers_Letter_BadPeriod';
import NO_LEGAL_NAME from '@salesforce/label/c.Volunteers_LetterAction_NoLegalName';
import PERIOD from '@salesforce/label/c.Core_Shared_Period';
import THIS_YEAR_LABEL from '@salesforce/label/c.Volunteers_Shared_ThisYear';
import LAST_YEAR_LABEL from '@salesforce/label/c.Volunteers_Shared_LastYear';
import CUSTOM_LABEL from '@salesforce/label/c.Core_DataDictionary_ColCustom';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

/**
 * The Volunteer letter action on a contact or person account (V-08): choose a template and a
 * period (This Year, Last Year or Custom dates, modules-4), preview the letter, then save it as
 * a PDF in the person's Files.
 */
export default class VolunteerLetter extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded('Volunteers');

  labels = {
    heading: HEADING,
    template: TEMPLATE,
    period: PERIOD,
    fromDate: FROM_DATE,
    toDate: TO_DATE,
    preview: PREVIEW,
    generate: GENERATE,
    cancel: CANCEL,
    loading: LOADING,
    noLegalName: NO_LEGAL_NAME
  };

  periodOptions = periodOptions({
    thisYear: THIS_YEAR_LABEL,
    lastYear: LAST_YEAR_LABEL,
    custom: CUSTOM_LABEL
  });

  context;
  templateId;
  period = THIS_YEAR;
  fromDate = periodDates(THIS_YEAR).fromDate;
  toDate = periodDates(THIS_YEAR).toDate;
  previewBody;
  notice;
  working = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Volunteers').then(() => {
        this.helpReady = true;
      });
    }
  }

  get isCustom() {
    return this.period === CUSTOM;
  }

  /** A preset fills the dates; Custom keeps the last dates and shows them to change. */
  handlePeriodChange(event) {
    this.period = event.detail.value;
    const dates = periodDates(this.period);
    if (dates) {
      this.fromDate = dates.fromDate;
      this.toDate = dates.toDate;
    }
    this.previewBody = undefined;
    this.notice = undefined;
  }

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

  /** The first answer has not arrived and nothing has failed yet. */
  get isLoading() {
    return !this.context && !this.notice;
  }

  /** Letters print the legal name; a blank one prints nothing, so say so before the letter. */
  get showLegalNameWarning() {
    return this.showForm && this.context.organizationNameBlank === true;
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
    this.notice = undefined;
  }

  handleToChange(event) {
    this.toDate = event.detail.value;
    this.previewBody = undefined;
    this.notice = undefined;
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

  /** True when the period can be sent; otherwise shows why, with no server call. */
  periodIsValid() {
    if (!this.fromDate || !this.toDate || this.fromDate > this.toDate) {
      this.notice = BAD_PERIOD;
      this.previewBody = undefined;
      return false;
    }
    return true;
  }

  async call(method) {
    this.notice = undefined;
    if (!this.periodIsValid()) {
      return undefined;
    }
    this.working = true;
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

  /** A readable sentence for any error shape, never "[object Object]". */
  messageOf(error) {
    const body = error && error.body;
    if (body && typeof body.message === 'string' && body.message) {
      return body.message;
    }
    if (error && typeof error.message === 'string' && error.message) {
      return error.message;
    }
    return helpText('Volunteers', 'Volunteers_Letter_ActionFailed');
  }
}
