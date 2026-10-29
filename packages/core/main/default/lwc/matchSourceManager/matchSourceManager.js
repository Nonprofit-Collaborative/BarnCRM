import { LightningElement } from 'lwc';
import getView from '@salesforce/apex/MatchSourceController.getView';
import tryValue from '@salesforce/apex/MatchSourceController.tryValue';
import setArchived from '@salesforce/apex/CustomMetadataManagerController.setArchived';
import getOutcome from '@salesforce/apex/CustomMetadataManagerController.getOutcome';
import MatchSourceModal from 'c/matchSourceModal';

import INTRO from '@salesforce/label/c.Core_MatchLogic_Intro';
import HELP from '@salesforce/label/c.Core_MatchLogic_Help';
import HELP_ALT from '@salesforce/label/c.Core_MatchLogic_HelpAlt';
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
import SUMMARY from '@salesforce/label/c.Core_MatchLogic_Summary';
import SHOW_DETAILS from '@salesforce/label/c.Core_MatchLogic_ShowDetails';
import HIDE_DETAILS from '@salesforce/label/c.Core_MatchLogic_HideDetails';
import ACTIVE_SWITCH from '@salesforce/label/c.Core_MatchLogic_ActiveSwitch';
import NEW_TITLE from '@salesforce/label/c.Core_MatchLogic_NewTitle';
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
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import EDIT_TITLE from '@salesforce/label/c.Core_CmdtManager_EditTitle';
import SAVING from '@salesforce/label/c.Core_CmdtManager_Saving';
import SAVED from '@salesforce/label/c.Core_CmdtManager_Saved';
import STILL_SAVING from '@salesforce/label/c.Core_CmdtManager_StillSaving';
import CHECK_AGAIN from '@salesforce/label/c.Core_CmdtManager_CheckAgain';
import LOAD_ERROR from '@salesforce/label/c.Core_CmdtManager_LoadError';

const TYPE_NAME = 'Match_Source__mdt';
const ADDRESS = 'Address';
const POLL_INTERVAL_MS = 3000;
const POLL_ATTEMPTS = 20;

/**
 * Matching Logic on the Duplicate Matching tab (ADR-0139, admin guide duplicates.md): each
 * match source as a card with a one-line summary, an Active switch, its details on request,
 * and "Try a Value"; adding and editing happen in a modal (c-match-source-modal). Saving goes
 * through the custom metadata manager, which checks the source against the org, deploys it and
 * needs Manage BarnCRM Metadata, so the page waits on the deployment as that page does.
 */
export default class MatchSourceManager extends LightningElement {
  labels = {
    intro: INTRO,
    helpAlt: HELP_ALT,
    readOnly: READ_ONLY,
    shipped: SHIPPED,
    notUsable: NOT_USABLE,
    object: OBJECT,
    valueField: VALUE_FIELD,
    postalField: POSTAL_FIELD,
    linksTo: LINKS_TO,
    parentField: PARENT_FIELD,
    compare: COMPARE,
    active: ACTIVE,
    inactive: INACTIVE,
    tryValue: TRY_VALUE,
    tryPostal: TRY_POSTAL,
    tryRun: TRY_RUN,
    tryFound: TRY_FOUND,
    add: ADD,
    edit: EDIT,
    cancel: CANCEL,
    checkAgain: CHECK_AGAIN
  };

  helpText = `${HELP} ${RULES_NOTE} ${SHIPPED_NOTE}`;

  view;
  /** The developer names of the cards whose details are shown. */
  expanded = {};
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

  get normalizations() {
    return (this.view && this.view.normalizations) || [];
  }

  get compareText() {
    const texts = {};
    this.normalizations.forEach((choice) => {
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
      const showDetails = Boolean(this.expanded[source.developerName]);
      const objectText = source.objectLabel || values.Object_Name__c;
      const valueText = source.valueFieldLabel || values.Value_Field__c;
      return {
        ...source,
        statusText: source.active ? ACTIVE : INACTIVE,
        statusClass: source.active ? 'slds-theme_success' : '',
        switchLabel: ACTIVE_SWITCH.replace('{0}', source.label),
        summary: SUMMARY.replace('{0}', valueText)
          .replace('{1}', objectText)
          .replace('{2}', values.Normalization__c || ''),
        notUsable: !source.usable,
        objectText,
        valueText,
        postalText: source.postalFieldLabel || values.Postal_Code_Field__c,
        parentText: source.parentFieldLabel || values.Parent_Field__c,
        compareText: texts[values.Normalization__c] || values.Normalization__c,
        isAddress: values.Normalization__c === ADDRESS,
        canChange: this.canEdit && !source.shipped,
        showDetails,
        detailsLabel: showDetails ? HIDE_DETAILS : SHOW_DETAILS,
        detailsExpanded: String(showDetails),
        tryLabel: TRY,
        isTrying,
        tryOpenLabel: `${TRY}: ${source.label}`
      };
    });
  }

  handleDetailsToggle(event) {
    const name = event.target.dataset.name;
    this.expanded = { ...this.expanded, [name]: !this.expanded[name] };
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

  // ------------------------------------------------------------------ add and edit

  handleAdd() {
    this.openForm(NEW_TITLE, undefined);
  }

  handleEdit(event) {
    const source = this.findSource(event.target.dataset.name);
    this.openForm(EDIT_TITLE.replace('{0}', source.label), {
      developerName: source.developerName,
      label: source.label,
      values: { ...source.values }
    });
  }

  /** The modal saves the source itself; once its deployment has started this page waits on it. */
  async openForm(label, source) {
    this.clearMessages();
    const result = await MatchSourceModal.open({
      size: 'small',
      label,
      source,
      normalizations: this.normalizations
    });
    if (result && result.jobId) {
      this.track(result.jobId, result.label);
    }
  }

  /**
   * The switch is put back at once: it moves when the deployment has finished and the list is
   * read again, so it never shows a state Salesforce has not applied.
   */
  handleToggle(event) {
    const source = this.findSource(event.target.dataset.name);
    event.target.checked = source.active;
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
      this.track(await request, label);
    } catch (error) {
      this.busy = false;
      this.errorMessage = this.messageFrom(error);
    }
  }

  /** Waits on a started deployment, saying "Saving" until it has finished. */
  track(jobId, label) {
    this.busy = true;
    this.pending = { jobId, label };
    this.statusMessage = SAVING;
    this.poll(jobId, label, POLL_ATTEMPTS);
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
