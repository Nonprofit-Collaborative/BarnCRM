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
    back: helpText('Migration', 'Migration_Back'),
    refresh: helpText('Migration', 'Migration_Refresh'),
    start: helpText('Migration', 'Migration_Start'),
    showResults: helpText('Migration', 'Migration_ShowResults'),
    hideResults: helpText('Migration', 'Migration_HideResults'),
    load: helpText('Migration', 'Migration_Load'),
    undo: helpText('Migration', 'Migration_Undo'),
    markDone: helpText('Migration', 'Migration_MarkDone'),
    markNotDone: helpText('Migration', 'Migration_MarkNotDone'),
    cancel: helpText('Migration', 'Migration_Cancel'),
    steps: helpText('Migration', 'Migration_Steps'),
    verification: helpText('Migration', 'Migration_Verification'),
    checkSource: helpText('Migration', 'Migration_CheckSource'),
    checkStaged: helpText('Migration', 'Migration_CheckStaged'),
    checkLoaded: helpText('Migration', 'Migration_CheckLoaded'),
    checkRejected: helpText('Migration', 'Migration_CheckRejected'),
    checkDone: helpText('Migration', 'Migration_CheckDone'),
    verified: helpText('Migration', 'Migration_Verified'),
    checkStep: helpText('Migration', 'Migration_CheckStep'),
    retire: helpText('Migration', 'Migration_Retire'),
    retireIntro: helpText('Migration', 'Migration_RetireIntro'),
    complete: helpText('Migration', 'Migration_Complete'),
    refreshHint: helpText('Migration', 'Migration_RefreshHint'),
    loadTitle: helpText('Migration', 'Migration_LoadTitle'),
    undoTitle: helpText('Migration', 'Migration_UndoTitle'),
    NotStarted: helpText('Migration', 'Migration_StatusNotStarted'),
    Waiting: helpText('Migration', 'Migration_StatusWaiting'),
    Running: helpText('Migration', 'Migration_StatusRunning'),
    Review: helpText('Migration', 'Migration_StatusReview'),
    Done: helpText('Migration', 'Migration_StatusDone'),
    Undone: helpText('Migration', 'Migration_StatusUndone'),
    Failed: helpText('Migration', 'Migration_StatusFailed')
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
 * Shown by `migrationHome` in place of the kit list; Back fires `back`.
 */
export default class MigrationAssistant extends NavigationMixin(LightningElement) {
  @api kitKey;

  helpReady = isHelpLoaded('Migration');
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
      loadHelp('Migration').then(() => {
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
      this.errorMessage = messageOf(error, helpText('Migration', 'Migration_LoadErrorMessage'));
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
      message: helpText('Migration', 'Migration_LoadConfirm', String(step.staged || 0)),
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
      this.noticeMessage = helpText('Migration', 'Migration_Started');
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
        'Migration',
        'Migration_UndoConfirm',
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
      this.noticeMessage = helpText('Migration', 'Migration_Started');
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
