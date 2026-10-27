import { LightningElement, api } from 'lwc';
import getTargetFields from '@salesforce/apex/RollupBuilderController.getTargetFields';
import getSources from '@salesforce/apex/RollupBuilderController.getSources';
import getSourceFields from '@salesforce/apex/RollupBuilderController.getSourceFields';
import getParentFields from '@salesforce/apex/RollupBuilderController.getParentFields';
import save from '@salesforce/apex/RollupBuilderController.save';
import preview from '@salesforce/apex/RollupBuilderController.preview';
import previewSamples from '@salesforce/apex/RollupBuilderController.previewSamples';

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
import ORDER_DIRECTION from '@salesforce/label/c.Core_RollupBuilder_OrderDirection';
import ROW_LIMIT from '@salesforce/label/c.Core_RollupBuilder_RowLimit';
import ROW_LIMIT_HELP from '@salesforce/label/c.Core_RollupBuilder_RowLimitHelp';
import ERROR_ROW_LIMIT_ORDER from '@salesforce/label/c.Core_Rollups_ErrorRowLimitNeedsOrder';
import DELIMITER from '@salesforce/label/c.Core_RollupBuilder_Delimiter';
import CUSTOM_DELIMITER from '@salesforce/label/c.Core_RollupBuilder_CustomDelimiter';
import ERROR_CUSTOM_DELIMITER from '@salesforce/label/c.Core_Rollups_ErrorCustomDelimiterNeeded';
import INCLUDE_DELETED from '@salesforce/label/c.Core_RollupBuilder_IncludeDeleted';
import INCLUDE_DELETED_HELP from '@salesforce/label/c.Core_RollupBuilder_IncludeDeletedHelp';
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
import PARENT_FIELD_NOTE from '@salesforce/label/c.Core_RollupBuilder_ParentFieldNote';
import NAME from '@salesforce/label/c.Core_RollupBuilder_Name';
import DESCRIPTION from '@salesforce/label/c.Core_RollupBuilder_Description';
import BYPASS_PERMISSION from '@salesforce/label/c.Core_RollupBuilder_BypassPermission';
import BYPASS_PERMISSION_HELP from '@salesforce/label/c.Core_RollupBuilder_BypassPermissionHelp';
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
import TARGET_SEARCH from '@salesforce/label/c.Core_RollupBuilder_TargetSearch';
import TARGET_SEARCH_HELP from '@salesforce/label/c.Core_RollupBuilder_TargetSearchHelp';
import NO_INSTANT from '@salesforce/label/c.Core_RollupBuilder_NoInstant';
import BUILDER_SENTENCE from '@salesforce/label/c.Core_RollupEase_BuilderSentence';
import SENTENCE_HELP from '@salesforce/label/c.Core_RollupEase_SentenceHelp';
import NOT_CHOSEN from '@salesforce/label/c.Core_RollupEase_NotChosen';
import EVERY_RECORD from '@salesforce/label/c.Core_RollupEase_EveryRecord';
import SOME_RECORDS from '@salesforce/label/c.Core_RollupEase_SomeRecords';
import TARGET_PART from '@salesforce/label/c.Core_RollupEase_TargetPart';
import NOT_FOR_FIELD from '@salesforce/label/c.Core_RollupEase_NotForField';
import FIELDS_NUMBERS from '@salesforce/label/c.Core_RollupEase_FieldsNumbers';
import FIELDS_NUMBERS_DATES from '@salesforce/label/c.Core_RollupEase_FieldsNumbersDates';
import NO_FIELD_FITS from '@salesforce/label/c.Core_RollupEase_NoFieldFits';
import MODE_HEADING from '@salesforce/label/c.Core_RollupEase_ModeHeading';
import MODE_INSTANT_AFTER from '@salesforce/label/c.Core_RollupEase_ModeInstantAfter';
import MODE_INSTANT_DURING from '@salesforce/label/c.Core_RollupEase_ModeInstantDuring';
import MODE_INSTANT_NONE from '@salesforce/label/c.Core_RollupEase_ModeInstantNone';
import MODE_NIGHTLY from '@salesforce/label/c.Core_RollupEase_ModeNightly';
import MODE_BOTH_TEXT from '@salesforce/label/c.Core_RollupEase_ModeBoth';
import MODE_BOTH_NO_INSTANT from '@salesforce/label/c.Core_RollupEase_ModeBothNoInstant';
import PICK_SAMPLES from '@salesforce/label/c.Core_RollupEase_PickSamples';
import PICK_SAMPLES_HELP from '@salesforce/label/c.Core_RollupEase_PickSamplesHelp';
import SAMPLES_HEADING from '@salesforce/label/c.Core_RollupEase_SamplesHeading';
import SAMPLES_NONE from '@salesforce/label/c.Core_RollupEase_SamplesNone';
import SHOW_ROWS from '@salesforce/label/c.Core_RollupEase_ShowRows';
import ROWS_HEADING from '@salesforce/label/c.Core_RollupEase_RowsHeading';

/** The stored modes (canonical model R-R4): Instantly alone, and Both. */
const MODE_REAL_TIME = 'Real-time';
const MODE_BOTH = 'Both';

const NUMBERS = new Set(['double', 'integer', 'long']);
const MONEY = new Set(['currency', 'percent']);
const DATES = new Set(['date', 'datetime']);
/** A fiscal year window is bounded by dates, so it is measured on a date field only. */
const FISCAL_DATES = new Set(['date']);
const TEXT = new Set(['string', 'textarea']);
const READS_NO_FIELD = new Set(['COUNT', 'ANY', 'NONE']);
const ORDERED = new Set(['FIRST', 'LAST']);
const LISTS = new Set(['TEXT_LIST', 'TEXT_LIST_DISTINCT']);
/** What a picklist target can be filled from (R-R15). */
const INTO_PICKLIST = new Set(['picklist', 'string']);
/** The calculations that take "only the first N records" (R-R15, ADR-0136). */
const ROW_LIMITED = new Set(['SUM', 'AVG', 'MIN', 'MAX', ...LISTS]);
/** Sum and Average read numbers; Minimum and Maximum numbers or dates (R-R10, U9). */
const READS_NUMBERS = new Set(['SUM', 'AVG']);
const READS_NUMBERS_OR_DATES = new Set(['MIN', 'MAX']);

/** Whether a field of this type can feed this calculation, as the save checks it (U9). */
function fitsCalculation(aggregate, type) {
  if (READS_NUMBERS.has(aggregate)) {
    return NUMBERS.has(type) || MONEY.has(type);
  }
  if (READS_NUMBERS_OR_DATES.has(aggregate)) {
    return NUMBERS.has(type) || MONEY.has(type) || DATES.has(type);
  }
  return true;
}

/** The calculations a target field of this type can hold (canonical model R-R15). */
function aggregatesFor(type) {
  if (type === 'boolean') {
    return ['ANY', 'NONE'];
  }
  if (type === 'picklist') {
    return ['FIRST', 'LAST'];
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
    orderDirection: ORDER_DIRECTION,
    rowLimit: ROW_LIMIT,
    rowLimitHelp: ROW_LIMIT_HELP,
    delimiter: DELIMITER,
    customDelimiter: CUSTOM_DELIMITER,
    includeDeleted: INCLUDE_DELETED,
    includeDeletedHelp: INCLUDE_DELETED_HELP,
    window: WINDOW,
    windowDate: WINDOW_DATE,
    filter: FILTER,
    targetFilter: TARGET_FILTER,
    parentFieldNote: PARENT_FIELD_NOTE,
    name: NAME,
    description: DESCRIPTION,
    bypassPermission: BYPASS_PERMISSION,
    bypassPermissionHelp: BYPASS_PERMISSION_HELP,
    mode: MODE,
    active: ACTIVE,
    back: BACK,
    next: NEXT,
    cancel: CANCEL,
    save: SAVE,
    saveAndCalculate: SAVE_AND_CALCULATE,
    previewRecord: PREVIEW_RECORD,
    targetSearch: TARGET_SEARCH,
    targetSearchHelp: TARGET_SEARCH_HELP,
    sentenceHelp: SENTENCE_HELP,
    modeHeading: MODE_HEADING,
    pickSamples: PICK_SAMPLES,
    pickSamplesHelp: PICK_SAMPLES_HELP,
    samplesHeading: SAMPLES_HEADING,
    samplesNone: SAMPLES_NONE,
    showRows: SHOW_ROWS,
    rowsHeading: ROWS_HEADING
  };

  /** The furthest step reached, so the sentence jumps back to any step already filled (U3). */
  furthest = 1;

  /** Step 1: what the administrator typed to find an object off the common list (ADR-0136). */
  targetSearch = '';

  step = 1;
  current = { active: true, fiscalYearAware: false };
  targetFields = [];
  sources = [];
  sourceFields = [];
  /** Fields of the records the counted records point to, for the filter (ADR-0136). */
  parentFields = [];
  targetEntityFields = [];
  error;
  busy = false;
  /** Step 5: how many records the rollup maintains, and its total on a picked record (S12). */
  maintains;
  previewResult;
  previewRecordId;
  /** Step 5: records the rollup would fill, picked for her, and the records read (U4). */
  samples;
  previewRows;

  /** The rollup to edit or copy, or nothing for a new one. */
  @api
  get draft() {
    return this.current;
  }
  set draft(value) {
    this.current = { active: true, fiscalYearAware: false, ...(value || {}) };
    this.step = 1;
    // An edited or copied rollup has every step filled in, so any part of it can be opened.
    this.furthest = value && value.targetObject ? 5 : 1;
    this.error = undefined;
    this.previewRecordId = undefined;
    this.samples = undefined;
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
  /** Step 5: the counted object, whose instant totals state is shown (ADR-0138). */
  get instantObject() {
    return this.current.sourceObject;
  }
  get canManageInstant() {
    return Boolean(this.model && this.model.canManage);
  }
  get showBack() {
    return this.step > 1;
  }

  // ------------------------------------------------------------------------------- options

  get allTargets() {
    return this.model && this.model.targets ? this.model.targets : [];
  }

  /**
   * The common objects, or every object whose name or API name holds what was typed, and the
   * chosen one always, so an edited rollup on another object still shows it (ADR-0136).
   */
  get targetOptions() {
    const term = (this.targetSearch || '').trim().toLowerCase();
    const matches = (option) => {
      if (!term) {
        return option.common !== false;
      }
      return option.label.toLowerCase().includes(term) || option.value.toLowerCase().includes(term);
    };
    const shown = this.allTargets
      .filter(matches)
      .map((option) => ({ value: option.value, label: option.label }));
    const chosen = this.current.targetObject;
    if (chosen && !shown.some((option) => option.value === chosen)) {
      const found = this.allTargets.find((option) => option.value === chosen);
      shown.unshift({ value: chosen, label: found ? found.label : chosen });
    }
    return shown;
  }

  handleTargetSearch(event) {
    this.targetSearch = event.detail.value;
  }

  get chosenSource() {
    return this.sources.find((entry) => entry.value === this.sourceValue);
  }

  /** False when the counted records have no rollup trigger (R-R12); unknown counts as instant. */
  get sourceIsInstant() {
    const source = this.chosenSource;
    return !source || source.instant !== false;
  }

  /** Step 5: says plainly that this total is not instant, and why (ADR-0136). */
  get noInstantNotice() {
    return this.sourceIsInstant ? undefined : format(NO_INSTANT, this.recordsLabel);
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
    return (
      ORDERED.has(this.current.aggregate) || LISTS.has(this.current.aggregate) || this.hasRowLimit
    );
  }

  get takesRowLimit() {
    return ROW_LIMITED.has(this.current.aggregate);
  }

  get hasRowLimit() {
    return this.takesRowLimit && this.current.rowLimit != null && this.current.rowLimit !== '';
  }

  /** First is always the lowest and Last the highest, so only lists and limits take a direction. */
  get takesDirection() {
    return LISTS.has(this.current.aggregate) || this.hasRowLimit;
  }

  get orderDirection() {
    return this.current.orderDirection || 'Ascending';
  }

  get directionOptions() {
    return this.model && this.model.directions ? this.model.directions : [];
  }

  get isTextList() {
    return LISTS.has(this.current.aggregate);
  }

  get isCustomDelimiter() {
    return this.isTextList && this.current.delimiter === 'Custom';
  }

  get sourceFieldOptions() {
    return this.sourceFields.map((field) => ({ value: field.value, label: field.label }));
  }

  /**
   * The fields a value can be read from: a picklist only from a picklist or text, and only fields
   * the calculation can read, so the save never has to refuse the pair (U9).
   */
  get copyFieldOptions() {
    return this.sourceFields
      .filter((field) => this.targetFieldType !== 'picklist' || INTO_PICKLIST.has(field.type))
      .filter((field) => fitsCalculation(this.current.aggregate, field.type))
      .map((field) => ({ value: field.value, label: field.label }));
  }

  get chosenAggregateLabel() {
    const option = (this.model ? this.model.aggregates : []).find(
      (entry) => entry.value === this.current.aggregate
    );
    return option ? option.label : this.current.aggregate;
  }

  get targetFieldLabel() {
    const field = this.targetFields.find((entry) => entry.value === this.current.targetField);
    return field ? field.label : this.current.targetField;
  }

  /** Step 3: the calculations this field cannot hold, and what to do instead (U9). */
  get unavailableNotice() {
    if (!this.model || !this.targetFieldType) {
      return undefined;
    }
    const allowed = new Set(aggregatesFor(this.targetFieldType));
    const hidden = this.model.aggregates
      .filter((option) => !allowed.has(option.value))
      .map((option) => option.label);
    return hidden.length
      ? format(NOT_FOR_FIELD, this.targetFieldLabel, hidden.join(', '))
      : undefined;
  }

  /** Step 3: why only some fields are listed, or that none fits (U9). */
  get fieldGuidance() {
    if (!this.needsSourceField) {
      return undefined;
    }
    if (this.sourceFields.length && !this.copyFieldOptions.length) {
      return format(NO_FIELD_FITS, this.chosenAggregateLabel);
    }
    if (READS_NUMBERS.has(this.current.aggregate)) {
      return format(FIELDS_NUMBERS, this.chosenAggregateLabel);
    }
    if (READS_NUMBERS_OR_DATES.has(this.current.aggregate)) {
      return format(FIELDS_NUMBERS_DATES, this.chosenAggregateLabel);
    }
    return undefined;
  }

  // ------------------------------------------------------------------ the sentence (U3)

  /** How many conditions the counted records must meet, in words. */
  get conditionsText() {
    try {
      const document = this.current.filterJson ? JSON.parse(this.current.filterJson) : null;
      const count = document && Array.isArray(document.conditions) ? document.conditions.length : 0;
      return count ? format(SOME_RECORDS, count) : EVERY_RECORD;
    } catch {
      return EVERY_RECORD;
    }
  }

  /** Each part of the sentence, by the step that sets it. */
  get sentenceValues() {
    const draft = this.current;
    const source = this.chosenSource;
    const field = this.sourceFields.find((entry) => entry.value === draft.sourceField);
    let calculation;
    if (draft.aggregate) {
      calculation = field
        ? `${this.chosenAggregateLabel} (${field.label})`
        : this.chosenAggregateLabel;
    }
    const mode = (this.model ? this.model.modes : []).find((entry) => entry.value === draft.mode);
    return [
      { step: 3, text: calculation },
      { step: 2, text: source ? source.label : draft.relationshipPath },
      { step: 4, text: this.furthest >= 4 ? this.conditionsText : undefined },
      {
        step: 1,
        text: draft.targetField
          ? format(TARGET_PART, this.targetLabel, this.targetFieldLabel)
          : undefined
      },
      { step: 5, text: this.furthest >= 5 && mode ? mode.label : undefined }
    ];
  }

  /**
   * The whole rollup as one sentence, built as the steps are filled in. Each chosen part is a
   * link to the step that sets it; a part not chosen yet says so (U3).
   */
  get sentenceParts() {
    const values = this.sentenceValues;
    return BUILDER_SENTENCE.split(/(\{\d\})/)
      .filter((piece) => piece !== '')
      .map((piece, index) => {
        const match = /^\{(\d)\}$/.exec(piece);
        if (!match) {
          return { key: `text-${index}`, text: piece, isText: true };
        }
        const part = values[Number(match[1])] || {};
        return {
          key: `part-${index}`,
          text: part.text || NOT_CHOSEN,
          step: String(part.step),
          isText: false,
          disabled: part.step > this.furthest
        };
      });
  }

  handleSentencePart(event) {
    const step = Number(event.target.dataset.step);
    if (step > this.furthest) {
      return;
    }
    this.error = undefined;
    this.step = step;
    if (step === 5) {
      this.samples = undefined;
      this.loadPreview();
    }
  }

  // ------------------------------------------------------------------- the modes (U10)

  /** What each mode means for this rollup: when its field changes (U10). */
  get modeConsequences() {
    const target = this.targetFieldLabel || '';
    const records = this.recordsLabel || '';
    const time = this.model && this.model.nightlyTime ? this.model.nightlyTime : '';
    let instantly;
    if (!this.sourceIsInstant) {
      instantly = format(MODE_INSTANT_NONE, records);
    } else {
      instantly = format(
        this.model && this.model.inSave ? MODE_INSTANT_DURING : MODE_INSTANT_AFTER,
        target,
        records
      );
    }
    return [
      { key: 'instantly', text: instantly },
      { key: 'nightly', text: format(MODE_NIGHTLY, target, time) },
      {
        key: 'both',
        text: this.sourceIsInstant
          ? format(MODE_BOTH_TEXT, time)
          : format(MODE_BOTH_NO_INSTANT, time, records)
      }
    ];
  }

  /** The source filter offers the counted records' own fields, then those one lookup away. */
  get filterFields() {
    return [...this.sourceFields, ...this.parentFields];
  }

  /** Whether the source filter reads a field of another record, which may not update at once. */
  get readsParentField() {
    try {
      const document = this.current.filterJson ? JSON.parse(this.current.filterJson) : null;
      const conditions = document && Array.isArray(document.conditions) ? document.conditions : [];
      return conditions.some((condition) => String(condition.field || '').includes('.'));
    } catch {
      return false;
    }
  }

  get dateFieldOptions() {
    return this.sourceFields
      .filter((field) => FISCAL_DATES.has(field.type))
      .map((field) => ({ value: field.value, label: field.label }));
  }

  get delimiterOptions() {
    return this.model ? this.model.delimiters : [];
  }

  /** Instantly alone is not offered for records with no rollup trigger. */
  get modeOptions() {
    const modes = this.model ? this.model.modes : [];
    return this.sourceIsInstant ? modes : modes.filter((mode) => mode.value !== MODE_REAL_TIME);
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
    const target = this.allTargets.find((entry) => entry.value === this.current.targetObject);
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
      this.parentFields = [];
      return Promise.resolve();
    }
    const sourceObject = this.current.sourceObject;
    return Promise.all([getSourceFields({ sourceObject }), getParentFields({ sourceObject })])
      .then(([fields, parentFields]) => {
        this.sourceFields = fields || [];
        this.parentFields = parentFields || [];
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
    // A new object clears what the later steps chose, so they are filled in again in order.
    this.furthest = 1;
    this.loadTarget();
  }

  handleSource(event) {
    const source = this.sources.find((entry) => entry.value === event.detail.value);
    if (!source) {
      return;
    }
    const changes = {
      sourceObject: source.sourceObject,
      relationshipPath: source.relationshipPath,
      sourceField: undefined,
      orderByField: undefined,
      fiscalDateField: undefined,
      filterJson: undefined
    };
    if (source.instant === false && this.current.mode === MODE_REAL_TIME) {
      changes.mode = MODE_BOTH;
    }
    this.change(changes);
    this.furthest = Math.min(this.furthest, 2);
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
    // A field the new calculation cannot read is cleared rather than refused on save (U9).
    if (name === 'aggregate' && this.current.sourceField) {
      const field = this.sourceFields.find((entry) => entry.value === this.current.sourceField);
      if (field && !fitsCalculation(value, field.type)) {
        this.change({ sourceField: undefined });
      }
    }
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
      if (this.hasRowLimit && !draft.orderByField) {
        return ERROR_ROW_LIMIT_ORDER;
      }
      if (this.isCustomDelimiter && !draft.customDelimiter) {
        return ERROR_CUSTOM_DELIMITER;
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
    return !!field && FISCAL_DATES.has(field.type);
  }

  handleNext() {
    this.error = this.stepProblem();
    if (!this.error) {
      this.step = Math.min(5, this.step + 1);
      this.furthest = Math.max(this.furthest, this.step);
      if (this.step === 5) {
        // Samples calculated before a change elsewhere would show old totals.
        this.samples = undefined;
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
    this.previewRows = undefined;
    preview({ draft: this.payload(), recordId: this.previewRecordId || null })
      .then((result) => {
        this.maintains = result.maintains;
        this.previewResult = result.result;
        this.previewRows = result.rows;
      })
      .catch((error) => this.fail(error));
  }

  /** Calculates the unsaved rollup on up to five records it would fill, picked for her (U4). */
  handlePickSamples() {
    this.samples = undefined;
    previewSamples({ draft: this.payload() })
      .then((result) => {
        this.samples = result || [];
      })
      .catch((error) => this.fail(error));
  }

  /** Previews one sample as if it were picked, listing the records read for it. */
  handleShowRows(event) {
    this.previewRecordId = event.currentTarget.dataset.recordId;
    this.loadPreview();
  }

  get hasSamples() {
    return Array.isArray(this.samples) && this.samples.length > 0;
  }

  get noSamples() {
    return Array.isArray(this.samples) && this.samples.length === 0;
  }

  /** The records read for the previewed record, each with a link and its outcome. */
  get rowList() {
    const rows = (this.previewRows && this.previewRows.rows) || [];
    return rows.map((row) => ({
      ...row,
      url: '/' + row.recordId,
      outcomeClass: row.counted ? 'slds-text-color_success' : 'slds-text-color_weak'
    }));
  }

  get hasRowDetail() {
    return Boolean(this.previewRows);
  }

  /** The draft as the server reads it. */
  payload() {
    const draft = { ...this.current };
    if (READS_NO_FIELD.has(draft.aggregate)) {
      draft.sourceField = null;
    }
    // A limit or a direction the calculation does not take is not saved with it.
    draft.rowLimit = this.hasRowLimit ? Number(draft.rowLimit) : null;
    draft.orderDirection = this.takesDirection ? this.orderDirection : 'Ascending';
    draft.customDelimiter = this.isCustomDelimiter ? draft.customDelimiter : null;
    draft.includeDeleted = draft.includeDeleted === true;
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
