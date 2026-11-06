import LightningModal from 'lightning/modal';
import { wire } from 'lwc';
import { getRecords } from 'lightning/uiRecordApi';
import getListContext from '@salesforce/apex/VolunteerLetterController.getListContext';
import startLetters from '@salesforce/apex/VolunteerLetterController.startLetters';
import { CUSTOM, THIS_YEAR, periodDates, periodOptions } from 'c/volunteerPeriods';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

import TEMPLATE from '@salesforce/label/c.Core_Import_StepTemplate';
import PERIOD from '@salesforce/label/c.Core_Shared_Period';
import FROM_DATE from '@salesforce/label/c.Core_SetupChanges_From';
import TO_DATE from '@salesforce/label/c.Core_SetupChanges_To';
import PERSON from '@salesforce/label/c.Core_Section_Person';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import THIS_YEAR_LABEL from '@salesforce/label/c.Volunteers_Shared_ThisYear';
import LAST_YEAR_LABEL from '@salesforce/label/c.Volunteers_Shared_LastYear';
import CUSTOM_LABEL from '@salesforce/label/c.Core_DataDictionary_ColCustom';
import NEED_PERMISSION from '@salesforce/label/c.Volunteers_Letter_NeedManagePermission';
import NO_TEMPLATE from '@salesforce/label/c.Volunteers_Letter_NoActiveTemplate';
import BAD_PERIOD from '@salesforce/label/c.Volunteers_Letter_BadPeriod';
import NO_LEGAL_NAME from '@salesforce/label/c.Volunteers_LetterAction_NoLegalName';
import TITLE from '@salesforce/label/c.Volunteers_Letters_Title';
import WHO from '@salesforce/label/c.Volunteers_Letters_Who';
import EVERYONE from '@salesforce/label/c.Volunteers_Letters_Everyone';
import CHOSEN from '@salesforce/label/c.Volunteers_Letters_Chosen';
import MAKE from '@salesforce/label/c.Volunteers_Letters_Make';

const EVERYONE_VALUE = 'everyone';
const CHOSEN_VALUE = 'chosen';

/**
 * Volunteer Letters (modules-20), opened from Approve Hours: letters for many people without
 * Flow Builder. The coordinator chooses the template, the period (This Year, Last Year or
 * Custom, as the single letter offers) and everyone with approved hours in the period or the
 * people they pick, then Make Letters starts the same background job as the Generate volunteer
 * letters flow action, which notifies them when it ends. Resolves with the sentence to show, or
 * undefined when closed without starting.
 */
export default class VolunteerLettersModal extends LightningModal {
  helpReady = isHelpLoaded('Volunteers');

  labels = {
    title: TITLE,
    template: TEMPLATE,
    period: PERIOD,
    fromDate: FROM_DATE,
    toDate: TO_DATE,
    person: PERSON,
    who: WHO,
    make: MAKE,
    cancel: CANCEL,
    loading: LOADING,
    noLegalName: NO_LEGAL_NAME
  };

  periodOptions = periodOptions({
    thisYear: THIS_YEAR_LABEL,
    lastYear: LAST_YEAR_LABEL,
    custom: CUSTOM_LABEL
  });

  whoOptions = [
    { label: EVERYONE, value: EVERYONE_VALUE },
    { label: CHOSEN, value: CHOSEN_VALUE }
  ];

  context;
  loadFailed = false;
  templateId;
  period = THIS_YEAR;
  fromDate = periodDates(THIS_YEAR).fromDate;
  toDate = periodDates(THIS_YEAR).toDate;
  who = EVERYONE_VALUE;
  people = [];
  notice;
  working = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Volunteers').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    try {
      this.context = await getListContext();
      const templates = this.context.templates || [];
      if (templates.length > 0) {
        this.templateId = templates[0].value;
      }
    } catch (error) {
      this.loadFailed = true;
      this.notice = messageOf(error);
    }
  }

  get intro() {
    return this.helpReady ? helpText('Volunteers', 'Volunteers_Letters_Intro') : '';
  }

  get isLoading() {
    return !this.context && !this.loadFailed;
  }

  /** Why nothing can be made here, or nothing when the form can be used. */
  get blocker() {
    if (!this.context) {
      return this.loadFailed ? this.notice : undefined;
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

  get showLegalNameWarning() {
    return this.showForm && this.context.organizationNameBlank === true;
  }

  get showNotice() {
    return Boolean(this.notice) && !this.blocker;
  }

  get templateOptions() {
    return this.context ? this.context.templates : [];
  }

  get isCustom() {
    return this.period === CUSTOM;
  }

  get isChosen() {
    return this.who === CHOSEN_VALUE;
  }

  get personObject() {
    return this.context ? this.context.personObject : 'Contact';
  }

  /** Person accounts only, where the org keeps people as accounts (the field comes from Apex). */
  get personFilter() {
    if (!this.context || !this.context.personFilterField) {
      return undefined;
    }
    return {
      criteria: [{ fieldPath: this.context.personFilterField, operator: 'eq', value: true }]
    };
  }

  get hasPeople() {
    return this.people.length > 0;
  }

  get makeDisabled() {
    return this.working || !this.showForm;
  }

  handleTemplateChange(event) {
    this.templateId = event.detail.value;
  }

  handlePeriodChange(event) {
    this.period = event.detail.value;
    const dates = periodDates(this.period);
    if (dates) {
      this.fromDate = dates.fromDate;
      this.toDate = dates.toDate;
    }
    this.notice = undefined;
  }

  handleFromChange(event) {
    this.fromDate = event.detail.value;
    this.notice = undefined;
  }

  handleToChange(event) {
    this.toDate = event.detail.value;
    this.notice = undefined;
  }

  handleWhoChange(event) {
    this.who = event.detail.value;
    this.notice = undefined;
  }

  /** The picked people's names, read once each person is added. */
  @wire(getRecords, { records: '$namesRequest' })
  wiredNames({ data }) {
    if (!data || !data.results) {
      return;
    }
    const names = {};
    data.results.forEach((result) => {
      const record = result.result;
      if (record && record.id && record.fields && record.fields.Name) {
        names[record.id] = record.fields.Name.value;
      }
    });
    this.names = names;
  }

  names = {};

  get namesRequest() {
    if (!this.hasPeople) {
      return undefined;
    }
    return [{ recordIds: this.people, fields: [`${this.personObject}.Name`] }];
  }

  get personPills() {
    return this.people.map((id) => ({ id, name: this.names[id] || this.labels.loading }));
  }

  /** Adds the picked person to the list once, then clears the picker for the next. */
  handlePersonPick(event) {
    const recordId = event.detail.recordId;
    if (!recordId) {
      return;
    }
    if (!this.people.includes(recordId)) {
      this.people = [...this.people, recordId];
    }
    if (event.target && typeof event.target.clearSelection === 'function') {
      event.target.clearSelection();
    }
    this.notice = undefined;
  }

  handleRemovePerson(event) {
    const id = event.target.dataset.personId;
    this.people = this.people.filter((personId) => personId !== id);
  }

  handleCancel() {
    this.close();
  }

  async handleMake() {
    this.notice = undefined;
    if (!this.fromDate || !this.toDate || this.fromDate > this.toDate) {
      this.notice = BAD_PERIOD;
      return;
    }
    if (this.isChosen && !this.hasPeople) {
      this.notice = helpText('Volunteers', 'Volunteers_Letters_ChooseSomeone');
      return;
    }
    this.working = true;
    try {
      const count = await startLetters({
        templateId: this.templateId,
        fromDate: this.fromDate,
        toDate: this.toDate,
        personIds: this.isChosen ? this.people : []
      });
      if (!count) {
        this.notice = helpText('Volunteers', 'Volunteers_Letters_Nobody');
        return;
      }
      this.close(
        count === 1
          ? helpText('Volunteers', 'Volunteers_Letters_StartedOne')
          : helpText('Volunteers', 'Volunteers_Letters_Started', count)
      );
    } catch (error) {
      this.notice = messageOf(error);
    } finally {
      this.working = false;
    }
  }
}

/** A readable sentence for any error shape, never "[object Object]". */
function messageOf(error) {
  const body = error && error.body;
  if (body && typeof body.message === 'string' && body.message) {
    return body.message;
  }
  return helpText('Volunteers', 'Volunteers_Letter_ActionFailed');
}
