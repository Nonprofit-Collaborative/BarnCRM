import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getKit from '@salesforce/apex/MigrationController.getKit';
import startStep from '@salesforce/apex/MigrationController.startStep';
import setToolStep from '@salesforce/apex/MigrationController.setToolStep';
import setChecklistItem from '@salesforce/apex/MigrationController.setChecklistItem';
import getBatch from '@salesforce/apex/ImportController.getBatch';
import getRowPage from '@salesforce/apex/ImportController.getRowPage';
import getChangedValues from '@salesforce/apex/ImportController.getChangedValues';
import startCommit from '@salesforce/apex/ImportController.startCommit';
import previewUndo from '@salesforce/apex/ImportController.previewUndo';
import startUndo from '@salesforce/apex/ImportController.startUndo';
import BarnConfirmModal from 'c/barnConfirmModal';
import { bodyMessage as messageOf } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/** Every word the page shows, from the Core help catalog (read once it has loaded). */
function words() {
  return {
    back: helpText('Core', 'Core_Migration_Back'),
    refresh: helpText('Core', 'Core_Migration_Refresh'),
    start: helpText('Core', 'Core_Migration_Start'),
    showResults: helpText('Core', 'Core_Migration_ShowResults'),
    hideResults: helpText('Core', 'Core_Migration_HideResults'),
    load: helpText('Core', 'Core_Migration_Load'),
    undo: helpText('Core', 'Core_Migration_Undo'),
    markDone: helpText('Core', 'Core_Migration_MarkDone'),
    markNotDone: helpText('Core', 'Core_Migration_MarkNotDone'),
    cancel: helpText('Core', 'Core_Migration_Cancel'),
    steps: helpText('Core', 'Core_Migration_Steps'),
    verification: helpText('Core', 'Core_Migration_Verification'),
    checkSource: helpText('Core', 'Core_Migration_CheckSource'),
    checkStaged: helpText('Core', 'Core_Migration_CheckStaged'),
    checkLoaded: helpText('Core', 'Core_Migration_CheckLoaded'),
    checkRejected: helpText('Core', 'Core_Migration_CheckRejected'),
    checkDone: helpText('Core', 'Core_Migration_CheckDone'),
    verified: helpText('Core', 'Core_Migration_Verified'),
    checkStep: helpText('Core', 'Core_Migration_CheckStep'),
    retire: helpText('Core', 'Core_Migration_Retire'),
    retireIntro: helpText('Core', 'Core_Migration_RetireIntro'),
    complete: helpText('Core', 'Core_Migration_Complete'),
    refreshHint: helpText('Core', 'Core_Migration_RefreshHint'),
    loadTitle: helpText('Core', 'Core_Migration_LoadTitle'),
    undoTitle: helpText('Core', 'Core_Migration_UndoTitle'),
    NotStarted: helpText('Core', 'Core_Migration_StatusNotStarted'),
    Waiting: helpText('Core', 'Core_Migration_StatusWaiting'),
    Running: helpText('Core', 'Core_Migration_StatusRunning'),
    Review: helpText('Core', 'Core_Migration_StatusReview'),
    Done: helpText('Core', 'Core_Migration_StatusDone'),
    Undone: helpText('Core', 'Core_Migration_StatusUndone'),
    Failed: helpText('Core', 'Core_Migration_StatusFailed')
  };
}

/** A step status's tone in the kit's vocabulary. */
const TONES = {
  NotStarted: 'neutral',
  Waiting: 'neutral',
  Running: 'in-progress',
  Review: 'warning',
  Done: 'success',
  Undone: 'neutral',
  Failed: 'error'
};

/** The rejected rows the results table shows; the rest are on the data job's rows. */
const RESULT_ROWS = 50;

function count(label, value, id) {
  return { key: id, label, value: value === null || value === undefined ? 0 : value };
}

/**
 * The Migration Assistant (MIG-01): one kit's steps in order, each with its status, the action
 * it allows now and its verification, then the retire checklist. Every rule (order, undo
 * backwards, what each step allows) is the server's (`MigrationController`); this draws it.
 * A loading step's preview, load and undo are the Super Importer's own, with its results panel.
 * Shown in place of the Integrations list; Back fires `back`.
 */
export default class MigrationAssistant extends NavigationMixin(LightningElement) {
  @api kitKey;

  helpReady = isHelpLoaded('Core');
  kit;
  errorMessage;
  noticeMessage;
  busy = false;

  /** The step whose results are open, with the Super Importer's batch and rows. */
  resultsStep;
  batch;
  rejectedRows = [];
  changedValues = [];

  get labels() {
    return words();
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    await this.work(async () => {
      this.kit = await getKit({ kitKey: this.kitKey });
    });
  }

  /** Runs one server call with the buttons off, showing a refusal in words. */
  async work(action) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage = messageOf(error, helpText('Core', 'Core_Migration_LoadErrorMessage'));
    } finally {
      this.busy = false;
    }
  }

  get title() {
    return this.kit ? this.kit.label : '';
  }

  get steps() {
    const steps = (this.kit && this.kit.steps) || [];
    const w = words();
    return steps.map((step, index) => {
      const status = TONES[step.status] ? step.status : 'NotStarted';
      const isImport = step.kind === 'import';
      const counts = isImport
        ? [
            count(w.checkSource, step.sourceCount, 'source'),
            count(w.checkStaged, step.staged, 'staged'),
            count(w.checkLoaded, step.loaded, 'loaded'),
            count(w.checkRejected, step.rejected, 'rejected')
          ]
        : [];
      if (step.checkSource !== null && step.checkSource !== undefined) {
        counts.push(count(w.checkSource, step.checkSource, 'check-source'));
        counts.push(count(w.checkDone, step.checkDone, 'check-done'));
      }
      return {
        ...step,
        number: `${index + 1}.`,
        statusText: w[status],
        statusTone: TONES[status],
        counts,
        showVerification: step.hasVerification && step.status !== 'Waiting',
        verdict: step.verified ? w.verified : w.checkStep,
        verdictTone: step.verified ? 'success' : 'warning',
        canShowResults: Boolean(step.batchId) && step.status !== 'Running',
        resultsOpen: this.resultsStep === step.key,
        resultsLabel: this.resultsStep === step.key ? w.hideResults : w.showResults,
        startLabel: w.start,
        loadLabel: w.load,
        undoLabel: w.undo,
        markDoneLabel: w.markDone,
        markNotDoneLabel: w.markNotDone,
        canOpenTool: Boolean(step.tab) && !isImport && step.status !== 'Waiting'
      };
    });
  }

  get checklist() {
    return (this.kit && this.kit.checklist) || [];
  }

  get showChecklist() {
    return this.checklist.length > 0;
  }

  get checklistDisabled() {
    return this.busy || !(this.kit && this.kit.allDone);
  }

  get isComplete() {
    return Boolean(this.kit && this.kit.complete);
  }

  stepOf(event) {
    const key = event.currentTarget.dataset.step;
    return this.kit.steps.find((step) => step.key === key);
  }

  handleBack() {
    this.dispatchEvent(new CustomEvent('back'));
  }

  handleRefresh() {
    this.noticeMessage = undefined;
    return this.load().then(() => (this.resultsStep ? this.readResults(this.resultsStep) : null));
  }

  async handleStart(event) {
    const step = this.stepOf(event);
    this.noticeMessage = undefined;
    await this.work(async () => {
      this.kit = await startStep({ kitKey: this.kitKey, stepKey: step.key });
    });
  }

  async handleToggleResults(event) {
    const step = this.stepOf(event);
    if (this.resultsStep === step.key) {
      this.resultsStep = undefined;
      return;
    }
    await this.readResults(step.key);
  }

  /** The step's data job as the Super Importer shows it: counts, run log, rejected rows. */
  async readResults(stepKey) {
    const step = this.kit.steps.find((candidate) => candidate.key === stepKey);
    if (!step || !step.batchId) {
      this.resultsStep = undefined;
      return;
    }
    await this.work(async () => {
      const batch = await getBatch({ batchId: step.batchId });
      const page = await getRowPage({
        batchId: step.batchId,
        status: 'Rejected',
        cursor: null,
        startIndex: 0,
        pageSize: RESULT_ROWS
      });
      this.changedValues =
        batch && batch.isDryRun ? (await getChangedValues({ batchId: step.batchId })) || [] : [];
      this.rejectedRows = (page && page.rows) || [];
      this.batch = batch;
      this.resultsStep = stepKey;
    });
  }

  async handleLoad(event) {
    const step = this.stepOf(event);
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: this.labels.loadTitle,
      message: helpText('Core', 'Core_Migration_LoadConfirm', String(step.staged || 0)),
      confirmLabel: this.labels.load,
      cancelLabel: this.labels.cancel
    });
    if (!confirmed) {
      return;
    }
    await this.work(async () => {
      await startCommit({ batchId: step.batchId });
      this.resultsStep = undefined;
      this.kit = await getKit({ kitKey: this.kitKey });
      this.noticeMessage = helpText('Core', 'Core_Migration_Started');
    });
  }

  /** The Super Importer undo, confirmed with the number of records it removes (R-IB8). */
  async handleUndo(event) {
    const step = this.stepOf(event);
    let preview;
    await this.work(async () => {
      preview = await previewUndo({ batchId: step.batchId });
      if (preview && !preview.allowed) {
        this.errorMessage = preview.reason;
      }
    });
    if (!preview || !preview.allowed) {
      return;
    }
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: this.labels.undoTitle,
      message: helpText(
        'Core',
        'Core_Migration_UndoConfirm',
        String(preview.total || 0),
        String(preview.updates || 0)
      ),
      confirmLabel: this.labels.undo,
      cancelLabel: this.labels.cancel,
      confirmVariant: 'destructive'
    });
    if (!confirmed) {
      return;
    }
    await this.work(async () => {
      await startUndo({ batchId: step.batchId, confirmedTotal: preview.total });
      this.resultsStep = undefined;
      this.kit = await getKit({ kitKey: this.kitKey });
      this.noticeMessage = helpText('Core', 'Core_Migration_Started');
    });
  }

  async handleMark(event) {
    const step = this.stepOf(event);
    const done = event.currentTarget.dataset.done === 'true';
    await this.work(async () => {
      this.kit = await setToolStep({ kitKey: this.kitKey, stepKey: step.key, done });
    });
  }

  handleOpenTool(event) {
    const step = this.stepOf(event);
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: step.tab }
    });
  }

  async handleTick(event) {
    const itemKey = event.target.dataset.item;
    const ticked = event.target.checked;
    await this.work(async () => {
      this.kit = await setChecklistItem({ kitKey: this.kitKey, itemKey, ticked });
    });
  }
}
