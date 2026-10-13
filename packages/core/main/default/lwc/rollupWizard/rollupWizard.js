import { LightningElement, api } from 'lwc';
import getTargetFields from '@salesforce/apex/RollupBuilderController.getTargetFields';
import getSources from '@salesforce/apex/RollupBuilderController.getSources';
import getSourceFields from '@salesforce/apex/RollupBuilderController.getSourceFields';
import save from '@salesforce/apex/RollupBuilderController.save';
import preview from '@salesforce/apex/RollupBuilderController.preview';

import STEP_1 from '@salesforce/label/c.Core_RollupBuilder_Step1';
import STEP_2 from '@salesforce/label/c.Core_RollupBuilder_Step2';
import STEP_3 from '@salesforce/label/c.Core_RollupBuilder_Step3';
import STEP_4 from '@salesforce/label/c.Core_RollupBuilder_Step4';
import STEP_5 from '@salesforce/label/c.Core_RollupBuilder_Step5';
import TARGET_OBJECT from '@salesforce/label/c.Core_RollupBuilder_TargetObject';
import TARGET_FIELD from '@salesforce/label/c.Core_RollupBuilder_TargetField';
import TARGET_FIELD_HELP from '@salesforce/label/c.Core_RollupBuilder_TargetFieldHelp';
import FILLED_BY from '@salesforce/label/c.Core_RollupBuilder_FilledBy';
import SOURCE from '@salesforce/label/c.Core_RollupBuilder_Source';
import AGGREGATE from '@salesforce/label/c.Core_RollupBuilder_Aggregate';
import SOURCE_FIELD from '@salesforce/label/c.Core_RollupBuilder_SourceField';
import ORDER_BY from '@salesforce/label/c.Core_RollupBuilder_OrderBy';
import DELIMITER from '@salesforce/label/c.Core_RollupBuilder_Delimiter';
import WINDOW from '@salesforce/label/c.Core_RollupBuilder_Window';
import WINDOW_ALL from '@salesforce/label/c.Core_RollupBuilder_WindowAll';
import WINDOW_THIS from '@salesforce/label/c.Core_RollupBuilder_WindowThisYear';
import WINDOW_LAST from '@salesforce/label/c.Core_RollupBuilder_WindowLastYear';
import WINDOW_TWO from '@salesforce/label/c.Core_RollupBuilder_WindowTwoYears';
import WINDOW_DATE from '@salesforce/label/c.Core_RollupBuilder_WindowDate';
import CURRENCY_WARNING from '@salesforce/label/c.Core_RollupBuilder_CurrencyWarning';
import NUMBER_WARNING from '@salesforce/label/c.Core_RollupBuilder_NumberWarning';
import FILTER from '@salesforce/label/c.Core_RollupBuilder_Filter';
import TARGET_FILTER from '@salesforce/label/c.Core_RollupBuilder_TargetFilter';
import NAME from '@salesforce/label/c.Core_RollupBuilder_Name';
import DESCRIPTION from '@salesforce/label/c.Core_RollupBuilder_Description';
import MODE from '@salesforce/label/c.Core_Rollups_ColumnMode';
import ACTIVE from '@salesforce/label/c.Core_Rollups_ColumnActive';
import SUMMARY from '@salesforce/label/c.Core_RollupBuilder_Summary';
import BACK from '@salesforce/label/c.Core_RollupBuilder_Back';
import NEXT from '@salesforce/label/c.Core_RollupBuilder_Next';
import CANCEL from '@salesforce/label/c.Core_RollupBuilder_Cancel';
import SAVE from '@salesforce/label/c.Core_RollupBuilder_Save';
import SAVE_AND_CALCULATE from '@salesforce/label/c.Core_RollupBuilder_SaveAndCalculate';
import ERROR_NAME from '@salesforce/label/c.Core_RollupBuilder_ErrorNameNeeded';
import ERROR_TARGET from '@salesforce/label/c.Core_RollupBuilder_ErrorTargetNeeded';
import ERROR_SOURCE from '@salesforce/label/c.Core_RollupBuilder_ErrorSourceNeeded';
import ERROR_SOURCE_FIELD from '@salesforce/label/c.Core_Rollups_ErrorSourceFieldNeeded';
import ERROR_ORDER_BY from '@salesforce/label/c.Core_RollupBuilder_ErrorOrderByNeeded';
import ERROR_WINDOW_DATE from '@salesforce/label/c.Core_RollupBuilder_ErrorWindowNeedsDate';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Rollups_UnexpectedError';
import PREVIEW_RECORD from '@salesforce/label/c.Core_RollupBuilder_PreviewRecord';

const NUMBERS = new Set(['double', 'integer', 'long']);
const MONEY = new Set(['currency', 'percent']);
const DATES = new Set(['date', 'datetime']);
const TEXT = new Set(['string', 'textarea']);
const READS_NO_FIELD = new Set(['COUNT', 'ANY', 'NONE']);
const ORDERED = new Set(['FIRST', 'LAST']);
const LISTS = new Set(['TEXT_LIST', 'TEXT_LIST_DISTINCT']);

/** The calculations a target field of this type can hold (canonical model R-R15). */
function aggregatesFor(type) {
  if (type === 'boolean') {
    return ['ANY', 'NONE'];
  }
  if (TEXT.has(type)) {
    return ['FIRST', 'LAST', 'TEXT_LIST', 'TEXT_LIST_DISTINCT'];
  }
  if (DATES.has(type)) {
    return ['MIN', 'MAX', 'FIRST', 'LAST'];
  }
  const numeric = ['SUM', 'COUNT', 'MIN', 'MAX', 'AVG', 'FIRST', 'LAST'];
  return NUMBERS.has(type) ? [...numeric, 'COUNT_DISTINCT'] : numeric;
}

function format(label, ...values) {
  return values.reduce((text, value, index) => text.replace(`{${index}}`, value), label);
}

/**
 * The five steps of the Rollup Builder (rollup proposal Part 2 section 3, slice S11). Every
 * choice comes from the org's describe through `RollupBuilderController`, and the save runs the
 * whole check of canonical model R-R10 and R-R8 on the server. `Next` checks only what the step
 * itself needs, so the administrator learns what is missing where she can fix it.
 *
 * Fires `saved` with `detail.notice` after a save, and `cancel`.
 */
export default class RollupWizard extends LightningElement {
  /** What `RollupBuilderController.getModel` answered. */
  @api model;

  labels = {
    targetObject: TARGET_OBJECT,
    targetField: TARGET_FIELD,
    targetFieldHelp: TARGET_FIELD_HELP,
    source: SOURCE,
    aggregate: AGGREGATE,
    sourceField: SOURCE_FIELD,
    orderBy: ORDER_BY,
    delimiter: DELIMITER,
    window: WINDOW,
    windowDate: WINDOW_DATE,
    filter: FILTER,
    targetFilter: TARGET_FILTER,
    name: NAME,
    description: DESCRIPTION,
    mode: MODE,
    active: ACTIVE,
    back: BACK,
    next: NEXT,
    cancel: CANCEL,
    save: SAVE,
    saveAndCalculate: SAVE_AND_CALCULATE,
    previewRecord: PREVIEW_RECORD
  };

  step = 1;
  current = { active: true, fiscalYearAware: false };
  targetFields = [];
  sources = [];
  sourceFields = [];
  targetEntityFields = [];
  error;
  busy = false;
  /** Step 5: how many records the rollup maintains, and its total on a picked record (S12). */
  maintains;
  previewResult;
  previewRecordId;

  /** The rollup to edit or copy, or nothing for a new one. */
  @api
  get draft() {
    return this.current;
  }
  set draft(value) {
    this.current = { active: true, fiscalYearAware: false, ...(value || {}) };
    this.step = 1;
    this.error = undefined;
    this.previewRecordId = undefined;
    this.loadTarget();
  }

  connectedCallback() {
    if (!this.current.mode && this.model) {
      this.current = { ...this.current, mode: this.model.defaultMode };
    }
  }

  // ------------------------------------------------------------------------------- the steps

  get steps() {
    return [STEP_1, STEP_2, STEP_3, STEP_4, STEP_5].map((label, index) => ({
      label,
      value: String(index + 1)
    }));
  }

  get stepValue() {
    return String(this.step);
  }

  get stepTitle() {
    return this.steps[this.step - 1].label;
  }

  get isStep1() {
    return this.step === 1;
  }
  get isStep2() {
    return this.step === 2;
  }
  get isStep3() {
    return this.step === 3;
  }
  get isStep4() {
    return this.step === 4;
  }
  get isStep5() {
    return this.step === 5;
  }
  get showBack() {
    return this.step > 1;
  }

  // ------------------------------------------------------------------------------- options

  get targetOptions() {
    return this.model ? this.model.targets : [];
  }

  get targetFieldOptions() {
    return this.targetFields.map((field) => ({
      value: field.value,
      label: field.filledBy ? format(FILLED_BY, field.label, field.filledBy) : field.label
    }));
  }

  get sourceOptions() {
    const options = this.sources.map((source) => ({ value: source.value, label: source.label }));
    const chosen = this.sourceValue;
    if (chosen && !options.some((option) => option.value === chosen)) {
      // A shipped rollup's path, such as two alternatives, that the Builder does not offer.
      options.push({ value: chosen, label: this.current.relationshipPath });
    }
    return options;
  }

  get sourceValue() {
    return this.current.sourceObject && this.current.relationshipPath
      ? `${this.current.sourceObject}|${this.current.relationshipPath}`
      : undefined;
  }

  get targetFieldType() {
    const field = this.targetFields.find((entry) => entry.value === this.current.targetField);
    return field ? field.type : '';
  }

  get aggregateOptions() {
    const allowed = new Set(aggregatesFor(this.targetFieldType));
    return (this.model ? this.model.aggregates : []).filter((option) => allowed.has(option.value));
  }

  get needsSourceField() {
    return !!this.current.aggregate && !READS_NO_FIELD.has(this.current.aggregate);
  }

  get needsOrderBy() {
    return ORDERED.has(this.current.aggregate) || LISTS.has(this.current.aggregate);
  }

  get isTextList() {
    return LISTS.has(this.current.aggregate);
  }

  get sourceFieldOptions() {
    return this.sourceFields.map((field) => ({ value: field.value, label: field.label }));
  }

  get dateFieldOptions() {
    return this.sourceFields
      .filter((field) => DATES.has(field.type))
      .map((field) => ({ value: field.value, label: field.label }));
  }

  get delimiterOptions() {
    return this.model ? this.model.delimiters : [];
  }

  get modeOptions() {
    return this.model ? this.model.modes : [];
  }

  get windowOptions() {
    return [
      { value: 'all', label: WINDOW_ALL },
      { value: '0', label: WINDOW_THIS },
      { value: '-1', label: WINDOW_LAST },
      { value: '-2', label: WINDOW_TWO }
    ];
  }

  get windowValue() {
    return this.current.fiscalYearAware ? String(this.current.fiscalYearOffset) : 'all';
  }

  get hasWindow() {
    return this.current.fiscalYearAware === true;
  }

  get recordsLabel() {
    const source = this.sources.find((entry) => entry.value === this.sourceValue);
    return source ? source.recordsLabel : this.current.sourceObject;
  }

  get targetLabel() {
    const target = this.targetOptions.find((entry) => entry.value === this.current.targetObject);
    return target ? target.label : this.current.targetObject;
  }

  /** R-R15 and the multi-currency ADR: a money total in an org with several currencies. */
  get currencyWarning() {
    if (!this.model || !this.model.multiCurrency) {
      return undefined;
    }
    const source = this.sourceFields.find((field) => field.value === this.current.sourceField);
    if (!source || source.type !== 'currency' || this.current.aggregate === 'COUNT') {
      return undefined;
    }
    if (this.targetFieldType === 'currency') {
      return CURRENCY_WARNING;
    }
    return NUMBERS.has(this.targetFieldType) || MONEY.has(this.targetFieldType)
      ? NUMBER_WARNING
      : undefined;
  }

  /** The whole rollup in one sentence. */
  get summary() {
    const aggregate = (this.model ? this.model.aggregates : []).find(
      (option) => option.value === this.current.aggregate
    );
    const sourceField = this.sourceFields.find((field) => field.value === this.current.sourceField);
    const targetField = this.targetFields.find((field) => field.value === this.current.targetField);
    const source = this.sources.find((entry) => entry.value === this.sourceValue);
    const calculation = aggregate ? aggregate.label : this.current.aggregate;
    return format(
      SUMMARY,
      sourceField ? `${calculation} (${sourceField.label})` : calculation,
      source ? source.label : this.current.relationshipPath,
      `${this.targetLabel}, ${targetField ? targetField.label : this.current.targetField}`
    );
  }

  get hasError() {
    return !!this.error;
  }

  // ---------------------------------------------------------------------------- loading

  loadTarget() {
    const target = this.current.targetObject;
    if (!target) {
      return Promise.resolve();
    }
    return Promise.all([
      getTargetFields({ targetObject: target }),
      getSources({ targetObject: target }),
      getSourceFields({ sourceObject: target })
    ])
      .then(([fields, sources, entityFields]) => {
        this.targetFields = fields || [];
        this.sources = sources || [];
        this.targetEntityFields = entityFields || [];
        return this.loadSource();
      })
      .catch((error) => this.fail(error));
  }

  loadSource() {
    if (!this.current.sourceObject) {
      this.sourceFields = [];
      return Promise.resolve();
    }
    return getSourceFields({ sourceObject: this.current.sourceObject })
      .then((fields) => {
        this.sourceFields = fields || [];
      })
      .catch((error) => this.fail(error));
  }

  // ---------------------------------------------------------------------------- changes

  change(changes) {
    this.current = { ...this.current, ...changes };
    this.error = undefined;
  }

  handleTargetObject(event) {
    this.change({
      targetObject: event.detail.value,
      targetField: undefined,
      sourceObject: undefined,
      relationshipPath: undefined,
      targetFilterJson: undefined
    });
    this.loadTarget();
  }

  handleSource(event) {
    const source = this.sources.find((entry) => entry.value === event.detail.value);
    if (!source) {
      return;
    }
    this.change({
      sourceObject: source.sourceObject,
      relationshipPath: source.relationshipPath,
      sourceField: undefined,
      orderByField: undefined,
      fiscalDateField: undefined,
      filterJson: undefined
    });
    this.loadSource();
  }

  handleWindow(event) {
    const value = event.detail.value;
    this.change(
      value === 'all'
        ? { fiscalYearAware: false, fiscalYearOffset: undefined }
        : { fiscalYearAware: true, fiscalYearOffset: Number(value) }
    );
  }

  /** One handler for every plain input: the element's `name` is the draft attribute. */
  handleInput(event) {
    const name = event.target.name;
    const value =
      event.target.type === 'toggle' || event.target.type === 'checkbox'
        ? event.target.checked
        : event.detail.value;
    this.change({ [name]: value });
  }

  handleFilter(event) {
    this.change({ [event.target.dataset.name]: event.detail.value });
  }

  // ------------------------------------------------------------------------- moving on

  /** What the step on screen still needs, or null. */
  stepProblem() {
    const draft = this.current;
    if (this.step === 1 && (!draft.targetObject || !draft.targetField)) {
      return ERROR_TARGET;
    }
    if (this.step === 2 && !this.sourceValue) {
      return ERROR_SOURCE;
    }
    if (this.step === 3) {
      if (!draft.aggregate || (this.needsSourceField && !draft.sourceField)) {
        return ERROR_SOURCE_FIELD;
      }
      if (ORDERED.has(draft.aggregate) && !draft.orderByField) {
        return ERROR_ORDER_BY;
      }
      if (draft.fiscalYearAware && !draft.fiscalDateField && !this.sourceIsDate()) {
        return ERROR_WINDOW_DATE;
      }
    }
    if (this.step === 4) {
      for (const builder of this.template.querySelectorAll('c-rollup-filter-builder')) {
        const problem = builder.validate();
        if (problem) {
          return problem;
        }
      }
    }
    if (this.step === 5 && !(draft.name || '').trim()) {
      return ERROR_NAME;
    }
    return null;
  }

  sourceIsDate() {
    const field = this.sourceFields.find((entry) => entry.value === this.current.sourceField);
    return !!field && DATES.has(field.type);
  }

  handleNext() {
    this.error = this.stepProblem();
    if (!this.error) {
      this.step = Math.min(5, this.step + 1);
      if (this.step === 5) {
        this.loadPreview();
      }
    }
  }

  handlePreviewRecord(event) {
    this.previewRecordId = event.detail.recordId;
    this.loadPreview();
  }

  /** Calculates the unsaved rollup on the picked record and counts what it maintains. */
  loadPreview() {
    this.maintains = undefined;
    this.previewResult = undefined;
    preview({ draft: this.payload(), recordId: this.previewRecordId || null })
      .then((result) => {
        this.maintains = result.maintains;
        this.previewResult = result.result;
      })
      .catch((error) => this.fail(error));
  }

  /** The draft as the server reads it. */
  payload() {
    const draft = { ...this.current };
    if (READS_NO_FIELD.has(draft.aggregate)) {
      draft.sourceField = null;
    }
    return draft;
  }

  handleBack() {
    this.error = undefined;
    this.step = Math.max(1, this.step - 1);
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent('cancel'));
  }

  handleSave(event) {
    this.error = this.stepProblem();
    if (this.error) {
      return;
    }
    const calculateNow = event.target.dataset.id === 'save-and-calculate';
    this.busy = true;
    save({ draft: this.payload(), calculateNow })
      .then((result) => {
        this.dispatchEvent(
          new CustomEvent('saved', { detail: { notice: result.notice, recordId: result.recordId } })
        );
      })
      .catch((error) => this.fail(error))
      .finally(() => {
        this.busy = false;
      });
  }

  fail(error) {
    this.error = error && error.body && error.body.message ? error.body.message : UNEXPECTED_ERROR;
  }
}
