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

/** The source key of Nonprofit Cloud households (R-HA7); anything else is NPSP. */
const NPC = 'NPC';

/** The NPSP panel's words. */
const NPSP_LABELS = {
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
  get keepNamesHelp() {
    return helpText('Core', 'Core_NpspAdoption_KeepNamesHelp');
  },
  get candidateCount() {
    return helpText('Core', 'Core_NpspAdoption_CandidateCount');
  },
  get confirmMessage() {
    return helpText('Core', 'Core_NpspAdoption_ConfirmMessage');
  },
  get undoMessage() {
    return helpText('Core', 'Core_NpspAdoption_UndoMessage');
  },
  get lastRunCounts() {
    return helpText('Core', 'Core_NpspAdoption_LastRunCounts');
  },
  sampleCaption: SAMPLE_CAPTION,
  keepNames: KEEP_NAMES,
  adoptButton: ADOPT_BUTTON,
  typeToAdopt: TYPE_TO_ADOPT,
  confirmAdopt: CONFIRM_ADOPT,
  lastRun: LAST_RUN,
  undoButton: UNDO_BUTTON
};

/** The same panel converting Nonprofit Cloud households (MIG-02b): its own words only. */
const NPC_LABELS = {
  get title() {
    return helpText('Core', 'Core_NpcConversion_Title');
  },
  get intro() {
    return helpText('Core', 'Core_NpcConversion_Intro');
  },
  get notAvailable() {
    return helpText('Core', 'Core_NpcConversion_NotAvailable');
  },
  get noneLeft() {
    return helpText('Core', 'Core_NpcConversion_NoneLeft');
  },
  get keepNamesHelp() {
    return helpText('Core', 'Core_NpcConversion_KeepNamesHelp');
  },
  get candidateCount() {
    return helpText('Core', 'Core_NpcConversion_CandidateCount');
  },
  get confirmMessage() {
    return helpText('Core', 'Core_NpcConversion_ConfirmMessage');
  },
  get undoMessage() {
    return helpText('Core', 'Core_NpcConversion_UndoMessage');
  },
  get lastRunCounts() {
    return helpText('Core', 'Core_NpcConversion_LastRunCounts');
  },
  get sampleCaption() {
    return helpText('Core', 'Core_NpcConversion_SampleCaption');
  },
  get keepNames() {
    return helpText('Core', 'Core_NpcConversion_KeepNames');
  },
  get adoptButton() {
    return helpText('Core', 'Core_NpcConversion_ConvertButton');
  },
  get typeToAdopt() {
    return helpText('Core', 'Core_NpcConversion_TypeToConvert');
  },
  get confirmAdopt() {
    return helpText('Core', 'Core_NpcConversion_ConfirmConvert');
  },
  get lastRun() {
    return helpText('Core', 'Core_NpcConversion_LastRun');
  },
  get undoButton() {
    return helpText('Core', 'Core_NpcConversion_UndoButton');
  }
};

/**
 * Adopt NPSP Households, on the General page of BarnCRM Settings (X-05, admin guide
 * npsp-households.md), and, with `source` NPC, Convert Nonprofit Cloud Households (MIG-02b,
 * admin guide nonprofit-cloud-households.md, placed by `npcHouseholdConversion`). The settings
 * console shows each row only where its product applies and only to holders of Manage BarnCRM
 * Settings; the controller checks the permission again on every call.
 *
 * It shows what would be adopted, starts a run after the person types the count, polls while a
 * run or an undo is going, and offers the undo of the newest run. Every rule lives in Apex.
 */
export default class NpspHouseholdAdoption extends LightningElement {
  helpReady = isHelpLoaded('Core');

  /** NPSP (the default) or NPC. */
  @api source;

  get isNpc() {
    return this.source === NPC;
  }

  /** NPC households have no greetings, so their sample leaves those columns out. */
  get showGreetings() {
    return !this.isNpc;
  }

  get labels() {
    const words = this.isNpc ? NPC_LABELS : NPSP_LABELS;
    return {
      title: words.title,
      intro: words.intro,
      notAvailable: words.notAvailable,
      noneLeft: words.noneLeft,
      sampleCaption: words.sampleCaption,
      columnName: COLUMN_NAME,
      columnFormal: COLUMN_FORMAL,
      columnInformal: COLUMN_INFORMAL,
      columnPrimary: COLUMN_PRIMARY,
      columnContacts: COLUMN_CONTACTS,
      keepNames: words.keepNames,
      keepNamesHelp: words.keepNamesHelp,
      adoptButton: words.adoptButton,
      running: helpText('Core', 'Core_NpspAdoption_Running'),
      lastRun: words.lastRun,
      undoButton: words.undoButton,
      refresh: REFRESH
    };
  }

  get words() {
    return this.isNpc ? NPC_LABELS : NPSP_LABELS;
  }

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
      this.status = await getStatus({ source: this.source });
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
        this.status = await getStatus({ source: this.source });
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
    return format(this.words.candidateCount, this.runCount.toLocaleString());
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
      ? format(this.words.lastRunCounts, run.adopted, run.undone, run.notRestored)
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
      label: this.words.title,
      message: format(this.words.confirmMessage, count.toLocaleString()),
      typeToConfirm: String(count),
      typeToConfirmLabel: format(this.words.typeToAdopt, count),
      confirmLabel: this.words.confirmAdopt,
      cancelLabel: CANCEL
    });
    if (!confirmed) {
      return;
    }
    await this.start(() =>
      adopt({ source: this.source, keepNames: this.keepNames, confirmedCount: count })
    );
  }

  async handleUndo() {
    const run = this.lastRun;
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: this.words.undoButton,
      message: format(this.words.undoMessage, run.adopted.toLocaleString()),
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
