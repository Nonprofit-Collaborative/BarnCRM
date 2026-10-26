import { LightningElement } from 'lwc';
import getView from '@salesforce/apex/MatchSourceController.getView';
import describeObject from '@salesforce/apex/MatchSourceController.describeObject';
import tryValue from '@salesforce/apex/MatchSourceController.tryValue';
import saveRow from '@salesforce/apex/CustomMetadataManagerController.saveRow';
import setArchived from '@salesforce/apex/CustomMetadataManagerController.setArchived';
import getOutcome from '@salesforce/apex/CustomMetadataManagerController.getOutcome';

import INTRO from '@salesforce/label/c.Core_MatchLogic_Intro';
import RULES_NOTE from '@salesforce/label/c.Core_MatchLogic_RulesNote';
import READ_ONLY from '@salesforce/label/c.Core_MatchLogic_ReadOnly';
import SHIPPED_NOTE from '@salesforce/label/c.Core_MatchLogic_ShippedNote';
import ACTIVE from '@salesforce/label/c.Core_MatchLogic_Active';
import INACTIVE from '@salesforce/label/c.Core_MatchLogic_Inactive';
import SHIPPED from '@salesforce/label/c.Core_MatchLogic_Shipped';
import NOT_USABLE from '@salesforce/label/c.Core_MatchLogic_NotUsable';
import OBJECT from '@salesforce/label/c.Core_MatchLogic_Object';
import VALUE_FIELD from '@salesforce/label/c.Core_MatchLogic_ValueField';
import POSTAL_FIELD from '@salesforce/label/c.Core_MatchLogic_PostalField';
import LINKS_TO from '@salesforce/label/c.Core_MatchLogic_LinksTo';
import PARENT_FIELD from '@salesforce/label/c.Core_MatchLogic_ParentField';
import COMPARE from '@salesforce/label/c.Core_MatchLogic_Compare';
import ACTIVATE from '@salesforce/label/c.Core_MatchLogic_Activate';
import DEACTIVATE from '@salesforce/label/c.Core_MatchLogic_Deactivate';
import FIND_FIELDS from '@salesforce/label/c.Core_MatchLogic_FindFields';
import TRY from '@salesforce/label/c.Core_MatchLogic_Try';
import TRY_VALUE from '@salesforce/label/c.Core_MatchLogic_TryValue';
import TRY_POSTAL from '@salesforce/label/c.Core_MatchLogic_TryPostal';
import TRY_RUN from '@salesforce/label/c.Core_MatchLogic_TryRun';
import TRY_COMPARED_AS from '@salesforce/label/c.Core_MatchLogic_TryComparedAs';
import TRY_FOUND from '@salesforce/label/c.Core_MatchLogic_TryFound';
import TRY_NONE from '@salesforce/label/c.Core_MatchLogic_TryNone';
import TRY_TOO_LITTLE from '@salesforce/label/c.Core_MatchLogic_TryTooLittle';
import ADD from '@salesforce/label/c.Core_CmdtManager_AddButton';
import EDIT from '@salesforce/label/c.Core_CmdtManager_EditAction';
import SAVE from '@salesforce/label/c.Core_CmdtManager_SaveButton';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import NAME from '@salesforce/label/c.Core_CmdtManager_NameField';
import NEW_TITLE from '@salesforce/label/c.Core_CmdtManager_NewTitle';
import EDIT_TITLE from '@salesforce/label/c.Core_CmdtManager_EditTitle';
import SAVING from '@salesforce/label/c.Core_CmdtManager_Saving';
import SAVED from '@salesforce/label/c.Core_CmdtManager_Saved';
import STILL_SAVING from '@salesforce/label/c.Core_CmdtManager_StillSaving';
import CHECK_AGAIN from '@salesforce/label/c.Core_CmdtManager_CheckAgain';
import LOAD_ERROR from '@salesforce/label/c.Core_CmdtManager_LoadError';

const TYPE_NAME = 'Match_Source__mdt';
const ADDRESS = 'Address';
const FIELDS = [
  'Object_Name__c',
  'Value_Field__c',
  'Postal_Code_Field__c',
  'Parent_Field__c',
  'Normalization__c'
];
const POLL_INTERVAL_MS = 3000;
const POLL_ATTEMPTS = 20;

/**
 * Matching Logic on the Duplicate Matching tab (ADR-0139, admin guide duplicates.md): the
 * match sources in plain words, add, edit, activate and deactivate, and "Try a value". Saving
 * goes through the custom metadata manager, which checks the source against the org, deploys
 * it and needs Manage BarnCRM Metadata, so the page waits on the deployment as that page does.
 */
export default class MatchSourceManager extends LightningElement {
  labels = {
    intro: INTRO,
    rulesNote: RULES_NOTE,
    readOnly: READ_ONLY,
    shippedNote: SHIPPED_NOTE,
    shipped: SHIPPED,
    notUsable: NOT_USABLE,
    object: OBJECT,
    valueField: VALUE_FIELD,
    postalField: POSTAL_FIELD,
    linksTo: LINKS_TO,
    parentField: PARENT_FIELD,
    compare: COMPARE,
    findFields: FIND_FIELDS,
    tryValue: TRY_VALUE,
    tryPostal: TRY_POSTAL,
    tryRun: TRY_RUN,
    tryFound: TRY_FOUND,
    add: ADD,
    edit: EDIT,
    save: SAVE,
    cancel: CANCEL,
    name: NAME,
    checkAgain: CHECK_AGAIN
  };

  view;
  form;
  /** The fields of the form's object, from describeObject. */
  objectFields;
  trying;
  tryInput = { value: '', postal: '' };
  tryResult;
  statusMessage;
  errorMessage;
  busy = false;
  pending;
  pollTimer;

  connectedCallback() {
    this.load();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  async load() {
    try {
      this.view = await getView();
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    }
  }

  // ------------------------------------------------------------------ what is shown

  get canEdit() {
    return Boolean(this.view && this.view.canEdit);
  }

  get showReadOnly() {
    return Boolean(this.view) && !this.view.canEdit;
  }

  get compareText() {
    const texts = {};
    ((this.view && this.view.normalizations) || []).forEach((choice) => {
      texts[choice.value] = choice.label;
    });
    return texts;
  }

  get sources() {
    if (!this.view) {
      return [];
    }
    const texts = this.compareText;
    return this.view.sources.map((source) => {
      const values = source.values || {};
      const isTrying = Boolean(this.trying) && this.trying.developerName === source.developerName;
      return {
        ...source,
        statusText: source.active ? ACTIVE : INACTIVE,
        notUsable: !source.usable,
        objectText: source.objectLabel || values.Object_Name__c,
        valueText: source.valueFieldLabel || values.Value_Field__c,
        postalText: source.postalFieldLabel || values.Postal_Code_Field__c,
        parentText: source.parentFieldLabel || values.Parent_Field__c,
        compareText: texts[values.Normalization__c] || values.Normalization__c,
        isAddress: values.Normalization__c === ADDRESS,
        canChange: this.canEdit && !source.shipped,
        toggleLabel: source.active ? DEACTIVATE : ACTIVATE,
        tryLabel: TRY,
        isTrying,
        tryOpenLabel: `${TRY}: ${source.label}`
      };
    });
  }

  get formTitle() {
    if (!this.form) {
      return '';
    }
    return this.form.developerName ? EDIT_TITLE.replace('{0}', this.form.originalLabel) : NEW_TITLE;
  }

  /** A field's choices: the object's fields once found, else the value already there. */
  choicesFor(list, current) {
    const found = (this.objectFields && this.objectFields[list]) || [];
    if (current && !found.some((choice) => choice.value === current)) {
      return [{ label: current, value: current }, ...found];
    }
    return found;
  }

  get valueFieldOptions() {
    return this.choicesFor('valueFields', this.form.values.Value_Field__c);
  }

  get postalFieldOptions() {
    return this.choicesFor('valueFields', this.form.values.Postal_Code_Field__c);
  }

  get parentFieldOptions() {
    return this.choicesFor('parentFields', this.form.values.Parent_Field__c);
  }

  get normalizationOptions() {
    return (this.view && this.view.normalizations) || [];
  }

  get formIsAddress() {
    return Boolean(this.form) && this.form.values.Normalization__c === ADDRESS;
  }

  get tryIsAddress() {
    return Boolean(this.trying) && this.trying.values.Normalization__c === ADDRESS;
  }

  get tryComparedAs() {
    if (!this.tryResult) {
      return undefined;
    }
    return this.tryResult.comparedAs
      ? TRY_COMPARED_AS.replace('{0}', this.tryResult.comparedAs)
      : TRY_TOO_LITTLE;
  }

  get tryRecords() {
    return (this.tryResult && this.tryResult.records) || [];
  }

  get tryFoundAny() {
    return this.tryRecords.length > 0;
  }

  get tryFoundNone() {
    return Boolean(this.tryResult && this.tryResult.comparedAs) && !this.tryFoundAny;
  }

  get tryNoneText() {
    return TRY_NONE;
  }

  // ------------------------------------------------------------------ the form

  handleAdd() {
    const values = {};
    FIELDS.forEach((name) => {
      values[name] = '';
    });
    this.form = { developerName: null, originalLabel: '', label: '', values };
    this.objectFields = undefined;
    this.clearMessages();
  }

  handleEdit(event) {
    const source = this.findSource(event.target.dataset.name);
    this.form = {
      developerName: source.developerName,
      originalLabel: source.label,
      label: source.label,
      values: { ...source.values }
    };
    this.objectFields = undefined;
    this.clearMessages();
    this.findFields();
  }

  handleNameChange(event) {
    this.form = { ...this.form, label: event.detail.value };
  }

  handleFieldChange(event) {
    const values = { ...this.form.values, [event.target.dataset.field]: event.detail.value };
    this.form = { ...this.form, values };
  }

  handleFindFields() {
    this.findFields();
  }

  async findFields() {
    const objectName = this.form && this.form.values.Object_Name__c;
    if (!objectName) {
      return;
    }
    try {
      this.objectFields = await describeObject({ objectName });
      this.errorMessage = undefined;
    } catch (error) {
      this.objectFields = undefined;
      this.errorMessage = this.messageFrom(error);
    }
  }

  handleCancel() {
    this.form = undefined;
    this.objectFields = undefined;
  }

  async handleSave() {
    const form = this.form;
    const started = await this.start(
      form.label,
      saveRow({
        typeName: TYPE_NAME,
        input: { developerName: form.developerName, label: form.label, values: form.values }
      })
    );
    if (started) {
      this.form = undefined;
      this.objectFields = undefined;
    }
  }

  handleToggle(event) {
    const source = this.findSource(event.target.dataset.name);
    this.start(
      source.label,
      setArchived({
        typeName: TYPE_NAME,
        developerName: source.developerName,
        archived: source.active
      })
    );
  }

  // ------------------------------------------------------------------ try a value

  handleTryOpen(event) {
    const source = this.findSource(event.target.dataset.name);
    this.trying = {
      developerName: source.developerName,
      label: source.label,
      values: source.values
    };
    this.tryInput = { value: '', postal: '' };
    this.tryResult = undefined;
  }

  handleTryInput(event) {
    this.tryInput = { ...this.tryInput, [event.target.dataset.input]: event.detail.value };
  }

  async handleTryRun() {
    try {
      this.tryResult = await tryValue({
        label: this.trying.label,
        values: this.trying.values,
        value: this.tryInput.value,
        postal: this.tryInput.postal
      });
      this.errorMessage = undefined;
    } catch (error) {
      this.tryResult = undefined;
      this.errorMessage = this.messageFrom(error);
    }
  }

  handleTryClose() {
    this.trying = undefined;
    this.tryResult = undefined;
  }

  // ------------------------------------------------------------------ saving

  handleCheckAgain() {
    this.load();
    if (this.pending) {
      this.poll(this.pending.jobId, this.pending.label, 1);
    }
  }

  async start(label, request) {
    this.busy = true;
    this.clearMessages();
    try {
      const jobId = await request;
      this.pending = { jobId, label };
      this.statusMessage = SAVING;
      this.poll(jobId, label, POLL_ATTEMPTS);
      return true;
    } catch (error) {
      this.busy = false;
      this.errorMessage = this.messageFrom(error);
      return false;
    }
  }

  poll(jobId, label, attemptsLeft) {
    this.stopPolling();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.pollTimer = setTimeout(async () => {
      this.pollTimer = undefined;
      let outcome;
      try {
        outcome = await getOutcome({ deploymentId: jobId });
      } catch (error) {
        this.finish(undefined, this.messageFrom(error));
        return;
      }
      if (outcome.status === 'Succeeded') {
        this.finish(SAVED.replace('{0}', label), undefined);
        this.load();
      } else if (outcome.status === 'Failed') {
        this.finish(undefined, outcome.message);
      } else if (attemptsLeft > 1) {
        this.poll(jobId, label, attemptsLeft - 1);
      } else {
        this.busy = false;
        this.statusMessage = STILL_SAVING;
      }
    }, POLL_INTERVAL_MS);
  }

  get showCheckAgain() {
    return Boolean(this.pending) && !this.busy;
  }

  finish(status, error) {
    this.pending = undefined;
    this.busy = false;
    this.statusMessage = status;
    this.errorMessage = error;
  }

  stopPolling() {
    if (this.pollTimer) {
      clearTimeout(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  clearMessages() {
    this.errorMessage = undefined;
    this.statusMessage = undefined;
  }

  findSource(developerName) {
    return this.view.sources.find((source) => source.developerName === developerName);
  }

  messageFrom(error) {
    return error && error.body && error.body.message ? error.body.message : LOAD_ERROR;
  }
}
