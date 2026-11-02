import { LightningElement, api } from 'lwc';
import saveIndicator from '@salesforce/apex/LogicModelBuilderController.saveIndicator';
import savePeriod from '@salesforce/apex/LogicModelBuilderController.savePeriod';
import remove from '@salesforce/apex/LogicModelBuilderController.remove';
import getSourceQueries from '@salesforce/apex/LogicModelBuilderController.getSourceQueries';
import getSourceFields from '@salesforce/apex/LogicModelBuilderController.getSourceFields';
import saveSource from '@salesforce/apex/LogicModelBuilderController.saveSource';
import refreshResults from '@salesforce/apex/LogicModelBuilderController.refreshResults';

import { FUNCTIONS, SOURCES, isComputed, progress, sourceReady } from 'c/logicModelRules';
import { LABELS, format, messageFrom } from 'c/logicModelText';

const HIGHER = 'Higher';
const EMPTY_INDICATOR = Object.freeze({
  name: '',
  unit: '',
  betterWhen: HIGHER,
  baselineValue: null,
  baselineDate: null,
  description: ''
});
const EMPTY_PERIOD = Object.freeze({
  name: '',
  startDate: null,
  endDate: null,
  targetValue: null,
  resultValue: null,
  notes: ''
});

/** One line under an indicator's name: its unit, which way is better and its baseline. */
function summaryOf(indicator) {
  const parts = [];
  if (indicator.unit) {
    parts.push(format(LABELS.unitIs, indicator.unit));
  }
  parts.push(
    format(LABELS.betterWhenIs, indicator.betterWhen === 'Lower' ? LABELS.lower : LABELS.higher)
  );
  const baseline = indicator.baselineValue;
  if (baseline !== null && baseline !== undefined) {
    parts.push(
      indicator.baselineDate
        ? format(LABELS.baselineOn, baseline, indicator.baselineDate)
        : format(LABELS.baselineIs, baseline)
    );
  }
  return parts.join(' ');
}

const SOURCE_LABELS = Object.freeze({
  [SOURCES.MANUAL]: LABELS.sourceManual,
  [SOURCES.IMPORT]: LABELS.sourceImport,
  [SOURCES.COMPUTED]: LABELS.sourceComputed
});

/** Where the indicator's results come from, in one line (R-IN3). */
function sourceLineOf(indicator) {
  if (!isComputed(indicator)) {
    return format(LABELS.resultsAre, SOURCE_LABELS[indicator.source] || LABELS.sourceManual);
  }
  const definition = indicator.definition || {};
  const field = definition.fieldLabel || definition.field;
  const workedOut =
    definition.function === FUNCTIONS.SUM
      ? format(LABELS.sumOf, field)
      : definition.function === FUNCTIONS.UNIQUE
        ? format(LABELS.uniqueOf, field)
        : LABELS.countOf;
  return format(
    LABELS.computedFrom,
    indicator.queryName || LABELS.someQuery,
    workedOut,
    definition.dateLabel || definition.dateField
  );
}

/** When a computed indicator's results were last worked out. */
function runLineOf(indicator) {
  if (!indicator.computedAt) {
    return LABELS.notRunYet;
  }
  return format(LABELS.lastRun, new Date(indicator.computedAt).toLocaleString());
}

const EMPTY_SOURCE = Object.freeze({
  source: SOURCES.MANUAL,
  queryId: null,
  dateField: null,
  function: FUNCTIONS.COUNT,
  field: null
});

/**
 * The indicators of one output or outcome (L-02): unit, which way is better and a baseline, and
 * under each a target and a result per period with its progress. Saves hand the whole model back
 * in a `modelchange` event; a refusal goes up as `failure`.
 */
export default class LogicModelIndicators extends LightningElement {
  @api model;
  @api elementId;
  @api canEdit = false;
  @api canDelete = false;

  labels = LABELS;
  busy = false;
  /** The indicator being edited: 'new' for Add Indicator, an Id, or undefined. */
  indicatorFormId;
  indicatorDraft = { ...EMPTY_INDICATOR };
  /** The period being edited: 'new' with periodIndicatorId, an Id, or undefined. */
  periodFormId;
  periodIndicatorId;
  periodDraft = { ...EMPTY_PERIOD };
  confirmingId;
  /** The indicator whose source is being chosen (L-03), or undefined. */
  sourceFormId;
  sourceDraft = { ...EMPTY_SOURCE };
  /** Saved queries the person can open, loaded when the source form first opens. */
  queryOptions;
  /** The chosen query's fields: dateFields, numberFields, uniqueFields. */
  fieldChoices = { dateFields: [], numberFields: [], uniqueFields: [] };

  get canSetSource() {
    return !!(this.model && this.model.canSetSource);
  }

  get canRefresh() {
    return !!(this.model && this.model.canRefresh);
  }

  get sourceOptions() {
    return [
      { value: SOURCES.MANUAL, label: LABELS.sourceManual },
      { value: SOURCES.IMPORT, label: LABELS.sourceImport },
      { value: SOURCES.COMPUTED, label: LABELS.sourceComputed }
    ];
  }

  get functionOptions() {
    return [
      { value: FUNCTIONS.COUNT, label: LABELS.count },
      { value: FUNCTIONS.SUM, label: LABELS.sum },
      { value: FUNCTIONS.UNIQUE, label: LABELS.unique }
    ];
  }

  get sourceDraftComputed() {
    return this.sourceDraft.source === SOURCES.COMPUTED;
  }

  get hasQueryOptions() {
    return !!(this.queryOptions && this.queryOptions.length);
  }

  get dateFieldOptions() {
    return this.fieldChoices.dateFields;
  }

  get needsField() {
    return this.sourceDraft.function !== FUNCTIONS.COUNT;
  }

  get measuredFieldOptions() {
    return this.sourceDraft.function === FUNCTIONS.SUM
      ? this.fieldChoices.numberFields
      : this.fieldChoices.uniqueFields;
  }

  get noFieldChoices() {
    return !this.sourceDraft.queryId;
  }

  get sourceSaveDisabled() {
    return this.busy || !sourceReady(this.sourceDraft);
  }

  /** The period form's indicator is computed: its result is never typed (R-IN3). */
  get periodResultLocked() {
    const indicator = ((this.model && this.model.indicators) || []).find(
      (item) => item.id === this.periodIndicatorId
    );
    return isComputed(indicator);
  }

  get periodResultHelp() {
    return this.periodResultLocked ? LABELS.resultComputed : undefined;
  }

  get betterWhenOptions() {
    return [
      { value: HIGHER, label: LABELS.higher },
      { value: 'Lower', label: LABELS.lower }
    ];
  }

  get indicators() {
    return ((this.model && this.model.indicators) || [])
      .filter((indicator) => indicator.elementId === this.elementId)
      .map((indicator) => ({
        id: indicator.id,
        name: indicator.name,
        description: indicator.description,
        summary: summaryOf(indicator),
        sourceLine: sourceLineOf(indicator),
        computed: isComputed(indicator),
        runLine: isComputed(indicator) ? runLineOf(indicator) : '',
        status: isComputed(indicator) ? indicator.status : null,
        showRefresh: isComputed(indicator) && this.canRefresh,
        sourceFormOpen: this.sourceFormId === indicator.id,
        confirming: this.confirmingId === indicator.id,
        periodFormOpen: !!this.periodFormId && this.periodIndicatorId === indicator.id,
        hasPeriods: (indicator.periods || []).length > 0,
        periods: (indicator.periods || []).map((period) => {
          const state = progress(indicator, period);
          return {
            ...period,
            progressText:
              state.state === 'met'
                ? LABELS.met
                : state.state === 'partial'
                  ? format(LABELS.percent, state.percent)
                  : ''
          };
        })
      }));
  }

  get hasIndicators() {
    return this.indicators.length > 0;
  }

  get indicatorFormOpen() {
    return !!this.indicatorFormId;
  }

  get showAddIndicator() {
    return this.canEdit && !this.indicatorFormId;
  }

  get indicatorSaveDisabled() {
    return this.busy || !this.indicatorDraft.name || !String(this.indicatorDraft.name).trim();
  }

  get periodSaveDisabled() {
    const draft = this.periodDraft;
    return this.busy || !draft.name || !draft.startDate || !draft.endDate;
  }

  // ------------------------------------------------------------------------ indicators

  handleAddIndicator() {
    this.indicatorFormId = 'new';
    this.indicatorDraft = { ...EMPTY_INDICATOR };
  }

  handleEditIndicator(event) {
    const id = event.currentTarget.dataset.recordId;
    const indicator = this.model.indicators.find((item) => item.id === id);
    this.indicatorFormId = id;
    this.indicatorDraft = {
      name: indicator.name,
      unit: indicator.unit || '',
      betterWhen: indicator.betterWhen || HIGHER,
      baselineValue: indicator.baselineValue,
      baselineDate: indicator.baselineDate,
      description: indicator.description || ''
    };
  }

  handleIndicatorField(event) {
    this.indicatorDraft = {
      ...this.indicatorDraft,
      [event.target.dataset.field]: event.detail.value
    };
  }

  handleIndicatorCancel() {
    this.indicatorFormId = undefined;
  }

  handleIndicatorSave() {
    const indicator = { ...this.indicatorDraft };
    if (this.indicatorFormId === 'new') {
      indicator.elementId = this.elementId;
    } else {
      indicator.id = this.indicatorFormId;
    }
    return this.run(saveIndicator({ indicatorJson: JSON.stringify(indicator) }), () => {
      this.indicatorFormId = undefined;
    });
  }

  handleDeleteIndicator(event) {
    this.confirmingId = event.currentTarget.dataset.recordId;
  }

  handleDeleteCancel() {
    this.confirmingId = undefined;
  }

  handleDeleteConfirm() {
    return this.run(
      remove({ recordId: this.confirmingId }),
      () => {
        this.confirmingId = undefined;
      },
      LABELS.deleted
    );
  }

  // -------------------------------------------------------------------- sources (L-03)

  handleSource(event) {
    const id = event.currentTarget.dataset.recordId;
    const indicator = this.model.indicators.find((item) => item.id === id);
    const definition = indicator.definition || {};
    this.sourceFormId = id;
    this.sourceDraft = {
      source: indicator.source || SOURCES.MANUAL,
      queryId: indicator.queryId || null,
      dateField: definition.dateField || null,
      function: definition.function || FUNCTIONS.COUNT,
      field: definition.field || null
    };
    this.fieldChoices = { dateFields: [], numberFields: [], uniqueFields: [] };
    return Promise.all([this.loadQueries(), this.loadFields(this.sourceDraft.queryId)]);
  }

  loadQueries() {
    if (this.queryOptions) {
      return Promise.resolve();
    }
    return getSourceQueries()
      .then((options) => {
        this.queryOptions = options || [];
      })
      .catch((error) => {
        this.queryOptions = [];
        this.fail(error);
      });
  }

  loadFields(queryId) {
    if (!queryId) {
      return Promise.resolve();
    }
    return getSourceFields({ queryId })
      .then((choices) => {
        this.fieldChoices = {
          dateFields: (choices && choices.dateFields) || [],
          numberFields: (choices && choices.numberFields) || [],
          uniqueFields: (choices && choices.uniqueFields) || []
        };
      })
      .catch((error) => this.fail(error));
  }

  handleSourceField(event) {
    const field = event.target.dataset.field;
    const value = event.detail.value;
    const draft = { ...this.sourceDraft, [field]: value };
    if (field === 'queryId') {
      draft.dateField = null;
      draft.field = null;
      this.fieldChoices = { dateFields: [], numberFields: [], uniqueFields: [] };
      this.loadFields(value);
    }
    if (field === 'function') {
      draft.field = null;
    }
    this.sourceDraft = draft;
  }

  handleSourceCancel() {
    this.sourceFormId = undefined;
  }

  handleSourceSave() {
    const source = { ...this.sourceDraft, id: this.sourceFormId };
    return this.run(
      saveSource({ modelId: this.model.id, sourceJson: JSON.stringify(source) }),
      () => {
        this.sourceFormId = undefined;
      },
      source.source === SOURCES.COMPUTED ? LABELS.refreshing : LABELS.saved
    );
  }

  handleRefresh(event) {
    return this.run(
      refreshResults({
        modelId: this.model.id,
        indicatorId: event.currentTarget.dataset.recordId
      }),
      null,
      LABELS.refreshing
    );
  }

  fail(error) {
    this.dispatchEvent(new CustomEvent('failure', { detail: { message: messageFrom(error) } }));
  }

  // --------------------------------------------------------------------------- periods

  handleAddPeriod(event) {
    this.periodFormId = 'new';
    this.periodIndicatorId = event.currentTarget.dataset.recordId;
    this.periodDraft = { ...EMPTY_PERIOD };
  }

  handleEditPeriod(event) {
    const id = event.currentTarget.dataset.recordId;
    const indicator = this.model.indicators.find((item) =>
      (item.periods || []).some((period) => period.id === id)
    );
    const period = indicator.periods.find((item) => item.id === id);
    this.periodFormId = id;
    this.periodIndicatorId = indicator.id;
    this.periodDraft = {
      name: period.name,
      startDate: period.startDate,
      endDate: period.endDate,
      targetValue: period.targetValue,
      resultValue: period.resultValue,
      notes: period.notes || ''
    };
  }

  handlePeriodField(event) {
    this.periodDraft = { ...this.periodDraft, [event.target.dataset.field]: event.detail.value };
  }

  handlePeriodCancel() {
    this.periodFormId = undefined;
  }

  handlePeriodSave() {
    const period = { ...this.periodDraft };
    if (this.periodFormId === 'new') {
      period.indicatorId = this.periodIndicatorId;
    } else {
      period.id = this.periodFormId;
    }
    return this.run(savePeriod({ periodJson: JSON.stringify(period) }), () => {
      this.periodFormId = undefined;
    });
  }

  handleDeletePeriod(event) {
    return this.run(
      remove({ recordId: event.currentTarget.dataset.recordId }),
      null,
      LABELS.deleted
    );
  }

  // ---------------------------------------------------------------------------- saving

  run(call, after, message) {
    this.busy = true;
    return call
      .then((model) => {
        if (after) {
          after();
        }
        this.dispatchEvent(
          new CustomEvent('modelchange', { detail: { model, message: message || LABELS.saved } })
        );
      })
      .catch((error) => this.fail(error))
      .finally(() => {
        this.busy = false;
      });
  }
}
