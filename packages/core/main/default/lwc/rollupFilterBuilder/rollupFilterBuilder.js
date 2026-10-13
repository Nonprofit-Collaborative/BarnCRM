import { LightningElement, api } from 'lwc';

import ADD_CONDITION from '@salesforce/label/c.Core_RollupFilter_AddCondition';
import FIELD from '@salesforce/label/c.Core_RollupFilter_Field';
import OPERATOR from '@salesforce/label/c.Core_RollupFilter_Operator';
import VALUE from '@salesforce/label/c.Core_RollupFilter_Value';
import REMOVE from '@salesforce/label/c.Core_RollupFilter_Remove';
import LOGIC from '@salesforce/label/c.Core_RollupFilter_Logic';
import LOGIC_HELP from '@salesforce/label/c.Core_RollupFilter_LogicHelp';
import LIST_HELP from '@salesforce/label/c.Core_RollupFilter_ListHelp';
import EVERY_RECORD from '@salesforce/label/c.Core_RollupFilter_EveryRecord';
import WHOSE from '@salesforce/label/c.Core_RollupFilter_Whose';
import AND from '@salesforce/label/c.Core_RollupFilter_And';
import OR from '@salesforce/label/c.Core_RollupFilter_Or';
import NOT from '@salesforce/label/c.Core_RollupFilter_Not';
import TRUE_VALUE from '@salesforce/label/c.Core_RollupFilter_True';
import FALSE_VALUE from '@salesforce/label/c.Core_RollupFilter_False';
import ERROR_INCOMPLETE from '@salesforce/label/c.Core_RollupFilter_ErrorIncomplete';
import ERROR_LOGIC from '@salesforce/label/c.Core_RollupFilter_ErrorLogic';
import OP_EQUALS from '@salesforce/label/c.Core_RollupFilter_OpEquals';
import OP_NOT_EQUALS from '@salesforce/label/c.Core_RollupFilter_OpNotEquals';
import OP_LESS_THAN from '@salesforce/label/c.Core_RollupFilter_OpLessThan';
import OP_LESS_OR_EQUAL from '@salesforce/label/c.Core_RollupFilter_OpLessOrEqual';
import OP_GREATER_THAN from '@salesforce/label/c.Core_RollupFilter_OpGreaterThan';
import OP_GREATER_OR_EQUAL from '@salesforce/label/c.Core_RollupFilter_OpGreaterOrEqual';
import OP_CONTAINS from '@salesforce/label/c.Core_RollupFilter_OpContains';
import OP_DOES_NOT_CONTAIN from '@salesforce/label/c.Core_RollupFilter_OpDoesNotContain';
import OP_STARTS_WITH from '@salesforce/label/c.Core_RollupFilter_OpStartsWith';
import OP_IS_NULL from '@salesforce/label/c.Core_RollupFilter_OpIsNull';
import OP_IS_NOT_NULL from '@salesforce/label/c.Core_RollupFilter_OpIsNotNull';
import OP_IN from '@salesforce/label/c.Core_RollupFilter_OpIn';
import OP_NOT_IN from '@salesforce/label/c.Core_RollupFilter_OpNotIn';
import PHRASE from '@salesforce/label/c.Core_RollupFilter_Phrase';
import PHRASE_NO_VALUE from '@salesforce/label/c.Core_RollupFilter_PhraseNoValue';

/** The operators of canonical model R-R2, in the order they are offered, with their words. */
const OPERATOR_WORDS = {
  equals: OP_EQUALS,
  'not equals': OP_NOT_EQUALS,
  'less than': OP_LESS_THAN,
  'less or equal': OP_LESS_OR_EQUAL,
  'greater than': OP_GREATER_THAN,
  'greater or equal': OP_GREATER_OR_EQUAL,
  contains: OP_CONTAINS,
  'does not contain': OP_DOES_NOT_CONTAIN,
  'starts with': OP_STARTS_WITH,
  'is null': OP_IS_NULL,
  'is not null': OP_IS_NOT_NULL,
  in: OP_IN,
  'not in': OP_NOT_IN
};

const NO_VALUE = new Set(['is null', 'is not null']);
const LIST = new Set(['in', 'not in']);
const NUMBERS = new Set(['double', 'integer', 'long', 'currency', 'percent']);
const DATES = new Set(['date', 'datetime']);
const PICKLISTS = new Set(['picklist', 'multipicklist']);
const LOGIC_TOKEN = /^(\d+|AND|OR|NOT|\(|\))$/;

/** Which operators suit a field of this type. */
function operatorsFor(type) {
  if (type === 'boolean') {
    return ['equals'];
  }
  if (NUMBERS.has(type) || DATES.has(type)) {
    return [
      'equals',
      'not equals',
      'less than',
      'less or equal',
      'greater than',
      'greater or equal',
      'is null',
      'is not null'
    ];
  }
  if (PICKLISTS.has(type)) {
    return ['equals', 'not equals', 'in', 'not in', 'is null', 'is not null'];
  }
  if (type === 'reference' || type === 'id') {
    return ['equals', 'not equals', 'is null', 'is not null'];
  }
  return Object.keys(OPERATOR_WORDS);
}

/** Fills {0}, {1} in a label. */
function format(label, ...values) {
  return values.reduce((text, value, index) => text.replace(`{${index}}`, value), label);
}

/**
 * The filter builder of the Rollup Builder (canonical model R-R2; ADR decision 7): rows of field,
 * comparison and value, and an optional logic string, read back as a sentence. It writes the
 * filter document and nothing else, so an administrator never types a query. Built once, to be
 * shared with Find (plan Section 4.9), which uses the same document.
 *
 * It fires `change` with `detail.value`, the document as JSON, or null when there are no
 * conditions. `validate()` answers what is missing, in words, or null.
 */
export default class RollupFilterBuilder extends LightningElement {
  /** The fields to choose from: { value, label, type, picklistValues }. */
  @api fields = [];
  /** The plural name of the records filtered, for the sentence: "Gifts". */
  @api recordsLabel = '';
  @api label;
  @api disabled = false;

  labels = {
    addCondition: ADD_CONDITION,
    field: FIELD,
    operator: OPERATOR,
    value: VALUE,
    logic: LOGIC,
    logicHelp: LOGIC_HELP,
    listHelp: LIST_HELP
  };

  conditions = [];
  logic = '';

  /** The filter document as JSON, or blank for none. */
  @api
  get value() {
    return this.documentJson();
  }
  set value(json) {
    let document = null;
    try {
      document = json ? JSON.parse(json) : null;
    } catch {
      // An unreadable document is shown as no conditions; the save check refuses it.
      document = null;
    }
    const conditions = document && Array.isArray(document.conditions) ? document.conditions : [];
    this.conditions = conditions.map((condition, index) => ({
      id: index + 1,
      field: condition.field || '',
      operator: condition.operator || '',
      value: condition.value === undefined || condition.value === null ? '' : condition.value
    }));
    this.logic = document && document.logic ? document.logic : '';
  }

  /** What is missing, in words the administrator acts on, or null when the filter is complete. */
  @api
  validate() {
    const incomplete = this.conditions.find(
      (condition) =>
        !condition.field ||
        !condition.operator ||
        (!NO_VALUE.has(condition.operator) && this.isBlank(condition.value))
    );
    if (incomplete) {
      return format(ERROR_INCOMPLETE, incomplete.id);
    }
    if (this.logic && !this.logicIsValid()) {
      return format(ERROR_LOGIC, this.conditions.length);
    }
    return null;
  }

  get rows() {
    return this.conditions.map((condition) => {
      const field = this.fieldByName(condition.field);
      const type = field ? field.type : '';
      const isList = LIST.has(condition.operator);
      const picklistOptions = field && field.picklistValues ? field.picklistValues : [];
      return {
        ...condition,
        key: `condition-${condition.id}`,
        number: `${condition.id}.`,
        removeLabel: format(REMOVE, condition.id),
        operatorOptions: operatorsFor(type).map((operator) => ({
          value: operator,
          label: OPERATOR_WORDS[operator]
        })),
        needsValue: !!condition.operator && !NO_VALUE.has(condition.operator),
        isBoolean: type === 'boolean',
        isPicklistChoice: PICKLISTS.has(type) && isList,
        isPicklistOne: PICKLISTS.has(type) && !isList,
        isTyped: !PICKLISTS.has(type) && type !== 'boolean',
        inputType: this.inputTypeFor(type, isList),
        picklistOptions,
        booleanOptions: [
          { value: 'true', label: TRUE_VALUE },
          { value: 'false', label: FALSE_VALUE }
        ],
        valueText: Array.isArray(condition.value)
          ? condition.value.join(', ')
          : String(condition.value),
        valueList: Array.isArray(condition.value) ? condition.value : [],
        valueHelp: isList ? LIST_HELP : undefined
      };
    });
  }

  get fieldOptions() {
    return (this.fields || []).map((field) => ({ value: field.value, label: field.label }));
  }

  get hasConditions() {
    return this.conditions.length > 0;
  }

  get showLogic() {
    return this.conditions.length > 1;
  }

  /** The filter read back: "Gifts whose Status is one of Received or Refunded and Amount is greater than 0". */
  get sentence() {
    if (!this.hasConditions) {
      return EVERY_RECORD;
    }
    const phraseById = new Map(
      this.conditions.map((condition) => [String(condition.id), this.phrase(condition)])
    );
    let body;
    if (this.logic && this.logicIsValid()) {
      body = this.tokens()
        .map((token) => {
          const upper = token.toUpperCase();
          if (phraseById.has(token)) {
            return phraseById.get(token);
          }
          return { AND: AND, OR: OR, NOT: NOT }[upper] || token;
        })
        .join(' ')
        .replace(/\( /g, '(')
        .replace(/ \)/g, ')');
    } else {
      body = [...phraseById.values()].join(` ${AND} `);
    }
    return format(WHOSE, this.recordsLabel, body);
  }

  phrase(condition) {
    const field = this.fieldByName(condition.field);
    const fieldLabel = field ? field.label : condition.field;
    const words = OPERATOR_WORDS[condition.operator] || condition.operator;
    if (NO_VALUE.has(condition.operator)) {
      return format(PHRASE_NO_VALUE, fieldLabel, words);
    }
    const values = (Array.isArray(condition.value) ? condition.value : [condition.value]).map(
      (value) => this.valueLabel(field, value)
    );
    const joined =
      values.length > 1
        ? `${values.slice(0, -1).join(', ')} ${OR} ${values[values.length - 1]}`
        : values[0];
    return format(PHRASE, fieldLabel, words, joined);
  }

  valueLabel(field, value) {
    if (value === true || value === 'true') {
      return TRUE_VALUE;
    }
    if (value === false || value === 'false') {
      return FALSE_VALUE;
    }
    const option =
      field && field.picklistValues
        ? field.picklistValues.find((entry) => entry.value === value)
        : null;
    return option ? option.label : String(value);
  }

  inputTypeFor(type, isList) {
    if (isList) {
      return 'text';
    }
    if (NUMBERS.has(type)) {
      return 'number';
    }
    return DATES.has(type) ? type : 'text';
  }

  fieldByName(name) {
    return (this.fields || []).find((field) => field.value === name);
  }

  isBlank(value) {
    return (
      value === undefined ||
      value === null ||
      value === '' ||
      (Array.isArray(value) && value.length === 0)
    );
  }

  tokens() {
    return this.logic.replace(/\(/g, ' ( ').replace(/\)/g, ' ) ').trim().split(/\s+/);
  }

  logicIsValid() {
    const ids = new Set(this.conditions.map((condition) => String(condition.id)));
    return this.tokens().every((token) => {
      const upper = token.toUpperCase();
      return LOGIC_TOKEN.test(upper) && (!/^\d+$/.test(upper) || ids.has(upper));
    });
  }

  // ---------------------------------------------------------------------------------- editing

  handleAdd() {
    this.conditions = [
      ...this.conditions,
      { id: this.conditions.length + 1, field: '', operator: '', value: '' }
    ];
    this.notify();
  }

  handleRemove(event) {
    const removed = Number(event.currentTarget.dataset.id);
    this.conditions = this.conditions
      .filter((condition) => condition.id !== removed)
      .map((condition, index) => ({ ...condition, id: index + 1 }));
    // The numbers moved, so a logic string written for the old ones no longer means the same.
    this.logic = '';
    this.notify();
  }

  handleField(event) {
    const field = this.fieldByName(event.detail.value);
    const operators = operatorsFor(field ? field.type : '');
    this.update(event, {
      field: event.detail.value,
      operator: operators[0],
      value: ''
    });
  }

  handleOperator(event) {
    const condition = this.conditionOf(event);
    const listChanged = LIST.has(condition.operator) !== LIST.has(event.detail.value);
    this.update(event, {
      operator: event.detail.value,
      value: listChanged || NO_VALUE.has(event.detail.value) ? '' : condition.value
    });
  }

  handleValue(event) {
    const condition = this.conditionOf(event);
    const field = this.fieldByName(condition.field);
    const type = field ? field.type : '';
    const raw = event.detail.value;
    let value;
    if (Array.isArray(raw)) {
      value = raw;
    } else if (LIST.has(condition.operator)) {
      value = String(raw || '')
        .split(',')
        .map((part) => part.trim())
        .filter((part) => part !== '')
        .map((part) => (NUMBERS.has(type) ? Number(part) : part));
    } else if (type === 'boolean') {
      value = raw === 'true';
    } else if (NUMBERS.has(type)) {
      value = raw === '' || raw === null ? '' : Number(raw);
    } else {
      value = raw;
    }
    this.update(event, { value });
  }

  handleLogic(event) {
    this.logic = (event.detail.value || '').toUpperCase();
    this.notify();
  }

  conditionOf(event) {
    const id = Number(event.target.dataset.id);
    return this.conditions.find((condition) => condition.id === id);
  }

  update(event, changes) {
    const id = Number(event.target.dataset.id);
    this.conditions = this.conditions.map((condition) => {
      return condition.id === id ? { ...condition, ...changes } : condition;
    });
    this.notify();
  }

  documentJson() {
    if (!this.hasConditions) {
      return null;
    }
    const document = {
      version: 1,
      conditions: this.conditions.map((condition) => {
        const entry = { id: condition.id, field: condition.field, operator: condition.operator };
        if (!NO_VALUE.has(condition.operator)) {
          entry.value = condition.value;
        }
        return entry;
      })
    };
    if (this.logic) {
      document.logic = this.logic;
    }
    return JSON.stringify(document);
  }

  notify() {
    this.dispatchEvent(new CustomEvent('change', { detail: { value: this.documentJson() } }));
  }
}
