import { LightningElement, api } from 'lwc';
import saveIndicator from '@salesforce/apex/LogicModelBuilderController.saveIndicator';
import savePeriod from '@salesforce/apex/LogicModelBuilderController.savePeriod';
import remove from '@salesforce/apex/LogicModelBuilderController.remove';

import { progress } from 'c/logicModelRules';
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
      .catch((error) => {
        this.dispatchEvent(new CustomEvent('failure', { detail: { message: messageFrom(error) } }));
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
