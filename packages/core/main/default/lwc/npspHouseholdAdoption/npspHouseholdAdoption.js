import { LightningElement, api } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import { bodyMessage, format } from 'c/findCsv';
import { startPolling } from 'c/jobPoller';
import getStatus from '@salesforce/apex/NpspHouseholdAdoptionController.getStatus';
import adopt from '@salesforce/apex/NpspHouseholdAdoptionController.adopt';
import undo from '@salesforce/apex/NpspHouseholdAdoptionController.undo';

import TITLE from '@salesforce/label/c.Core_NpspAdoption_Title';
import SAMPLE_CAPTION from '@salesforce/label/c.Core_NpspAdoption_SampleCaption';
import COLUMN_NAME from '@salesforce/label/c.Core_Households_NameSuffix';
import COLUMN_FORMAL from '@salesforce/label/c.Core_HouseholdNamingSettings_ColumnFormal';
import COLUMN_INFORMAL from '@salesforce/label/c.Core_HouseholdNamingSettings_ColumnInformal';
import COLUMN_PRIMARY from '@salesforce/label/c.Core_NpspAdoption_ColumnPrimary';
import COLUMN_CONTACTS from '@salesforce/label/c.Core_SampleData_ContactsLabel';
import KEEP_NAMES from '@salesforce/label/c.Core_NpspAdoption_KeepNames';
import ADOPT_BUTTON from '@salesforce/label/c.Core_NpspAdoption_AdoptButton';
import TYPE_TO_ADOPT from '@salesforce/label/c.Core_NpspAdoption_TypeToAdopt';
import CONFIRM_ADOPT from '@salesforce/label/c.Core_NpspAdoption_ConfirmAdopt';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import LAST_RUN from '@salesforce/label/c.Core_NpspAdoption_LastRun';
import UNDO_BUTTON from '@salesforce/label/c.Core_NpspAdoption_UndoButton';
import TYPE_TO_UNDO from '@salesforce/label/c.Core_NpspAdoption_TypeToUndo';
import CONFIRM_UNDO from '@salesforce/label/c.Core_AutoMerge_Undo';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * Adopt NPSP Households, on the General page of BarnCRM Settings (X-05, admin guide
 * npsp-households.md). The settings console shows this row only where NPSP applies and only to
 * holders of Manage BarnCRM Settings; the controller checks the permission again on every call.
 *
 * It shows what would be adopted, starts a run after the person types the count, polls while a
 * run or an undo is going, and offers the undo of the newest run. Every rule lives in Apex.
 */
export default class NpspHouseholdAdoption extends LightningElement {
  helpReady = isHelpLoaded('Core');

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Core', 'Core_NpspAdoption_Intro');
    },
    get notAvailable() {
      return helpText('Core', 'Core_NpspAdoption_NotAvailable');
    },
    get noneLeft() {
      return helpText('Core', 'Core_NpspAdoption_NoneLeft');
    },
    sampleCaption: SAMPLE_CAPTION,
    columnName: COLUMN_NAME,
    columnFormal: COLUMN_FORMAL,
    columnInformal: COLUMN_INFORMAL,
    columnPrimary: COLUMN_PRIMARY,
    columnContacts: COLUMN_CONTACTS,
    keepNames: KEEP_NAMES,
    get keepNamesHelp() {
      return helpText('Core', 'Core_NpspAdoption_KeepNamesHelp');
    },
    adoptButton: ADOPT_BUTTON,
    get running() {
      return helpText('Core', 'Core_NpspAdoption_Running');
    },
    lastRun: LAST_RUN,
    undoButton: UNDO_BUTTON,
    refresh: REFRESH
  };

  status;
  keepNames = true;
  busy = false;
  errorMessage;
  noticeMessage;
  stopPolling;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  disconnectedCallback() {
    this.stop();
  }

  /** The console calls this after a save: a membership change can block or unblock a run. */
  @api
  refresh() {
    return this.load();
  }

  async load() {
    try {
      this.status = await getStatus();
      this.errorMessage = undefined;
      if (this.status.running) {
        this.poll();
      }
    } catch (error) {
      this.errorMessage = bodyMessage(error);
    }
    return this.status;
  }

  poll() {
    if (this.stopPolling) {
      return;
    }
    this.stopPolling = startPolling(
      async () => {
        this.status = await getStatus();
        if (!this.status.running) {
          this.stop();
          return true;
        }
        return false;
      },
      (error) => {
        this.stop();
        this.errorMessage = bodyMessage(error);
      }
    );
  }

  stop() {
    if (this.stopPolling) {
      this.stopPolling();
      this.stopPolling = undefined;
    }
  }

  get available() {
    return !!(this.status && this.status.available);
  }

  get running() {
    return !!(this.status && this.status.running);
  }

  get blockedReason() {
    return this.status ? this.status.blockedReason : undefined;
  }

  get candidateCount() {
    return this.status ? this.status.candidateCount || 0 : 0;
  }

  /** What one run adopts: every candidate, up to the run limit. */
  get runCount() {
    return this.status ? Math.min(this.candidateCount, this.status.runLimit) : 0;
  }

  get hasCandidates() {
    return this.candidateCount > 0;
  }

  get candidateMessage() {
    return format(
      helpText('Core', 'Core_NpspAdoption_CandidateCount'),
      this.runCount.toLocaleString()
    );
  }

  get moreThanLimitMessage() {
    return this.status && this.status.moreThanLimit
      ? format(
          helpText('Core', 'Core_NpspAdoption_MoreThanLimit'),
          this.status.runLimit.toLocaleString()
        )
      : undefined;
  }

  get sample() {
    return this.status && this.status.sample ? this.status.sample : [];
  }

  get hasSample() {
    return this.sample.length > 0;
  }

  get lastRun() {
    return this.status ? this.status.lastRun : undefined;
  }

  get lastRunCounts() {
    const run = this.lastRun;
    return run
      ? format(
          helpText('Core', 'Core_NpspAdoption_LastRunCounts'),
          run.adopted,
          run.undone,
          run.notRestored
        )
      : undefined;
  }

  get adoptDisabled() {
    return this.busy || this.running || !!this.blockedReason || !this.hasCandidates;
  }

  get canUndo() {
    return !!(this.lastRun && this.lastRun.adopted > 0);
  }

  get undoDisabled() {
    return this.busy || this.running;
  }

  handleKeepNames(event) {
    this.keepNames = event.target.checked;
  }

  handleRefresh() {
    this.noticeMessage = undefined;
    this.load();
  }

  async handleAdopt() {
    const count = this.runCount;
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: TITLE,
      message: format(helpText('Core', 'Core_NpspAdoption_ConfirmMessage'), count.toLocaleString()),
      typeToConfirm: String(count),
      typeToConfirmLabel: format(TYPE_TO_ADOPT, count),
      confirmLabel: CONFIRM_ADOPT,
      cancelLabel: CANCEL
    });
    if (!confirmed) {
      return;
    }
    await this.start(() => adopt({ keepNames: this.keepNames, confirmedCount: count }));
  }

  async handleUndo() {
    const run = this.lastRun;
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: UNDO_BUTTON,
      message: format(
        helpText('Core', 'Core_NpspAdoption_UndoMessage'),
        run.adopted.toLocaleString()
      ),
      typeToConfirm: String(run.adopted),
      typeToConfirmLabel: format(TYPE_TO_UNDO, run.adopted),
      confirmLabel: CONFIRM_UNDO,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive'
    });
    if (!confirmed) {
      return;
    }
    await this.start(() => undo({ runId: run.runId, confirmedCount: run.adopted }));
  }

  async start(call) {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      await call();
      this.noticeMessage = helpText('Core', 'Core_NpspAdoption_Started');
      await this.load();
      this.poll();
    } catch (error) {
      this.errorMessage = bodyMessage(error);
    } finally {
      this.busy = false;
    }
  }
}
