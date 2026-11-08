import LightningModal from 'lightning/modal';
import { api } from 'lwc';

import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';

/**
 * One small form for a record that belongs to an event (a ticket type, a promo code, a track, a
 * session or a speaker), shared by the event page's panels. It saves through the platform's
 * record form, so field access, validation rules and automations apply as on any record page.
 *
 * Open it with EventRecordModal.open({ label, size: 'small', objectApiName, recordId, fields,
 * defaults }): `fields` are the API names shown, in order; `defaults` are values set on a new
 * record and kept out of sight (the event it belongs to). It resolves `{ id }` once saved and
 * undefined when closed.
 */
export default class EventRecordModal extends LightningModal {
  @api objectApiName;
  /** Empty for a new record. */
  @api recordId;
  @api fields = [];
  @api defaults = {};

  labels = { save: SAVE, cancel: CANCEL };
  busy = false;

  get visibleFields() {
    return (this.fields || []).map((name) => ({
      name,
      value: this.recordId ? undefined : this.defaultFor(name)
    }));
  }

  get hiddenFields() {
    if (this.recordId) {
      return [];
    }
    const shown = new Set(this.fields || []);
    return Object.keys(this.defaults || {})
      .filter((name) => !shown.has(name))
      .map((name) => ({ name, value: this.defaults[name] }));
  }

  defaultFor(name) {
    return this.defaults ? this.defaults[name] : undefined;
  }

  handleSave() {
    this.busy = true;
    this.template.querySelector('lightning-record-edit-form').submit();
  }

  handleSuccess(event) {
    this.busy = false;
    this.close({ id: event.detail.id });
  }

  handleError() {
    this.busy = false;
  }

  handleCancel() {
    this.close();
  }
}
