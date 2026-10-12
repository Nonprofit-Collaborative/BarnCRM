import { LightningElement } from 'lwc';
import getTypes from '@salesforce/apex/CustomMetadataManagerController.getTypes';
import saveRow from '@salesforce/apex/CustomMetadataManagerController.saveRow';
import setArchived from '@salesforce/apex/CustomMetadataManagerController.setArchived';
import getOutcome from '@salesforce/apex/CustomMetadataManagerController.getOutcome';

import ADD from '@salesforce/label/c.Core_CmdtManager_AddButton';
import EDIT from '@salesforce/label/c.Core_CmdtManager_EditAction';
import ARCHIVE from '@salesforce/label/c.Core_CmdtManager_ArchiveAction';
import RESTORE from '@salesforce/label/c.Core_CmdtManager_RestoreAction';
import SAVE from '@salesforce/label/c.Core_CmdtManager_SaveButton';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import NAME from '@salesforce/label/c.Core_CmdtManager_NameField';
import STATUS from '@salesforce/label/c.Core_CmdtManager_StatusColumn';
import IN_USE from '@salesforce/label/c.Core_CmdtManager_StatusInUse';
import ARCHIVED from '@salesforce/label/c.Core_CmdtManager_StatusArchived';
import OWN_HEADING from '@salesforce/label/c.Core_CmdtManager_OwnHeading';
import OWN_EMPTY from '@salesforce/label/c.Core_CmdtManager_OwnEmpty';
import SHIPPED_HEADING from '@salesforce/label/c.Core_CmdtManager_ShippedHeading';
import NEW_TITLE from '@salesforce/label/c.Core_CmdtManager_NewTitle';
import EDIT_TITLE from '@salesforce/label/c.Core_CmdtManager_EditTitle';
import SAVING from '@salesforce/label/c.Core_CmdtManager_Saving';
import SAVED from '@salesforce/label/c.Core_CmdtManager_Saved';
import STILL_SAVING from '@salesforce/label/c.Core_CmdtManager_StillSaving';
import CHECK_AGAIN from '@salesforce/label/c.Core_CmdtManager_CheckAgain';
import LOAD_ERROR from '@salesforce/label/c.Core_CmdtManager_LoadError';

const POLL_INTERVAL_MS = 3000;
const POLL_ATTEMPTS = 20;

/**
 * The Custom metadata page in BarnCRM Settings: the organization's own rows of each editable
 * list, which it can add, edit, archive and restore, above the rows BarnCRM ships, which it
 * can only read. Saving is a metadata deployment, so the page waits on its outcome
 * (NEXT-custom-metadata-manager-edits-only-types-read-directly.md).
 */
export default class CustomMetadataManager extends LightningElement {
  types = [];
  form;
  statusMessage;
  errorMessage;
  busy = false;
  pending;
  pollTimer;

  labels = {
    add: ADD,
    save: SAVE,
    cancel: CANCEL,
    name: NAME,
    ownHeading: OWN_HEADING,
    ownEmpty: OWN_EMPTY,
    shippedHeading: SHIPPED_HEADING,
    checkAgain: CHECK_AGAIN
  };

  connectedCallback() {
    this.load();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  async load() {
    try {
      this.types = (await getTypes()) || [];
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    }
  }

  get sections() {
    return this.types.map((type) => {
      const columns = [
        { label: NAME, fieldName: 'label' },
        ...type.fields.map((field) => ({ label: field.label, fieldName: field.apiName })),
        { label: STATUS, fieldName: 'statusText' }
      ];
      const rows = type.rows.map((row) => ({
        ...row.values,
        developerName: row.developerName,
        label: row.label,
        shipped: row.shipped,
        archived: row.archived,
        statusText: row.archived ? ARCHIVED : IN_USE
      }));
      const own = rows.filter((row) => !row.shipped);
      return {
        ...type,
        ownColumns: [
          ...columns,
          { type: 'action', typeAttributes: { rowActions: this.rowActions } }
        ],
        shippedColumns: columns,
        ownRows: own,
        hasOwnRows: own.length > 0,
        shippedRows: rows.filter((row) => row.shipped),
        showForm: Boolean(this.form) && this.form.typeName === type.typeName
      };
    });
  }

  // A function, so each row offers Archive or Restore as fits it.
  rowActions = (row, done) => {
    done([
      { label: EDIT, name: 'edit' },
      row.archived ? { label: RESTORE, name: 'restore' } : { label: ARCHIVE, name: 'archive' }
    ]);
  };

  get formTitle() {
    if (!this.form) {
      return '';
    }
    return this.form.developerName ? EDIT_TITLE.replace('{0}', this.form.originalLabel) : NEW_TITLE;
  }

  get formFields() {
    if (!this.form) {
      return [];
    }
    return this.form.fields.map((field) => ({
      ...field,
      value: this.form.values[field.apiName] || '',
      isChoice: Array.isArray(field.choices),
      isLong: !Array.isArray(field.choices) && field.isLong,
      isText: !Array.isArray(field.choices) && !field.isLong
    }));
  }

  get disabled() {
    return this.busy;
  }

  handleAdd(event) {
    this.openForm(event.target.dataset.type, null);
  }

  handleRowAction(event) {
    const typeName = event.target.dataset.type;
    const row = event.detail.row;
    const action = event.detail.action.name;
    if (action === 'edit') {
      this.openForm(typeName, row);
    } else {
      this.start(
        typeName,
        row.label,
        setArchived({ typeName, developerName: row.developerName, archived: action === 'archive' })
      );
    }
  }

  openForm(typeName, row) {
    const type = this.types.find((candidate) => candidate.typeName === typeName);
    const values = {};
    type.fields.forEach((field) => {
      values[field.apiName] = row ? row[field.apiName] : '';
    });
    this.form = {
      typeName,
      fields: type.fields,
      developerName: row ? row.developerName : null,
      originalLabel: row ? row.label : '',
      label: row ? row.label : '',
      values
    };
    this.errorMessage = undefined;
    this.statusMessage = undefined;
  }

  handleNameChange(event) {
    this.form = { ...this.form, label: event.detail.value };
  }

  handleFieldChange(event) {
    const values = { ...this.form.values, [event.target.dataset.field]: event.detail.value };
    this.form = { ...this.form, values };
  }

  handleCancel() {
    this.form = undefined;
  }

  handleSave() {
    const form = this.form;
    this.start(
      form.typeName,
      form.label,
      saveRow({
        typeName: form.typeName,
        input: { developerName: form.developerName, label: form.label, values: form.values }
      })
    ).then((started) => {
      if (started) {
        this.form = undefined;
      }
    });
  }

  handleCheckAgain() {
    this.load();
    if (this.pending) {
      this.poll(this.pending.jobId, this.pending.label, 1);
    }
  }

  async start(typeName, label, request) {
    this.busy = true;
    this.errorMessage = undefined;
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

  messageFrom(error) {
    return error && error.body && error.body.message ? error.body.message : LOAD_ERROR;
  }
}
