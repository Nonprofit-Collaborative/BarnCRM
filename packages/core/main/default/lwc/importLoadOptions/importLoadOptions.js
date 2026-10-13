import { LightningElement, api } from 'lwc';

import operationLabel from '@salesforce/label/c.Core_Import_LoadOperationLabel';
import insertOption from '@salesforce/label/c.Core_Import_OperationInsert';
import updateOption from '@salesforce/label/c.Core_Import_OperationUpdate';
import upsertOption from '@salesforce/label/c.Core_Import_OperationUpsert';
import insertHelp from '@salesforce/label/c.Core_Import_LoadInsertHelp';
import updateHelp from '@salesforce/label/c.Core_Import_LoadUpdateHelp';
import upsertHelp from '@salesforce/label/c.Core_Import_LoadUpsertHelp';
import matchFieldLabel from '@salesforce/label/c.Core_Import_LoadMatchFieldLabel';
import noKeyFields from '@salesforce/label/c.Core_Import_LoadNoKeyFields';
import notFoundLabel from '@salesforce/label/c.Core_Import_LookupNotFoundLabel';
import rejectOption from '@salesforce/label/c.Core_Import_LookupRejectOption';
import leaveEmptyOption from '@salesforce/label/c.Core_Import_LookupLeaveEmptyOption';
import rejectHelp from '@salesforce/label/c.Core_Import_LookupRejectHelp';
import leaveEmptyHelp from '@salesforce/label/c.Core_Import_LookupLeaveEmptyHelp';

/** The values Import_Template__c.Load_Operation__c and Lookup_Not_Found__c hold. */
export const INSERT = 'Insert';
export const UPDATE = 'Update by record Id';
export const UPSERT = 'Upsert by external ID';
export const LOOKUP_REJECT = 'Reject the row';
export const LOOKUP_LEAVE_EMPTY = 'Leave it empty';

const OPERATIONS = [
  { value: INSERT, label: insertOption, help: insertHelp },
  { value: UPDATE, label: updateOption, help: updateHelp },
  { value: UPSERT, label: upsertOption, help: upsertHelp }
];

/**
 * What a mapping that loads one object does with each row (canonical model R-IT12, R-IT13):
 * insert, update by record ID, or upsert by an external ID field, with what each choice risks,
 * the field an upsert matches on, and what a row does when a lookup finds no record.
 * Presentational: the wizard owns the values and hears every change through a `change` event
 * whose detail is `{ operation, matchField, lookupNotFound }`.
 * See docs/admin-guide/importing.md, section 9.
 */
export default class ImportLoadOptions extends LightningElement {
  @api operation = INSERT;
  @api matchField = '';
  @api lookupNotFound = LOOKUP_REJECT;
  /** The operations the object allows (R-IT14); all three when not given. */
  @api operations;
  /** The object's external ID fields an upsert can match on: `{ label, value }`. */
  @api keyFields = [];

  labels = { operationLabel, matchFieldLabel, notFoundLabel, noKeyFields };

  get operationOptions() {
    const allowed = this.operations && this.operations.length > 0 ? this.operations : null;
    return OPERATIONS.filter((each) => !allowed || allowed.includes(each.value)).map((each) => ({
      label: each.label,
      value: each.value
    }));
  }

  get operationHelp() {
    const found = OPERATIONS.find((each) => each.value === this.operation);
    return found ? found.help : '';
  }

  get isUpsert() {
    return this.operation === UPSERT;
  }

  get hasKeyFields() {
    return (this.keyFields || []).length > 0;
  }

  get keyFieldOptions() {
    return (this.keyFields || []).map((field) => ({ label: field.label, value: field.value }));
  }

  get notFoundOptions() {
    return [
      { label: rejectOption, value: LOOKUP_REJECT },
      { label: leaveEmptyOption, value: LOOKUP_LEAVE_EMPTY }
    ];
  }

  get notFoundHelp() {
    return this.lookupNotFound === LOOKUP_LEAVE_EMPTY ? leaveEmptyHelp : rejectHelp;
  }

  handleOperationChange(event) {
    this.announce({ operation: event.detail.value });
  }

  handleMatchFieldChange(event) {
    this.announce({ matchField: event.detail.value });
  }

  handleNotFoundChange(event) {
    this.announce({ lookupNotFound: event.detail.value });
  }

  announce(change) {
    const detail = {
      operation: this.operation,
      matchField: this.matchField,
      lookupNotFound: this.lookupNotFound,
      ...change
    };
    this.dispatchEvent(new CustomEvent('change', { detail }));
  }
}
