import { LightningElement } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import getView from '@salesforce/apex/AutoMergeController.getView';
import preview from '@salesforce/apex/AutoMergeController.preview';
import startRun from '@salesforce/apex/AutoMergeController.startRun';
import undoRun from '@salesforce/apex/AutoMergeController.undoRun';

import PREVIEW from '@salesforce/label/c.Core_AutoMerge_Preview';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import PREVIEW_HEADING from '@salesforce/label/c.Core_AutoMerge_PreviewHeading';
import KEEP from '@salesforce/label/c.Core_AutoMerge_Keep';
import MERGE_AWAY from '@salesforce/label/c.Core_AutoMerge_MergeAway';
import CHANGE from '@salesforce/label/c.Core_AutoMerge_Change';
import BLANK from '@salesforce/label/c.Core_Find_Blank';
import MERGE_BUTTON from '@salesforce/label/c.Core_AutoMerge_MergeButton';
import CONFIRM_HEADING from '@salesforce/label/c.Core_AutoMerge_ConfirmHeading';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import RECENT_RUNS from '@salesforce/label/c.Core_AutoMerge_RecentRuns';
import UNDO from '@salesforce/label/c.Core_AutoMerge_Undo';
import UNDO_HEADING from '@salesforce/label/c.Core_AutoMerge_UndoHeading';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

function format(label, ...values) {
  return values.reduce((text, value, index) => text.replace(`{${index}}`, value), label);
}

/**
 * The Auto-Merge area of the Duplicate Matching tab (C-51, admin guide duplicates.md,
 * "Auto-Merge"): preview the exact people matches in the review list, merge them in one
 * background run after a confirm, and undo a recent run. The server checks every permission.
 */
export default class AutoMergePanel extends LightningElement {
  helpReady = isHelpLoaded('Core');

  labels = {
    get intro() {
      return helpText('Core', 'Core_AutoMerge_Intro');
    },
    preview: PREVIEW,
    refresh: REFRESH,
    loading: LOADING,
    get running() {
      return helpText('Core', 'Core_AutoMerge_Running');
    },
    get none() {
      return helpText('Core', 'Core_AutoMerge_None');
    },
    keep: KEEP,
    mergeAway: MERGE_AWAY,
    get noChanges() {
      return helpText('Core', 'Core_AutoMerge_NoChanges');
    },
    recentRuns: RECENT_RUNS,
    get noRuns() {
      return helpText('Core', 'Core_AutoMerge_NoRuns');
    },
    undo: UNDO,
    get noAccess() {
      return helpText('Core', 'Core_AutoMerge_NoAccess');
    }
  };

  view;
  previewed;
  loading = false;
  error;
  message;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
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
      this.error =
        (caught && caught.body && caught.body.message) ||
        helpText('Core', 'Core_Duplicates_ErrorUnexpected');
    } finally {
      this.loading = false;
    }
  }

  get ruleText() {
    return this.view ? format(helpText('Core', 'Core_AutoMerge_Rule'), this.view.exactRule) : '';
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
    return this.previewed
      ? format(
          helpText('Core', 'Core_AutoMerge_More'),
          this.previewed.pairs.length,
          this.previewed.total
        )
      : '';
  }

  get mergeLabel() {
    return format(MERGE_BUTTON, this.previewed ? this.previewed.total : 0);
  }

  get runRows() {
    return ((this.view && this.view.runs) || []).map((run) => ({
      runId: run.runId,
      startedAt: run.startedAt,
      canUndo: run.canUndo,
      summary: format(
        helpText('Core', 'Core_AutoMerge_RunSummary'),
        run.merged,
        run.undone,
        run.notUndone
      ),
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
      message: format(helpText('Core', 'Core_AutoMerge_ConfirmBody'), total),
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
      this.message = helpText('Core', 'Core_AutoMerge_Started');
    });
  }

  async handleUndo(event) {
    const runId = event.target.dataset.run;
    const confirmed = await BarnConfirmModal.open({
      label: UNDO_HEADING,
      message: helpText('Core', 'Core_AutoMerge_UndoBody'),
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
      this.message = helpText('Core', 'Core_AutoMerge_UndoStarted');
    });
  }
}
