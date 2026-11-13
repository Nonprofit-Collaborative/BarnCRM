import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPage from '@salesforce/apex/BackupSetController.getPage';
import setBackup from '@salesforce/apex/BackupSetController.setBackup';
import runNow from '@salesforce/apex/BackupSetController.runNow';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { format, messageFrom } from 'c/findCsv';
import { startPolling } from 'c/jobPoller';
import { tabPageReference } from 'c/barnTabs';

/**
 * The Backup Sets panel on Data Manager (C-66, canonical model R-SQ15, admin guide
 * backup-sets.md): the saved Find queries marked as Backup Sets, Run Now beside each, the
 * person's own saved queries to add, and their recent runs with each run's first file. A run
 * that is still saving is read again until it ends (c/jobPoller). Restoring is an import: the
 * panel links to Import and says which load to choose.
 */
export default class BackupSets extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');
  page;
  loading = true;
  busy = false;
  errorMessage;
  noticeMessage;
  chosen;
  stopTimer;

  get title() {
    return helpText('Core', 'Core_DataManager_BackupTitle');
  }

  get labels() {
    return {
      intro: helpText('Core', 'Core_BackupSets_Intro'),
      setsHeading: helpText('Core', 'Core_BackupSets_SetsHeading'),
      none: helpText('Core', 'Core_BackupSets_None'),
      addLabel: helpText('Core', 'Core_BackupSets_AddLabel'),
      addNone: helpText('Core', 'Core_BackupSets_AddNone'),
      add: helpText('Core', 'Core_BackupSets_Add'),
      run: helpText('Core', 'Core_BackupSets_Run'),
      remove: helpText('Core', 'Core_BackupSets_Remove'),
      runsHeading: helpText('Core', 'Core_BackupSets_RunsHeading'),
      runsNone: helpText('Core', 'Core_BackupSets_RunsNone'),
      restore: helpText('Core', 'Core_BackupSets_Restore'),
      openImport: helpText('Core', 'Core_BackupSets_OpenImport')
    };
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  async load() {
    this.loading = true;
    await this.act(() => getPage());
    this.loading = false;
  }

  /** Runs a server call that returns the page, showing its refusal when there is one. */
  async act(call, notice) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      this.page = await call();
      this.noticeMessage = notice;
      this.pollWhileRunning();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  get sets() {
    return (this.page && this.page.sets) || [];
  }

  get hasSets() {
    return this.sets.length > 0;
  }

  get candidateOptions() {
    return ((this.page && this.page.candidates) || []).map((query) => ({
      label: query.name,
      value: query.id
    }));
  }

  get hasCandidates() {
    return this.candidateOptions.length > 0;
  }

  get addDisabled() {
    return this.busy || !this.chosen;
  }

  get limitText() {
    return this.page ? format(helpText('Core', 'Core_BackupSets_Limit'), this.page.rowLimit) : '';
  }

  get runs() {
    return ((this.page && this.page.runs) || []).map((run) => ({
      ...run,
      fileUrl: run.fileId ? `/lightning/r/ContentDocument/${run.fileId}/view` : null,
      detail: run.rows === null || run.rows === undefined ? '' : String(run.rows)
    }));
  }

  get hasRuns() {
    return this.runs.length > 0;
  }

  get anyRunning() {
    return this.runs.some((run) => run.running);
  }

  pollWhileRunning() {
    if (this.stopTimer || !this.anyRunning) {
      return;
    }
    this.stopTimer = startPolling(
      async () => {
        this.page = await getPage();
        if (!this.anyRunning) {
          this.stopPolling();
          return true;
        }
        return false;
      },
      (error) => {
        this.stopPolling();
        this.errorMessage = messageFrom(error);
      }
    );
  }

  stopPolling() {
    if (this.stopTimer) {
      this.stopTimer();
      this.stopTimer = undefined;
    }
  }

  handleChoose(event) {
    this.chosen = event.detail.value;
  }

  handleAdd() {
    const queryId = this.chosen;
    this.chosen = undefined;
    return this.act(() => setBackup({ queryId, asSet: true }));
  }

  handleRemove(event) {
    return this.act(() => setBackup({ queryId: event.target.dataset.id, asSet: false }));
  }

  handleRun(event) {
    return this.act(
      () => runNow({ queryId: event.target.dataset.id }),
      helpText('Core', 'Core_BackupSets_Started')
    );
  }

  async handleOpenImport() {
    this[NavigationMixin.Navigate](await tabPageReference('Import'));
  }
}
