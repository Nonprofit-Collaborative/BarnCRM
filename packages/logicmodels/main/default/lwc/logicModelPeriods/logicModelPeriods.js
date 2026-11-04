import { LightningElement, api } from 'lwc';
import savePeriods from '@salesforce/apex/LogicModelBuilderController.savePeriods';
import addPeriodToEveryIndicator from '@salesforce/apex/LogicModelBuilderController.addPeriodToEveryIndicator';
import { LABELS, format, messageFrom } from 'c/logicModelText';
import BarnConfirmModal from 'c/barnConfirmModal';

const EMPTY_DRAFT = Object.freeze({ name: '', startDate: null, endDate: null });

/** The key of a period: its dates, as R-IP2 compares them. */
function keyOf(period) {
  return `${period.startDate}|${period.endDate}`;
}

/**
 * A logic model's shared reporting periods (R-LM4; v1.0 modules-23): the list, Add Period, a
 * period removed from the list, and Add Period to Every Indicator. Saves hand the whole model
 * back in a `modelchange` event; a refusal goes up as `failure`, as the other builder panels do.
 */
export default class LogicModelPeriods extends LightningElement {
  @api model;
  /** The person can add indicator periods (Add Period to Every Indicator). */
  @api canEdit = false;

  labels = LABELS;
  busy = false;
  formOpen = false;
  draft = { ...EMPTY_DRAFT };

  get periods() {
    return ((this.model && this.model.periods) || []).map((period) => ({
      ...period,
      key: keyOf(period)
    }));
  }

  get hasPeriods() {
    return this.periods.length > 0;
  }

  get canEditPeriods() {
    return !!(this.model && this.model.canEditPeriods);
  }

  get showAdd() {
    return this.canEditPeriods && !this.formOpen;
  }

  get saveDisabled() {
    const draft = this.draft;
    return this.busy || !String(draft.name || '').trim() || !draft.startDate || !draft.endDate;
  }

  handleAdd() {
    this.formOpen = true;
    this.draft = { ...EMPTY_DRAFT };
  }

  handleField(event) {
    this.draft = { ...this.draft, [event.target.dataset.field]: event.detail.value };
  }

  handleCancel() {
    this.formOpen = false;
  }

  /** The list as saved: name and dates only. */
  listOf(periods) {
    return periods.map((period) => ({
      name: period.name,
      startDate: period.startDate,
      endDate: period.endDate
    }));
  }

  handleSave() {
    const rows = [...this.listOf(this.periods), { ...this.draft, name: this.draft.name.trim() }];
    return this.run(
      savePeriods({ modelId: this.model.id, periodsJson: JSON.stringify(rows) }),
      () => {
        this.formOpen = false;
      }
    );
  }

  async handleRemove(event) {
    const key = event.currentTarget.dataset.key;
    const period = this.periods.find((item) => item.key === key);
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: LABELS.remove,
      message: format(LABELS.periodsDeleteConfirm, period ? period.name : ''),
      confirmLabel: LABELS.remove,
      cancelLabel: LABELS.cancel,
      confirmVariant: 'destructive'
    });
    if (!confirmed) {
      return undefined;
    }
    const rows = this.listOf(this.periods.filter((item) => item.key !== key));
    return this.run(
      savePeriods({ modelId: this.model.id, periodsJson: JSON.stringify(rows) }),
      null,
      LABELS.deleted
    );
  }

  handleAddToEvery(event) {
    const key = event.currentTarget.dataset.key;
    const period = this.periods.find((item) => item.key === key);
    return this.run(
      addPeriodToEveryIndicator({
        modelId: this.model.id,
        startDate: period.startDate,
        endDate: period.endDate
      }),
      null,
      (model) => format(LABELS.periodsAdded, (model && model.added) || 0)
    );
  }

  /** Runs a save; `message` is a string or a function of the returned model. */
  run(call, after, message) {
    this.busy = true;
    return call
      .then((model) => {
        if (after) {
          after();
        }
        const text = typeof message === 'function' ? message(model) : message;
        this.dispatchEvent(
          new CustomEvent('modelchange', { detail: { model, message: text || LABELS.saved } })
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
