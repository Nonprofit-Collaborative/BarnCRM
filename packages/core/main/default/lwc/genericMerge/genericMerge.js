import { LightningElement } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import getView from '@salesforce/apex/GenericMergeController.getView';
import compare from '@salesforce/apex/GenericMergeController.compare';
import mergeRecords from '@salesforce/apex/GenericMergeController.mergeRecords';
import undo from '@salesforce/apex/GenericMergeController.undo';

import OBJECT from '@salesforce/label/c.Core_MatchLogic_Object';
import COMPARE from '@salesforce/label/c.Core_AccessCompare_Compare';
import KEEP from '@salesforce/label/c.Core_GenericMerge_Keep';
import ONLY_DIFFERENCES from '@salesforce/label/c.Core_GenericMerge_OnlyDifferences';
import MERGE from '@salesforce/label/c.Core_HouseholdMerge_MergeButton';
import UNDO from '@salesforce/label/c.Core_AutoMerge_Undo';
import FIELD from '@salesforce/label/c.Core_AccessExplorer_Field';
import BLANK from '@salesforce/label/c.Core_Find_Blank';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { fromOther, initialChoices, visibleRows } from './mergeChoices';

function format(label, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), label);
}

/**
 * The Merge Records area of the Duplicate Matching tab (C-62, admin guide duplicates.md,
 * "Merge Records"): compare two records of one BarnCRM object, choose the value each field
 * keeps, merge after a confirm, and undo a recent merge. The server checks every permission.
 */
export default class GenericMerge extends LightningElement {
  helpReady = isHelpLoaded('Core');

  labels = {
    get intro() {
      return helpText('Core', 'Core_GenericMerge_Intro');
    },
    get off() {
      return helpText('Core', 'Core_GenericMerge_Off');
    },
    get noMerges() {
      return helpText('Core', 'Core_GenericMerge_NoMerges');
    },
    get first() {
      return helpText('Core', 'Core_GenericMerge_First');
    },
    get second() {
      return helpText('Core', 'Core_GenericMerge_Second');
    },
    get recentMerges() {
      return helpText('Core', 'Core_GenericMerge_RecentMerges');
    },
    object: OBJECT,
    compare: COMPARE,
    keep: KEEP,
    onlyDifferences: ONLY_DIFFERENCES,
    merge: MERGE,
    undo: UNDO,
    field: FIELD,
    refresh: REFRESH,
    loading: LOADING
  };

  view;
  objectName;
  firstId;
  secondId;
  comparison;
  choices = {};
  keep = 'first';
  onlyDifferences = false;
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

  get enabled() {
    return Boolean(this.view && this.view.enabled);
  }

  get showOff() {
    return Boolean(this.view) && !this.view.enabled;
  }

  get objectOptions() {
    return (this.view && this.view.objects) || [];
  }

  get compareDisabled() {
    return this.loading || !this.objectName || !this.firstId || !this.secondId;
  }

  get keepOptions() {
    if (!this.comparison) {
      return [];
    }
    return [
      { label: this.comparison.firstName || this.labels.first, value: 'first' },
      { label: this.comparison.secondName || this.labels.second, value: 'second' }
    ];
  }

  get rows() {
    if (!this.comparison) {
      return [];
    }
    return visibleRows(this.comparison.fields, this.choices, this.onlyDifferences).map((row) => ({
      ...row,
      firstText: row.first || BLANK,
      secondText: row.second || BLANK,
      rowClass: row.differs ? 'slds-hint-parent' : 'slds-hint-parent slds-text-color_weak'
    }));
  }

  get mergeRows() {
    return ((this.view && this.view.merges) || []).map((merged) => ({
      ...merged,
      title: `${merged.objectLabel}: ${merged.mergedName}`,
      hasNotes: Boolean(merged.notes)
    }));
  }

  get hasMerges() {
    return this.mergeRows.length > 0;
  }

  /** A new object or record starts a fresh comparison. */
  clearComparison() {
    this.comparison = undefined;
    this.choices = {};
    this.keep = 'first';
  }

  handleObject(event) {
    this.objectName = event.detail.value;
    this.firstId = undefined;
    this.secondId = undefined;
    this.message = undefined;
    this.clearComparison();
  }

  handleRecord(event) {
    const recordId = (event.detail && event.detail.recordId) || undefined;
    if (event.target.dataset.side === 'second') {
      this.secondId = recordId;
    } else {
      this.firstId = recordId;
    }
    this.clearComparison();
  }

  async handleCompare() {
    this.message = undefined;
    await this.call(async () => {
      const compared = await compare({
        objectName: this.objectName,
        firstId: this.firstId,
        secondId: this.secondId
      });
      this.comparison = compared;
      this.choices = initialChoices(compared.fields);
      this.keep = 'first';
    });
  }

  handleKeep(event) {
    this.keep = event.detail.value;
  }

  handleChoice(event) {
    const { field, side } = event.target.dataset;
    this.choices = { ...this.choices, [field]: side };
  }

  handleOnlyDifferences(event) {
    this.onlyDifferences = event.target.checked;
  }

  async handleMerge() {
    const keepId = this.keep === 'second' ? this.secondId : this.firstId;
    const otherId = this.keep === 'second' ? this.firstId : this.secondId;
    const keepName =
      this.keep === 'second' ? this.comparison.secondName : this.comparison.firstName;
    const otherName =
      this.keep === 'second' ? this.comparison.firstName : this.comparison.secondName;
    const confirmed = await BarnConfirmModal.open({
      label: helpText('Core', 'Core_GenericMerge_ConfirmHeading'),
      message: format(helpText('Core', 'Core_GenericMerge_ConfirmBody'), otherName, keepName),
      confirmLabel: MERGE,
      cancelLabel: CANCEL,
      size: 'small'
    });
    if (!confirmed) {
      return;
    }
    await this.call(async () => {
      const outcome = await mergeRecords({
        objectName: this.objectName,
        keepId,
        otherId,
        fromOther: fromOther(this.comparison.fields, this.choices, this.keep)
      });
      this.message = format(
        helpText('Core', 'Core_GenericMerge_Merged'),
        outcome.moved,
        outcome.changed
      );
      this.firstId = undefined;
      this.secondId = undefined;
      this.clearComparison();
      this.view = await getView();
    });
  }

  async handleUndo(event) {
    const journalId = event.target.dataset.journal;
    const confirmed = await BarnConfirmModal.open({
      label: helpText('Core', 'Core_GenericMerge_UndoHeading'),
      message: helpText('Core', 'Core_GenericMerge_UndoBody'),
      confirmLabel: UNDO,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive',
      size: 'small'
    });
    if (!confirmed) {
      return;
    }
    await this.call(async () => {
      this.view = await undo({ journalId });
      this.message = helpText('Core', 'Core_GenericMerge_Undone');
    });
  }

  handleRefresh() {
    this.message = undefined;
    this.load();
  }
}
