import { LightningElement, api, track } from 'lwc';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';
import {
  OPERATORS,
  VALUE_KINDS,
  isFilterableField,
  logicProblem,
  operatorsFor,
  parseDocument,
  serializeDocument,
  toDocumentValue,
  toInputValue,
  valueKindFor,
  valueProblem
} from 'c/filterDocument';

import ADD_CONDITION from '@salesforce/label/c.Core_Filter_AddCondition';
import REMOVE_CONDITION from '@salesforce/label/c.Core_Filter_RemoveCondition';
import CONDITION_LEGEND from '@salesforce/label/c.Core_Filter_ConditionLegend';
import FIELD from '@salesforce/label/c.Core_Filter_Field';
import FIELD_ON from '@salesforce/label/c.Core_Filter_FieldOn';
import PARENT_FIELDS from '@salesforce/label/c.Core_Filter_ParentFields';
import CHOOSE_FIELD from '@salesforce/label/c.Core_Filter_ChooseField';
import OPERATOR from '@salesforce/label/c.Core_Filter_Operator';
import CHOOSE_OPERATOR from '@salesforce/label/c.Core_Filter_ChooseOperator';
import VALUE from '@salesforce/label/c.Core_Filter_Value';
import VALUES_ONE_PER_LINE from '@salesforce/label/c.Core_Filter_ValuesOnePerLine';
import DAYS from '@salesforce/label/c.Core_Filter_Days';
import AVAILABLE_VALUES from '@salesforce/label/c.Core_Filter_AvailableValues';
import CHOSEN_VALUES from '@salesforce/label/c.Core_Filter_ChosenValues';
import TRUE_LABEL from '@salesforce/label/c.Core_Filter_True';
import FALSE_LABEL from '@salesforce/label/c.Core_Filter_False';
import USE_LOGIC from '@salesforce/label/c.Core_Filter_UseLogic';
import LOGIC from '@salesforce/label/c.Core_Filter_Logic';
import LOGIC_HELP from '@salesforce/label/c.Core_Filter_LogicHelp';
import EMPTY from '@salesforce/label/c.Core_Filter_Empty';
import LOADING from '@salesforce/label/c.Core_Filter_Loading';
import ERROR_CHOOSE_FIELD from '@salesforce/label/c.Core_Filter_ErrorChooseField';
import ERROR_CHOOSE_OPERATOR from '@salesforce/label/c.Core_Filter_ErrorChooseOperator';
import ERROR_VALUE_REQUIRED from '@salesforce/label/c.Core_Filter_ErrorValueRequired';
import ERROR_NUMBER from '@salesforce/label/c.Core_Filter_ErrorNumber';
import ERROR_DAYS from '@salesforce/label/c.Core_Filter_ErrorDays';
import ERROR_FIELD_UNAVAILABLE from '@salesforce/label/c.Core_Filter_ErrorFieldUnavailable';
import ERROR_LOGIC_SYNTAX from '@salesforce/label/c.Core_Filter_ErrorLogicSyntax';
import ERROR_LOGIC_UNKNOWN from '@salesforce/label/c.Core_Filter_ErrorLogicUnknown';
import ERROR_LOGIC_MISSING from '@salesforce/label/c.Core_Filter_ErrorLogicMissing';
import ERROR_INVALID_DOCUMENT from '@salesforce/label/c.Core_Filter_ErrorInvalidDocument';
import ERROR_SUMMARY from '@salesforce/label/c.Core_Filter_ErrorSummary';
import SUMMARY_ALL from '@salesforce/label/c.Core_Filter_SummaryAll';
import SUMMARY_LOGIC from '@salesforce/label/c.Core_Filter_SummaryLogic';
import OP_EQUALS from '@salesforce/label/c.Core_Filter_OpEquals';
import OP_NOT_EQUALS from '@salesforce/label/c.Core_Filter_OpNotEquals';
import OP_LESS_THAN from '@salesforce/label/c.Core_Filter_OpLessThan';
import OP_LESS_OR_EQUAL from '@salesforce/label/c.Core_Filter_OpLessOrEqual';
import OP_GREATER_THAN from '@salesforce/label/c.Core_Filter_OpGreaterThan';
import OP_GREATER_OR_EQUAL from '@salesforce/label/c.Core_Filter_OpGreaterOrEqual';
import OP_CONTAINS from '@salesforce/label/c.Core_Filter_OpContains';
import OP_NOT_CONTAINS from '@salesforce/label/c.Core_Filter_OpNotContains';
import OP_STARTS_WITH from '@salesforce/label/c.Core_Filter_OpStartsWith';
import OP_IS_NULL from '@salesforce/label/c.Core_Filter_OpIsNull';
import OP_IS_NOT_NULL from '@salesforce/label/c.Core_Filter_OpIsNotNull';
import OP_IN from '@salesforce/label/c.Core_Filter_OpIn';
import OP_NOT_IN from '@salesforce/label/c.Core_Filter_OpNotIn';
import OP_THIS_YEAR from '@salesforce/label/c.Core_Filter_OpThisYear';
import OP_LAST_YEAR from '@salesforce/label/c.Core_Filter_OpLastYear';
import OP_LAST_N_DAYS from '@salesforce/label/c.Core_Filter_OpLastNDays';
import LAST_N_DAYS_VALUE from '@salesforce/label/c.Core_Filter_LastNDaysValue';

const OPERATOR_LABELS = {
  [OPERATORS.EQUALS]: OP_EQUALS,
  [OPERATORS.NOT_EQUALS]: OP_NOT_EQUALS,
  [OPERATORS.LESS_THAN]: OP_LESS_THAN,
  [OPERATORS.LESS_OR_EQUAL]: OP_LESS_OR_EQUAL,
  [OPERATORS.GREATER_THAN]: OP_GREATER_THAN,
  [OPERATORS.GREATER_OR_EQUAL]: OP_GREATER_OR_EQUAL,
  [OPERATORS.CONTAINS]: OP_CONTAINS,
  [OPERATORS.NOT_CONTAINS]: OP_NOT_CONTAINS,
  [OPERATORS.STARTS_WITH]: OP_STARTS_WITH,
  [OPERATORS.IS_NULL]: OP_IS_NULL,
  [OPERATORS.IS_NOT_NULL]: OP_IS_NOT_NULL,
  [OPERATORS.IN]: OP_IN,
  [OPERATORS.NOT_IN]: OP_NOT_IN,
  [OPERATORS.THIS_YEAR]: OP_THIS_YEAR,
  [OPERATORS.LAST_YEAR]: OP_LAST_YEAR,
  [OPERATORS.LAST_N_DAYS]: OP_LAST_N_DAYS
};

const VALUE_PROBLEM_LABELS = {
  valueRequired: ERROR_VALUE_REQUIRED,
  number: ERROR_NUMBER,
  days: ERROR_DAYS
};

const FIELD_PREFIX = 'f:';
const PARENT_PREFIX = 'r:';

function format(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

/**
 * The shared filter builder: rows of field, operator and value, plus an optional condition logic
 * string, over one object, reading and writing the filter document of canonical model R-R2.
 *
 * It is the document's only writer, for the Rollups page and for Find. Fields come from
 * QueryFieldCatalog, the running user's describe, so a field the user cannot see is never offered;
 * a saved condition naming one is shown with an error rather than dropped. Every change fires a
 * `change` event whose detail carries the document (an empty string when there are no conditions),
 * whether it is valid, and a plain sentence describing it.
 */
export default class FilterBuilder extends LightningElement {
  /** API name of the object the conditions test. */
  @api
  get objectApiName() {
    return this._objectApiName;
  }
  set objectApiName(value) {
    const changed = value !== this._objectApiName;
    this._objectApiName = value;
    if (changed && this.connected) {
      this.rebuild();
    }
  }

  /** The R-R2 filter document as JSON text; empty means every record. */
  @api
  get value() {
    return this.currentDocument();
  }
  set value(text) {
    const incoming = text || '';
    if (incoming === this.lastEmitted) {
      return;
    }
    this._value = incoming;
    if (this.connected) {
      this.rebuild();
    }
  }

  /** How many lookups a condition may cross to a parent's field: 0, 1 or 2 (the default). */
  @api parentDepth = 2;

  /** Leaves out "is this year", "is last year" and "is in the last N days". */
  @api hideRelativeDates = false;

  /** Shows the conditions without letting them change. */
  @api disabled = false;

  labels = {
    addCondition: ADD_CONDITION,
    useLogic: USE_LOGIC,
    logic: LOGIC,
    logicHelp: LOGIC_HELP,
    empty: EMPTY,
    loading: LOADING,
    errorSummary: ERROR_SUMMARY,
    operator: OPERATOR,
    chooseOperator: CHOOSE_OPERATOR,
    value: VALUE,
    valuesOnePerLine: VALUES_ONE_PER_LINE,
    days: DAYS,
    availableValues: AVAILABLE_VALUES,
    chosenValues: CHOSEN_VALUES
  };

  @track rows = [];
  logicEnabled = false;
  logicText = '';
  loading = false;
  loadError;
  showErrors = false;

  _objectApiName;
  _value = '';
  connected = false;
  lastEmitted;
  nextKey = 0;
  infoByObject = new Map();

  connectedCallback() {
    this.connected = true;
    this.rebuild();
  }

  disconnectedCallback() {
    this.connected = false;
  }

  /** Checks every condition and the logic; returns { valid, message }. Shows nothing. */
  @api
  validate() {
    const message = this.firstProblem();
    return { valid: !message, message: message || '' };
  }

  /** Checks every condition, shows what needs fixing next to it, and returns whether it is valid. */
  @api
  reportValidity() {
    this.showErrors = true;
    return this.validate().valid;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return !this.loading && !this.loadError && this.rows.length === 0;
  }

  get canAdd() {
    return !this.disabled && !this.loading && !this.loadError;
  }

  get addDisabled() {
    return !this.canAdd;
  }

  get showLogicToggle() {
    return this.rows.length > 1 || this.logicEnabled;
  }

  get logicError() {
    if (!this.showErrors || !this.logicEnabled) {
      return undefined;
    }
    return this.logicMessage();
  }

  get showErrorSummary() {
    return this.showErrors && !!this.firstProblem();
  }

  get booleanOptions() {
    return [
      { label: TRUE_LABEL, value: 'true' },
      { label: FALSE_LABEL, value: 'false' }
    ];
  }

  /** One view per condition, with everything the markup needs worked out here. */
  get rowViews() {
    return this.rows.map((row, index) => {
      const number = String(index + 1);
      const field = this.leafField(row);
      const kind = valueKindFor(field, row.operator);
      const problem = this.rowProblem(row);
      return {
        key: row.key,
        number,
        legend: format(CONDITION_LEGEND, number),
        removeLabel: format(REMOVE_CONDITION, number),
        segments: this.segmentViews(row),
        operatorOptions: operatorsFor(field, !this.hideRelativeDates).map((operator) => ({
          label: OPERATOR_LABELS[operator],
          value: operator
        })),
        operator: row.operator,
        operatorDisabled: this.disabled || !field,
        value: row.inputValue,
        picklistOptions: field ? this.picklistOptions(field) : [],
        isText: kind === VALUE_KINDS.TEXT,
        isNumber: kind === VALUE_KINDS.NUMBER,
        isDate: kind === VALUE_KINDS.DATE,
        isDateTime: kind === VALUE_KINDS.DATETIME,
        isBoolean: kind === VALUE_KINDS.BOOLEAN,
        isPick: kind === VALUE_KINDS.PICK,
        isPickList: kind === VALUE_KINDS.PICK_LIST,
        isLines: kind === VALUE_KINDS.LINES,
        isDays: kind === VALUE_KINDS.DAYS,
        error: this.showErrors || row.unavailable ? problem : undefined
      };
    });
  }

  segmentViews(row) {
    return row.segments.map((segment, depth) => {
      const info = this.infoByObject.get(segment.objectApiName);
      return {
        key: `${row.key}-${depth}`,
        depth: String(depth),
        label: depth === 0 ? FIELD : format(FIELD_ON, info ? info.label : segment.objectApiName),
        value: segment.selection,
        options: info ? this.fieldOptions(info, depth) : [],
        placeholder: CHOOSE_FIELD,
        disabled: this.disabled || !info
      };
    });
  }

  fieldOptions(info, depth) {
    const options = [];
    const canOpenParents = depth < Math.min(Number(this.parentDepth) || 0, 2);
    for (const field of info.fields) {
      if (isFilterableField(field)) {
        options.push({ label: field.label, value: FIELD_PREFIX + field.apiName });
      }
      if (canOpenParents && field.referenceTo && field.relationshipName) {
        options.push({
          label: format(PARENT_FIELDS, field.label),
          value: PARENT_PREFIX + field.relationshipName
        });
      }
    }
    return options;
  }

  picklistOptions(field) {
    return (field.picklistValues || []).map((entry) => ({
      label: entry.label,
      value: entry.value
    }));
  }

  /* ---------- events from the markup ---------- */

  handleAdd() {
    this.rows = [...this.rows, this.newRow()];
    this.emitChange();
  }

  handleRemove(event) {
    const key = event.currentTarget.dataset.key;
    this.rows = this.rows.filter((row) => row.key !== key);
    if (this.rows.length < 2 && !this.logicText) {
      this.logicEnabled = false;
    }
    this.emitChange();
  }

  async handleFieldChange(event) {
    const key = event.currentTarget.dataset.key;
    const depth = Number(event.currentTarget.dataset.depth);
    const selection = event.detail.value;
    const row = this.rows.find((candidate) => candidate.key === key);
    if (!row) {
      return;
    }
    const segments = row.segments.slice(0, depth + 1);
    segments[depth] = { ...segments[depth], selection };
    if (selection.startsWith(PARENT_PREFIX)) {
      const lookup = this.lookupField(segments[depth].objectApiName, selection);
      if (lookup) {
        segments.push({ objectApiName: lookup.referenceTo, selection: '' });
        this.updateRow(key, { segments, operator: '', inputValue: '', unavailable: false });
        await this.loadInfo(lookup.referenceTo);
        this.rows = [...this.rows];
      }
    } else {
      const updated = { ...row, segments };
      const field = this.leafField(updated);
      const keepOperator = operatorsFor(field, !this.hideRelativeDates).includes(row.operator);
      this.updateRow(key, {
        segments,
        operator: keepOperator ? row.operator : '',
        inputValue: keepOperator ? row.inputValue : '',
        unavailable: false
      });
    }
    this.emitChange();
  }

  handleOperatorChange(event) {
    const key = event.currentTarget.dataset.key;
    const operator = event.detail.value;
    const row = this.rows.find((candidate) => candidate.key === key);
    const field = this.leafField(row);
    const sameKind = valueKindFor(field, operator) === valueKindFor(field, row.operator);
    const emptyValue = valueKindFor(field, operator) === VALUE_KINDS.PICK_LIST ? [] : '';
    this.updateRow(key, { operator, inputValue: sameKind ? row.inputValue : emptyValue });
    this.emitChange();
  }

  handleValueChange(event) {
    const key = event.currentTarget.dataset.key;
    const detail = event.detail || {};
    const value = detail.value !== undefined ? detail.value : event.target.value;
    this.updateRow(key, { inputValue: value });
    this.emitChange();
  }

  handleLogicToggle(event) {
    this.logicEnabled = event.target.checked;
    if (this.logicEnabled && !this.logicText) {
      this.logicText = this.rows.map((row, index) => String(index + 1)).join(' AND ');
    }
    this.emitChange();
  }

  handleLogicChange(event) {
    this.logicText = event.target.value;
    this.emitChange();
  }

  /* ---------- state ---------- */

  newRow() {
    this.nextKey++;
    return {
      key: `row-${this.nextKey}`,
      segments: [{ objectApiName: this._objectApiName, selection: '' }],
      operator: '',
      inputValue: '',
      unavailable: false,
      rawField: ''
    };
  }

  updateRow(key, changes) {
    this.rows = this.rows.map((row) => (row.key === key ? { ...row, ...changes } : row));
  }

  lookupField(objectApiName, selection) {
    const info = this.infoByObject.get(objectApiName);
    const relationship = selection.substring(PARENT_PREFIX.length);
    return info
      ? info.fields.find(
          (field) =>
            field.relationshipName &&
            field.relationshipName.toLowerCase() === relationship.toLowerCase()
        )
      : undefined;
  }

  /** The field a row ends on, or undefined while it is not chosen yet. */
  leafField(row) {
    if (!row || row.unavailable) {
      return undefined;
    }
    const last = row.segments[row.segments.length - 1];
    if (!last || !last.selection.startsWith(FIELD_PREFIX)) {
      return undefined;
    }
    const info = this.infoByObject.get(last.objectApiName);
    const apiName = last.selection.substring(FIELD_PREFIX.length);
    return info ? info.fields.find((field) => field.apiName === apiName) : undefined;
  }

  /** `Household__r.Name`, from the relationship names and the field the row ends on. */
  fieldPath(row) {
    if (row.unavailable) {
      return row.rawField;
    }
    return row.segments
      .map((segment) =>
        segment.selection.substring(
          segment.selection.startsWith(PARENT_PREFIX) ? PARENT_PREFIX.length : FIELD_PREFIX.length
        )
      )
      .join('.');
  }

  /** The field's label with the lookups it crosses: `Contact > Account > Account Name`. */
  fieldLabelPath(row) {
    return row.segments
      .map((segment) => {
        const info = this.infoByObject.get(segment.objectApiName);
        if (!info) {
          return segment.selection;
        }
        if (segment.selection.startsWith(PARENT_PREFIX)) {
          const lookup = this.lookupField(segment.objectApiName, segment.selection);
          return lookup ? lookup.label : segment.selection;
        }
        const apiName = segment.selection.substring(FIELD_PREFIX.length);
        const field = info.fields.find((candidate) => candidate.apiName === apiName);
        return field ? field.label : apiName;
      })
      .join(' > ');
  }

  rowProblem(row) {
    if (row.unavailable) {
      return format(ERROR_FIELD_UNAVAILABLE, row.rawField);
    }
    const field = this.leafField(row);
    if (!field) {
      return ERROR_CHOOSE_FIELD;
    }
    if (!row.operator || !operatorsFor(field, !this.hideRelativeDates).includes(row.operator)) {
      return ERROR_CHOOSE_OPERATOR;
    }
    const problem = valueProblem(valueKindFor(field, row.operator), row.inputValue);
    return problem ? VALUE_PROBLEM_LABELS[problem] : undefined;
  }

  logicMessage() {
    const found = logicProblem(this.logicText, this.rows.length);
    if (!found) {
      return undefined;
    }
    if (found.problem === 'unknown') {
      return format(ERROR_LOGIC_UNKNOWN, found.condition);
    }
    if (found.problem === 'missing') {
      return format(ERROR_LOGIC_MISSING, found.condition);
    }
    return ERROR_LOGIC_SYNTAX;
  }

  firstProblem() {
    if (this.loadError) {
      return this.loadError;
    }
    for (const row of this.rows) {
      const problem = this.rowProblem(row);
      if (problem) {
        return problem;
      }
    }
    return this.logicEnabled && this.rows.length > 0 ? this.logicMessage() : undefined;
  }

  currentDocument() {
    if (this.loading || this.loadError) {
      return this._value;
    }
    const conditions = this.rows.map((row) => {
      const field = this.leafField(row);
      const kind = valueKindFor(field, row.operator);
      return {
        field: this.fieldPath(row),
        operator: row.unavailable ? row.rawOperator : row.operator,
        value: row.unavailable ? row.rawValue : toDocumentValue(kind, row.inputValue)
      };
    });
    return serializeDocument(conditions, this.logicEnabled ? this.logicText : '');
  }

  summary() {
    const parts = this.rows.map((row, index) => {
      const field = this.leafField(row);
      if (!field) {
        return `${index + 1}. ${row.rawField || ''}`.trim();
      }
      const kind = valueKindFor(field, row.operator);
      let text;
      if (row.operator === OPERATORS.LAST_N_DAYS) {
        text = format(LAST_N_DAYS_VALUE, String(row.inputValue));
      } else {
        const valueText = this.valueText(field, kind, row.inputValue);
        text = [OPERATOR_LABELS[row.operator] || '', valueText].filter((part) => part).join(' ');
      }
      const condition = `${this.fieldLabelPath(row)} ${text}`.trim();
      return this.logicEnabled ? `${index + 1}. ${condition}` : condition;
    });
    if (parts.length === 0) {
      return EMPTY;
    }
    return this.logicEnabled
      ? format(SUMMARY_LOGIC, parts.join('; '), this.logicText)
      : format(SUMMARY_ALL, parts.join('; '));
  }

  valueText(field, kind, inputValue) {
    const labelOf = (value) => {
      const entry = (field.picklistValues || []).find((option) => option.value === value);
      return entry ? entry.label : value;
    };
    switch (kind) {
      case VALUE_KINDS.NONE:
        return '';
      case VALUE_KINDS.BOOLEAN:
        return inputValue === 'true' ? TRUE_LABEL : FALSE_LABEL;
      case VALUE_KINDS.PICK:
        return labelOf(inputValue);
      case VALUE_KINDS.PICK_LIST:
      case VALUE_KINDS.LINES:
        return toDocumentValue(kind, inputValue).map(labelOf).join(', ');
      default:
        return String(inputValue || '');
    }
  }

  emitChange() {
    const document = this.currentDocument();
    this.lastEmitted = document;
    this._value = document;
    const message = this.firstProblem();
    this.dispatchEvent(
      new CustomEvent('change', {
        detail: { value: document, valid: !message, summary: this.summary() }
      })
    );
  }

  /* ---------- loading ---------- */

  async loadInfo(objectApiName) {
    if (!this.infoByObject.has(objectApiName)) {
      const info = await getObjectInfo({ objectApiName });
      this.infoByObject.set(objectApiName, info);
    }
    return this.infoByObject.get(objectApiName);
  }

  /** Reads the object and the document into rows, loading every object a path crosses. */
  async rebuild() {
    if (!this._objectApiName) {
      return;
    }
    this.loading = true;
    this.loadError = undefined;
    const objectApiName = this._objectApiName;
    try {
      await this.loadInfo(objectApiName);
      let parsed;
      try {
        parsed = parseDocument(this._value);
      } catch {
        this.loadError = ERROR_INVALID_DOCUMENT;
        return;
      }
      const rows = [];
      for (const condition of parsed.conditions) {
        // One condition at a time, so a parent object two conditions share is described once.
        // eslint-disable-next-line no-await-in-loop
        rows.push(await this.rowFromCondition(objectApiName, condition));
      }
      this.rows = rows;
      this.logicText = parsed.logic;
      this.logicEnabled = !!parsed.logic;
    } catch (failure) {
      this.loadError = this.messageFrom(failure);
    } finally {
      this.loading = false;
    }
  }

  async rowFromCondition(objectApiName, condition) {
    const row = this.newRow();
    row.rawField = condition.field;
    row.rawOperator = condition.operator;
    row.rawValue = condition.value;
    const names = condition.field ? condition.field.split('.') : [];
    if (names.length === 0 || names.length - 1 > Math.min(Number(this.parentDepth) || 0, 2)) {
      return { ...row, unavailable: true };
    }
    const segments = [];
    // Objects are keyed by the name they were asked for, so a namespaced describe name never
    // splits one object into two cache entries.
    let currentObject = objectApiName;
    let info = this.infoByObject.get(currentObject);
    for (let index = 0; index < names.length; index++) {
      const name = names[index].toLowerCase();
      if (index < names.length - 1) {
        const lookup = info.fields.find(
          (field) =>
            field.referenceTo &&
            field.relationshipName &&
            field.relationshipName.toLowerCase() === name
        );
        if (!lookup) {
          return { ...row, unavailable: true };
        }
        segments.push({
          objectApiName: currentObject,
          selection: PARENT_PREFIX + lookup.relationshipName
        });
        try {
          currentObject = lookup.referenceTo;
          // Each step of a path needs the object the previous step reached.
          // eslint-disable-next-line no-await-in-loop
          info = await this.loadInfo(currentObject);
        } catch {
          return { ...row, unavailable: true };
        }
      } else {
        const field = info.fields.find(
          (candidate) => candidate.apiName.toLowerCase() === name && isFilterableField(candidate)
        );
        if (!field) {
          return { ...row, unavailable: true };
        }
        segments.push({ objectApiName: currentObject, selection: FIELD_PREFIX + field.apiName });
      }
    }
    const built = { ...row, segments, operator: condition.operator };
    const kind = valueKindFor(this.leafField(built), condition.operator);
    return { ...built, inputValue: toInputValue(kind, condition.value) };
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return error && error.message ? error.message : String(error);
  }
}
