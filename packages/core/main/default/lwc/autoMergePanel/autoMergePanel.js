import { LightningElement } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import getView from '@salesforce/apex/AutoMergeController.getView';
import preview from '@salesforce/apex/AutoMergeController.preview';
import startRun from '@salesforce/apex/AutoMergeController.startRun';
import undoRun from '@salesforce/apex/AutoMergeController.undoRun';

import INTRO from '@salesforce/label/c.Core_AutoMerge_Intro';
import RULE from '@salesforce/label/c.Core_AutoMerge_Rule';
import PREVIEW from '@salesforce/label/c.Core_AutoMerge_Preview';
import REFRESH from '@salesforce/label/c.Core_AutoMerge_Refresh';
import LOADING from '@salesforce/label/c.Core_AutoMerge_Loading';
import RUNNING from '@salesforce/label/c.Core_AutoMerge_Running';
import PREVIEW_HEADING from '@salesforce/label/c.Core_AutoMerge_PreviewHeading';
import NONE from '@salesforce/label/c.Core_AutoMerge_None';
import KEEP from '@salesforce/label/c.Core_AutoMerge_Keep';
import MERGE_AWAY from '@salesforce/label/c.Core_AutoMerge_MergeAway';
import NO_CHANGES from '@salesforce/label/c.Core_AutoMerge_NoChanges';
import CHANGE from '@salesforce/label/c.Core_AutoMerge_Change';
import BLANK from '@salesforce/label/c.Core_AutoMerge_Blank';
import MORE from '@salesforce/label/c.Core_AutoMerge_More';
import MERGE_BUTTON from '@salesforce/label/c.Core_AutoMerge_MergeButton';
import CONFIRM_HEADING from '@salesforce/label/c.Core_AutoMerge_ConfirmHeading';
import CONFIRM_BODY from '@salesforce/label/c.Core_AutoMerge_ConfirmBody';
import CANCEL from '@salesforce/label/c.Core_AutoMerge_Cancel';
import STARTED from '@salesforce/label/c.Core_AutoMerge_Started';
import RECENT_RUNS from '@salesforce/label/c.Core_AutoMerge_RecentRuns';
import NO_RUNS from '@salesforce/label/c.Core_AutoMerge_NoRuns';
import RUN_SUMMARY from '@salesforce/label/c.Core_AutoMerge_RunSummary';
import UNDO from '@salesforce/label/c.Core_AutoMerge_Undo';
import UNDO_HEADING from '@salesforce/label/c.Core_AutoMerge_UndoHeading';
import UNDO_BODY from '@salesforce/label/c.Core_AutoMerge_UndoBody';
import UNDO_STARTED from '@salesforce/label/c.Core_AutoMerge_UndoStarted';
import NO_ACCESS from '@salesforce/label/c.Core_AutoMerge_NoAccess';
import UNEXPECTED from '@salesforce/label/c.Core_Duplicates_ErrorUnexpected';

function format(label, ...values) {
  return values.reduce((text, value, index) => text.replace(`{${index}}`, value), label);
}

/**
 * The Auto-Merge area of the Duplicate Matching tab (C-51, admin guide duplicates.md,
 * "Auto-Merge"): preview the exact people matches in the review list, merge them in one
 * background run after a confirm, and undo a recent run. The server checks every permission.
 */
export default class AutoMergePanel extends LightningElement {
  labels = {
    intro: INTRO,
    preview: PREVIEW,
    refresh: REFRESH,
    loading: LOADING,
    running: RUNNING,
    none: NONE,
    keep: KEEP,
    mergeAway: MERGE_AWAY,
    noChanges: NO_CHANGES,
    recentRuns: RECENT_RUNS,
    noRuns: NO_RUNS,
    undo: UNDO,
    noAccess: NO_ACCESS
  };

  view;
  previewed;
  loading = false;
  error;
  message;

  connectedCallback() {
    this.load();
  }

  async load() {
    await this.call(async () => {
      this.view = await getView();
    });
  }

  /** Runs one server call with the spinner on, showing its error, if any, in one sentence. */
  async call(work) {
    this.loading = true;
    this.error = undefined;
    try {
      await work();
    } catch (caught) {
      this.error = (caught && caught.body && caught.body.message) || UNEXPECTED;
    } finally {
      this.loading = false;
    }
  }

  get ruleText() {
    return this.view ? format(RULE, this.view.exactRule) : '';
  }

  get running() {
    return Boolean(this.view && this.view.running);
  }

  get canRun() {
    return Boolean(this.view && this.view.canRun);
  }

  get previewDisabled() {
    return this.loading || this.running || !this.canRun;
  }

  get showNoAccess() {
    return Boolean(this.view) && !this.canRun;
  }

  get previewHeading() {
    return this.previewed ? format(PREVIEW_HEADING, this.previewed.total) : '';
  }

  get hasPairs() {
    return Boolean(this.previewed && this.previewed.total > 0);
  }

  get pairRows() {
    return ((this.previewed && this.previewed.pairs) || []).map((pair) => {
      const changes = (pair.changes || []).map((change) =>
        format(CHANGE, change.label, change.before || BLANK, change.after || BLANK)
      );
      return {
        ref: pair.ref,
        survivorName: pair.survivorName,
        mergedName: pair.mergedName,
        hasChanges: changes.length > 0,
        changeText: changes.join('; ')
      };
    });
  }

  get moreNotShown() {
    return Boolean(this.previewed) && this.previewed.total > this.previewed.pairs.length;
  }

  get moreText() {
    return this.previewed ? format(MORE, this.previewed.pairs.length, this.previewed.total) : '';
  }

  get mergeLabel() {
    return format(MERGE_BUTTON, this.previewed ? this.previewed.total : 0);
  }

  get runRows() {
    return ((this.view && this.view.runs) || []).map((run) => ({
      runId: run.runId,
      startedAt: run.startedAt,
      canUndo: run.canUndo,
      summary: format(RUN_SUMMARY, run.merged, run.undone, run.notUndone),
      noteLines: (run.notes || []).map((text, index) => ({ key: `${run.runId}-${index}`, text }))
    }));
  }

  get hasRuns() {
    return this.runRows.length > 0;
  }

  handleRefresh() {
    this.message = undefined;
    this.load();
  }

  async handlePreview() {
    this.message = undefined;
    await this.call(async () => {
      this.previewed = await preview();
    });
  }

  async handleMerge() {
    const total = this.previewed ? this.previewed.total : 0;
    const confirmed = await BarnConfirmModal.open({
      label: CONFIRM_HEADING,
      message: format(CONFIRM_BODY, total),
      confirmLabel: this.mergeLabel,
      cancelLabel: CANCEL,
      size: 'small'
    });
    if (!confirmed) {
      return;
    }
    await this.call(async () => {
      this.view = await startRun();
      this.previewed = undefined;
      this.message = STARTED;
    });
  }

  async handleUndo(event) {
    const runId = event.target.dataset.run;
    const confirmed = await BarnConfirmModal.open({
      label: UNDO_HEADING,
      message: UNDO_BODY,
      confirmLabel: UNDO,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive',
      size: 'small'
    });
    if (!confirmed) {
      return;
    }
    await this.call(async () => {
      this.view = await undoRun({ runId });
      this.message = UNDO_STARTED;
    });
  }
}
