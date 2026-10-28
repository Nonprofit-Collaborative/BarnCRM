import { LightningElement, api } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import getCandidates from '@salesforce/apex/RollupDlrsImport.getCandidates';
import importRollups from '@salesforce/apex/RollupDlrsImport.importRollups';
import compare from '@salesforce/apex/RollupDlrsImport.compare';
import turnOn from '@salesforce/apex/RollupDlrsImport.turnOn';

import TITLE from '@salesforce/label/c.Core_RollupBuilder_DlrsImportTitle';
import INTRO from '@salesforce/label/c.Core_RollupBuilder_DlrsImportIntro';
import STEP_CHOOSE from '@salesforce/label/c.Core_RollupBuilder_DlrsImportStepChoose';
import STEP_REVIEW from '@salesforce/label/c.Core_RollupBuilder_DlrsImportStepReview';
import STEP_COMPARE from '@salesforce/label/c.Core_RollupBuilder_DlrsImportStepCompare';
import STEP_TURN_ON from '@salesforce/label/c.Core_RollupBuilder_DlrsImportStepTurnOn';
import CAN_COPY from '@salesforce/label/c.Core_RollupBuilder_DlrsImportCanCopy';
import STAYS from '@salesforce/label/c.Core_RollupBuilder_DlrsImportStays';
import NONE_ACTIVE from '@salesforce/label/c.Core_RollupBuilder_DlrsImportNoneActive';
import FILLS from '@salesforce/label/c.Core_RollupBuilder_DlrsImportFills';
import BECOMES from '@salesforce/label/c.Core_RollupBuilder_DlrsImportBecomes';
import NO_CHANGES from '@salesforce/label/c.Core_RollupBuilder_DlrsImportNoChanges';
import COPY from '@salesforce/label/c.Core_RollupBuilder_DlrsImportCopy';
import NEXT from '@salesforce/label/c.Core_RollupBuilder_DlrsImportNext';
import BACK from '@salesforce/label/c.Core_RollupBuilder_DlrsImportBack';
import CLOSE from '@salesforce/label/c.Core_RollupBuilder_DlrsImportClose';
import FINISH from '@salesforce/label/c.Core_RollupBuilder_DlrsImportFinish';
import COMPARE from '@salesforce/label/c.Core_RollupBuilder_DlrsImportCompare';
import TURN_ON from '@salesforce/label/c.Core_RollupBuilder_DlrsImportTurnOn';
import CREATED from '@salesforce/label/c.Core_RollupBuilder_DlrsImportCreated';
import UPDATED from '@salesforce/label/c.Core_RollupBuilder_DlrsImportUpdated';
import REFUSED from '@salesforce/label/c.Core_RollupBuilder_DlrsImportRefused';
import NOT_REACHED from '@salesforce/label/c.Core_RollupBuilder_DlrsImportNotReached';
import ACTIVE from '@salesforce/label/c.Core_RollupBuilder_DlrsImportActive';
import NOTHING_COPIED from '@salesforce/label/c.Core_RollupBuilder_DlrsImportNothingCopied';
import RECORD from '@salesforce/label/c.Core_RollupBuilder_DlrsImportRecord';
import VALUE_NOW from '@salesforce/label/c.Core_RollupBuilder_DlrsImportValueNow';
import VALUE_BARN from '@salesforce/label/c.Core_RollupBuilder_DlrsImportValueBarn';
import RESULT from '@salesforce/label/c.Core_RollupBuilder_DlrsImportResult';
import SAME from '@salesforce/label/c.Core_RollupBuilder_DlrsImportSame';
import NO_RECORDS from '@salesforce/label/c.Core_RollupBuilder_DlrsImportNoRecords';
import FINISH_HINT from '@salesforce/label/c.Core_RollupBuilder_DlrsImportFinishHint';
import FINISHED from '@salesforce/label/c.Core_RollupBuilder_DlrsImportFinished';
import CONFIRM_TITLE from '@salesforce/label/c.Core_RollupBuilder_DlrsConfirmTitle';
import CONFIRM_QUESTION from '@salesforce/label/c.Core_RollupBuilder_DlrsConfirmQuestion';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Rollups_UnexpectedError';

const CHOOSE_STEP = 'choose';
const REVIEW_STEP = 'review';
const COMPARE_STEP = 'compare';
const TURN_ON_STEP = 'turnOn';
/** Outcomes that leave a copy in BarnCRM (`RollupDlrsImport`). */
const COPIED = new Set(['created', 'updated', 'active']);
const OUTCOME_TEXT = {
  created: CREATED,
  updated: UPDATED,
  active: ACTIVE,
  notReached: NOT_REACHED
};

const format = (template, ...values) =>
  values.reduce((text, value, index) => text.replace(`{${index}}`, value), template);

/**
 * Import from DLRS (canonical model R-R16): choose the active DLRS rollups to copy, review what
 * each becomes, copy them switched off, compare their values with the ones DLRS wrote, then turn
 * each on with the admin's word that she will switch the DLRS rollup off. Finish waits until
 * every copy is on; Close leaves the copies switched off. DLRS itself is never changed.
 */
export default class RollupDlrsImport extends LightningElement {
  /** The Builder's model, for the names of the totals. */
  @api model;

  labels = {
    title: TITLE,
    intro: INTRO,
    canCopy: CAN_COPY,
    stays: STAYS,
    noneActive: NONE_ACTIVE,
    noChanges: NO_CHANGES,
    copy: COPY,
    next: NEXT,
    back: BACK,
    close: CLOSE,
    finish: FINISH,
    compare: COMPARE,
    turnOn: TURN_ON,
    nothingCopied: NOTHING_COPIED,
    record: RECORD,
    valueNow: VALUE_NOW,
    valueBarn: VALUE_BARN,
    result: RESULT,
    noRecords: NO_RECORDS,
    finishHint: FINISH_HINT
  };

  steps = [
    { value: CHOOSE_STEP, label: STEP_CHOOSE },
    { value: REVIEW_STEP, label: STEP_REVIEW },
    { value: COMPARE_STEP, label: STEP_COMPARE },
    { value: TURN_ON_STEP, label: STEP_TURN_ON }
  ];

  step = CHOOSE_STEP;
  candidates = [];
  chosen = new Set();
  rows = [];
  comparisons = {};
  loading = true;
  busy = false;
  error;

  connectedCallback() {
    getCandidates()
      .then((candidates) => {
        this.candidates = candidates || [];
        this.chosen = new Set(this.candidates.filter((c) => c.importable).map((c) => c.key));
      })
      .catch((error) => this.fail(error))
      .finally(() => {
        this.loading = false;
      });
  }

  get isChoose() {
    return this.step === CHOOSE_STEP;
  }

  get isReview() {
    return this.step === REVIEW_STEP;
  }

  get isCompare() {
    return this.step === COMPARE_STEP;
  }

  get isTurnOn() {
    return this.step === TURN_ON_STEP;
  }

  get hasCandidates() {
    return this.candidates.length > 0;
  }

  /** Step 1: what can be copied, chosen unless the admin unticks it. */
  get copyable() {
    return this.candidates
      .filter((c) => c.importable)
      .map((c) => ({
        key: c.key,
        label: c.label,
        checked: this.chosen.has(c.key),
        fills: this.fills(c)
      }));
  }

  get hasCopyable() {
    return this.copyable.length > 0;
  }

  /** Step 1: what stays in DLRS, and why. */
  get staying() {
    return this.candidates
      .filter((c) => !c.importable)
      .map((c) => ({
        key: c.key,
        label: c.label,
        fills: this.fills(c),
        reasons: this.listed(c.key, c.reasons)
      }));
  }

  get hasStaying() {
    return this.staying.length > 0;
  }

  get nothingChosen() {
    return this.chosen.size === 0;
  }

  /** Step 2: what each chosen rollup becomes, and what changes. */
  get reviewed() {
    return this.candidates
      .filter((c) => c.importable && this.chosen.has(c.key))
      .map((c) => {
        const notes = this.listed(c.key, c.notes);
        return {
          key: c.key,
          label: c.label,
          becomes: format(BECOMES, this.aggregateLabel(c.draft.aggregate), this.target(c)),
          notes,
          unchanged: notes.length === 0
        };
      });
  }

  /** Steps 3 and 4: what the copy did to each, with any comparison loaded. */
  get rowViews() {
    return this.rows.map((row) => {
      const compared = this.comparisons[row.recordId];
      return {
        key: row.key,
        name: row.name,
        recordId: row.recordId,
        outcome:
          row.outcome === 'refused' ? format(REFUSED, row.reason || '') : OUTCOME_TEXT[row.outcome],
        copied: COPIED.has(row.outcome),
        active: row.outcome === 'active',
        switchedOff: COPIED.has(row.outcome) && row.outcome !== 'active',
        compared: Boolean(compared),
        noRecords: Boolean(compared) && compared.length === 0,
        comparisons: (compared || []).map((c) => ({ ...c, result: c.agree ? SAME : c.difference }))
      };
    });
  }

  get copies() {
    return this.rowViews.filter((row) => row.copied);
  }

  get hasCopies() {
    return this.copies.length > 0;
  }

  get nothingCopied() {
    return !this.hasCopies;
  }

  /** Finish waits until every copy is on (plan D-124 item 6). */
  get finishDisabled() {
    return this.busy || !this.hasCopies || !this.copies.every((row) => row.active);
  }

  get copyDisabled() {
    return this.busy || this.nothingChosen;
  }

  handleChoose(event) {
    const chosen = new Set(this.chosen);
    if (event.target.checked) {
      chosen.add(event.target.dataset.key);
    } else {
      chosen.delete(event.target.dataset.key);
    }
    this.chosen = chosen;
  }

  handleNext() {
    this.error = undefined;
    this.step = this.isChoose ? REVIEW_STEP : TURN_ON_STEP;
  }

  handleBack() {
    this.error = undefined;
    this.step = this.isTurnOn ? COMPARE_STEP : CHOOSE_STEP;
  }

  /** Step 2 to 3: copies the chosen rollups, switched off. */
  handleCopy() {
    this.busy = true;
    this.error = undefined;
    importRollups({ keys: [...this.chosen] })
      .then((rows) => {
        this.rows = rows || [];
        this.step = COMPARE_STEP;
      })
      .catch((error) => this.fail(error))
      .finally(() => {
        this.busy = false;
      });
  }

  handleCompare(event) {
    const definitionId = event.target.dataset.record;
    this.busy = true;
    this.error = undefined;
    compare({ definitionId })
      .then((comparisons) => {
        this.comparisons = { ...this.comparisons, [definitionId]: comparisons || [] };
      })
      .catch((error) => this.fail(error))
      .finally(() => {
        this.busy = false;
      });
  }

  /** Turns one copy on once the admin confirms she will switch the DLRS rollup off (R-R16). */
  async handleTurnOn(event) {
    const definitionId = event.target.dataset.record;
    const row = this.rows.find((r) => r.recordId === definitionId);
    const confirmed = await LightningConfirm.open({
      label: CONFIRM_TITLE,
      message:
        row && row.confirmation ? `${row.confirmation} ${CONFIRM_QUESTION}` : CONFIRM_QUESTION,
      theme: 'warning'
    });
    if (!confirmed) {
      return;
    }
    this.busy = true;
    this.error = undefined;
    try {
      await turnOn({ definitionId, dlrsOffConfirmed: true });
      this.rows = this.rows.map((r) => {
        return r.recordId === definitionId ? { ...r, outcome: 'active' } : r;
      });
    } catch (error) {
      this.fail(error);
    } finally {
      this.busy = false;
    }
  }

  handleFinish() {
    this.dispatchEvent(
      new CustomEvent('close', {
        detail: { notice: format(FINISHED, String(this.copies.length)) }
      })
    );
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent('close', { detail: {} }));
  }

  fills(candidate) {
    return format(FILLS, this.target(candidate), candidate.operation || '');
  }

  target(candidate) {
    return `${candidate.parentObject}.${candidate.targetField}`;
  }

  listed(key, texts) {
    return (texts || []).map((text, index) => ({ id: `${key}-${index}`, text }));
  }

  aggregateLabel(value) {
    const options = (this.model && this.model.aggregates) || [];
    const option = options.find((o) => o.value === value);
    return option ? option.label : value;
  }

  fail(error) {
    this.error = error && error.body && error.body.message ? error.body.message : UNEXPECTED_ERROR;
  }
}
