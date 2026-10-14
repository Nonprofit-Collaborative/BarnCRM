import { LightningElement, api } from 'lwc';
import listChildRelationships from '@salesforce/apex/FindController.listChildRelationships';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';
import { messageFrom } from 'c/findCsv';

import RELATED_RECORDS from '@salesforce/label/c.Core_Find_RelatedRecords';
import RELATED_HELP from '@salesforce/label/c.Core_Find_RelatedHelp';
import ADD_RELATED from '@salesforce/label/c.Core_Find_AddRelated';
import HAS from '@salesforce/label/c.Core_Find_Has';
import HAS_NO from '@salesforce/label/c.Core_Find_HasNo';
import WHICH from '@salesforce/label/c.Core_Find_Which';
import RELATED_KIND from '@salesforce/label/c.Core_Find_RelatedKind';
import CHOOSE_RELATED from '@salesforce/label/c.Core_Find_ChooseRelated';
import RELATED_CONDITIONS from '@salesforce/label/c.Core_Find_RelatedConditions';
import RELATED_COLUMNS from '@salesforce/label/c.Core_Find_RelatedColumns';
import ADD_COLUMN from '@salesforce/label/c.Core_Find_AddRelatedColumn';
import RELATED_FIELDS from '@salesforce/label/c.Core_Find_RelatedFields';
import RELATED_ROWS from '@salesforce/label/c.Core_Find_RelatedRows';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import AVAILABLE_FIELDS from '@salesforce/label/c.Core_Find_AvailableFields';
import CHOSEN_FIELDS from '@salesforce/label/c.Core_Find_ChosenFields';

const MAX_ENTRIES = 2;
const NOT_SHOWN = new Set(['address', 'location', 'base64']);

/**
 * Related records in Find (C-36, admin guide find.md sections 7.1 and 7.2, canonical model
 * R-SQ8): up to two "has, or has no, related records matching" conditions, each with its own
 * filter builder over the related object, and up to two related record columns. It reports
 * the document's `related` and `children` keys in a `change` event; the server checks them.
 */
export default class FindRelatedPanel extends LightningElement {
  labels = {
    relatedRecords: RELATED_RECORDS,
    relatedHelp: RELATED_HELP,
    addRelated: ADD_RELATED,
    which: WHICH,
    relatedKind: RELATED_KIND,
    chooseRelated: CHOOSE_RELATED,
    relatedConditions: RELATED_CONDITIONS,
    relatedColumns: RELATED_COLUMNS,
    addColumn: ADD_COLUMN,
    relatedFields: RELATED_FIELDS,
    relatedRows: RELATED_ROWS,
    remove: REMOVE,
    availableFields: AVAILABLE_FIELDS,
    chosenFields: CHOSEN_FIELDS
  };

  options = [];
  conditions = [];
  columns = [];
  fieldsByObject = {};
  errorMessage;
  nextKey = 1;
  loadedFor;
  _objectApiName;

  @api
  get objectApiName() {
    return this._objectApiName;
  }
  set objectApiName(value) {
    this._objectApiName = value;
    this.loadOptions();
  }

  /** The document's `related` entries, when a query is opened. */
  @api
  get related() {
    return this.relatedEntries();
  }
  set related(entries) {
    // Find hands back what this panel just reported; keep the rows being edited.
    if (JSON.stringify(entries || []) === this.lastRelated) {
      return;
    }
    this.conditions = (entries || []).map((entry) => ({
      key: this.key(),
      has: entry.has === false ? 'no' : 'yes',
      kind: `${entry.object}.${entry.field}`,
      object: entry.object,
      field: entry.field,
      filterJson: entry.filter ? JSON.stringify(entry.filter) : '',
      valid: true
    }));
  }

  /** The document's `children` entries, when a query is opened. */
  @api
  get children() {
    return this.childEntries();
  }
  set children(entries) {
    if (JSON.stringify(entries || []) === this.lastChildren) {
      return;
    }
    this.columns = (entries || []).map((entry) => ({
      key: this.key(),
      relationship: entry.relationship,
      fields: [...(entry.fields || [])],
      limit: entry.limit || 10
    }));
    this.columns.forEach((column) => this.loadFields(column.relationship));
  }

  key() {
    return String(this.nextKey++);
  }

  async loadOptions() {
    if (!this._objectApiName || this.loadedFor === this._objectApiName) {
      return;
    }
    this.loadedFor = this._objectApiName;
    try {
      this.options = (await listChildRelationships({ objectApiName: this._objectApiName })) || [];
      this.columns.forEach((column) => this.loadFields(column.relationship));
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  async loadFields(relationship) {
    const option = this.options.find((candidate) => candidate.relationshipName === relationship);
    if (!option || this.fieldsByObject[option.objectName]) {
      return;
    }
    try {
      const info = await getObjectInfo({ objectApiName: option.objectName });
      this.fieldsByObject = { ...this.fieldsByObject, [option.objectName]: info.fields };
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get hasChoices() {
    return [
      { label: HAS, value: 'yes' },
      { label: HAS_NO, value: 'no' }
    ];
  }

  get conditionKinds() {
    return this.options
      .filter((option) => option.filterable)
      .map((option) => ({ label: option.label, value: `${option.objectName}.${option.field}` }));
  }

  get columnKinds() {
    return this.options.map((option) => ({ label: option.label, value: option.relationshipName }));
  }

  get canAddCondition() {
    return this.conditions.length < MAX_ENTRIES && this.conditionKinds.length > 0;
  }

  get addConditionDisabled() {
    return !this.canAddCondition;
  }

  get addColumnDisabled() {
    return this.columns.length >= MAX_ENTRIES || this.columnKinds.length === 0;
  }

  get conditionRows() {
    return this.conditions.map((condition, index) => ({
      ...condition,
      number: index + 1,
      hasKind: !!condition.object
    }));
  }

  get columnRows() {
    return this.columns.map((column) => {
      const option = this.options.find(
        (candidate) => candidate.relationshipName === column.relationship
      );
      const fields = option ? this.fieldsByObject[option.objectName] || [] : [];
      return {
        ...column,
        fieldOptions: fields
          .filter((field) => !NOT_SHOWN.has(field.dataType))
          .map((field) => ({ label: field.label, value: field.apiName })),
        hasKind: !!column.relationship
      };
    });
  }

  relatedEntries() {
    return this.conditions
      .filter((condition) => condition.object)
      .map((condition) => {
        const entry = {
          object: condition.object,
          field: condition.field,
          has: condition.has !== 'no'
        };
        if (condition.filterJson) {
          entry.filter = JSON.parse(condition.filterJson);
        }
        return entry;
      });
  }

  childEntries() {
    return this.columns
      .filter((column) => column.relationship && column.fields.length > 0)
      .map((column) => ({
        relationship: column.relationship,
        fields: [...column.fields],
        limit: Number(column.limit)
      }));
  }

  announce() {
    const related = this.relatedEntries();
    const children = this.childEntries();
    this.lastRelated = JSON.stringify(related);
    this.lastChildren = JSON.stringify(children);
    this.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          related,
          children,
          valid: this.conditions.every((condition) => condition.valid)
        }
      })
    );
  }

  update(list, key, changes) {
    return list.map((item) => (item.key === key ? { ...item, ...changes } : item));
  }

  handleAddCondition() {
    this.conditions = [
      ...this.conditions,
      { key: this.key(), has: 'yes', kind: '', object: '', field: '', filterJson: '', valid: true }
    ];
  }

  handleAddColumn() {
    this.columns = [...this.columns, { key: this.key(), relationship: '', fields: [], limit: 10 }];
  }

  handleHasChange(event) {
    this.conditions = this.update(this.conditions, event.target.dataset.key, {
      has: event.detail.value
    });
    this.announce();
  }

  handleKindChange(event) {
    const [object, field] = event.detail.value.split('.');
    this.conditions = this.update(this.conditions, event.target.dataset.key, {
      kind: event.detail.value,
      object,
      field,
      filterJson: '',
      valid: true
    });
    this.announce();
  }

  handleConditionFilterChange(event) {
    this.conditions = this.update(this.conditions, event.target.dataset.key, {
      filterJson: event.detail.value,
      valid: event.detail.valid
    });
    this.announce();
  }

  handleRemoveCondition(event) {
    this.conditions = this.conditions.filter(
      (condition) => condition.key !== event.target.dataset.key
    );
    this.announce();
  }

  handleColumnKindChange(event) {
    this.columns = this.update(this.columns, event.target.dataset.key, {
      relationship: event.detail.value,
      fields: []
    });
    this.loadFields(event.detail.value);
    this.announce();
  }

  handleColumnFieldsChange(event) {
    this.columns = this.update(this.columns, event.target.dataset.key, {
      fields: [...event.detail.value]
    });
    this.announce();
  }

  handleColumnRowsChange(event) {
    this.columns = this.update(this.columns, event.target.dataset.key, {
      limit: event.target.value
    });
    this.announce();
  }

  handleRemoveColumn(event) {
    this.columns = this.columns.filter((column) => column.key !== event.target.dataset.key);
    this.announce();
  }
}
