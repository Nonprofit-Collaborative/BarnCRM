import { LightningElement, api } from 'lwc';

import operationLabel from '@salesforce/label/c.Core_Import_LoadOperationLabel';
import insertOption from '@salesforce/label/c.Core_Import_OperationInsert';
import updateOption from '@salesforce/label/c.Core_Import_OperationUpdate';
import upsertOption from '@salesforce/label/c.Core_Import_OperationUpsert';
import insertHelp from '@salesforce/label/c.Core_Import_LoadInsertHelp';
import updateHelp from '@salesforce/label/c.Core_Import_LoadUpdateHelp';
import upsertHelp from '@salesforce/label/c.Core_Import_LoadUpsertHelp';
import updateByFieldOption from '@salesforce/label/c.Core_Import_OperationUpdateByField';
import updateByFieldHelp from '@salesforce/label/c.Core_Import_LoadUpdateByFieldHelp';
import noMatchFields from '@salesforce/label/c.Core_Import_LoadNoMatchFields';
import matchFieldLabel from '@salesforce/label/c.Core_Import_LoadMatchFieldLabel';
import noKeyFields from '@salesforce/label/c.Core_Import_LoadNoKeyFields';
import notFoundLabel from '@salesforce/label/c.Core_Import_LookupNotFoundLabel';
import rejectOption from '@salesforce/label/c.Core_Import_LookupRejectOption';
import leaveEmptyOption from '@salesforce/label/c.Core_Import_LookupLeaveEmptyOption';
import rejectHelp from '@salesforce/label/c.Core_Import_LookupRejectHelp';
import leaveEmptyHelp from '@salesforce/label/c.Core_Import_LookupLeaveEmptyHelp';
import relatedLabel from '@salesforce/label/c.Core_Import_RelatedLabel';
import relatedNone from '@salesforce/label/c.Core_Import_RelatedNone';
import relatedHelp from '@salesforce/label/c.Core_Import_RelatedHelp';
import relatedInsertHelp from '@salesforce/label/c.Core_Import_RelatedInsertHelp';

/** The values Import_Template__c.Load_Operation__c and Lookup_Not_Found__c hold. */
export const INSERT = 'Insert';
export const UPDATE = 'Update by record Id';
export const UPDATE_BY_FIELD = 'Update by a matching field';
export const UPSERT = 'Upsert by external ID';
export const LOOKUP_REJECT = 'Reject the row';
export const LOOKUP_LEAVE_EMPTY = 'Leave it empty';

const OPERATIONS = [
  { value: INSERT, label: insertOption, help: insertHelp },
  { value: UPDATE, label: updateOption, help: updateHelp },
  { value: UPDATE_BY_FIELD, label: updateByFieldOption, help: updateByFieldHelp },
  { value: UPSERT, label: upsertOption, help: upsertHelp }
];

/**
 * What a mapping that loads one object does with each row (canonical model R-IT12, R-IT13):
 * insert, update by record ID, update by a field the user chooses, or upsert by an external ID
 * field, with what each choice risks, the field an update or upsert matches on, and what a row
 * does when a lookup finds no record, and the related records each row also creates (R-IT17),
 * offered under every operation but Insert, which has no parent key.
 * Presentational: the wizard owns the values and hears every change through a `change` event
 * whose detail is `{ operation, matchField, lookupNotFound, related }`.
 * See docs/admin-guide/importing.md, section 9.
 */
export default class ImportLoadOptions extends LightningElement {
  @api operation = INSERT;
  @api matchField = '';
  @api lookupNotFound = LOOKUP_REJECT;
  /** The operations the object allows (R-IT14); all four when not given. */
  @api operations;
  /** The object's external ID fields an upsert can match on: `{ label, value }`. */
  @api keyFields = [];
  /** The object's text, email and phone fields an update can match on: `{ label, value }`. */
  @api rowMatchFields = [];
  /** The related records chosen, `Object.Field`, or empty for none. */
  @api related = '';
  /** The related records the object offers: `{ label, value }`. */
  @api relatedOptions = [];

  labels = {
    operationLabel,
    matchFieldLabel,
    notFoundLabel,
    relatedLabel,
    relatedHelp,
    relatedInsertHelp
  };

  /** Related records need a parent key, which Insert does not have. */
  get offersRelated() {
    return this.operation !== INSERT;
  }

  get relatedChoices() {
    return [{ label: relatedNone, value: '' }].concat(
      (this.relatedOptions || []).map((each) => ({ label: each.label, value: each.value }))
    );
  }

  handleRelatedChange(event) {
    this.announce({ related: event.detail.value });
  }

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

  /** Whether the operation finds records by a field: an upsert, or an update by a field. */
  get usesMatchField() {
    return this.operation === UPSERT || this.operation === UPDATE_BY_FIELD;
  }

  /** The fields the operation may match on: External ID fields for an upsert, else any. */
  get offeredFields() {
    const fields = this.operation === UPSERT ? this.keyFields : this.rowMatchFields;
    return fields || [];
  }

  get hasKeyFields() {
    return this.offeredFields.length > 0;
  }

  get keyFieldOptions() {
    return this.offeredFields.map((field) => ({ label: field.label, value: field.value }));
  }

  get noFieldsText() {
    return this.operation === UPSERT ? noKeyFields : noMatchFields;
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
      related: this.related || '',
      ...change
    };
    this.dispatchEvent(new CustomEvent('change', { detail }));
  }
}
