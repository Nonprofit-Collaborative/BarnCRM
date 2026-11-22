import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPage from '@salesforce/apex/BackupSetController.getPage';
import setBackup from '@salesforce/apex/BackupSetController.setBackup';
import runNow from '@salesforce/apex/BackupSetController.runNow';
import setSchedule from '@salesforce/apex/BackupSetController.setSchedule';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { format, messageFrom } from 'c/findCsv';
import { startPolling } from 'c/jobPoller';
import { tabPageReference } from 'c/barnTabs';

/**
 * The Backup Sets panel on Data Manager (C-66, canonical model R-SQ15, admin guide
 * backup-sets.md): the saved Find queries marked as Backup Sets, Run Now beside each, the
 * person's own saved queries to add, and their recent runs with each run's first file. The owner
 * of a set gives it a schedule (R-SQ16): off, daily, weekly on a weekday or monthly on a day from
 * 1 to 28, run by the nightly jobs. A run that is still saving is read again until it ends
 * (c/jobPoller). Restoring is an import: the panel links to Import and says which load to choose.
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
  /** The set whose schedule is being edited, and the schedule as edited so far. */
  editingId;
  draft = {};

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
      openImport: helpText('Core', 'Core_BackupSets_OpenImport'),
      editSchedule: helpText('Core', 'Core_BackupSets_EditSchedule'),
      frequency: helpText('Core', 'Core_BackupSets_Frequency'),
      weekday: helpText('Core', 'Core_BackupSets_Weekday'),
      dayOfMonth: helpText('Core', 'Core_BackupSets_DayOfMonth'),
      saveSchedule: helpText('Core', 'Core_BackupSets_SaveSchedule'),
      cancel: helpText('Core', 'Core_BackupSets_Cancel'),
      nightlyOff: helpText('Core', 'Core_BackupSets_NightlyOff')
    };
  }

  get frequencyOptions() {
    return [
      { label: helpText('Core', 'Core_BackupSets_FrequencyOff'), value: 'off' },
      { label: helpText('Core', 'Core_BackupSets_FrequencyDaily'), value: 'daily' },
      { label: helpText('Core', 'Core_BackupSets_FrequencyWeekly'), value: 'weekly' },
      { label: helpText('Core', 'Core_BackupSets_FrequencyMonthly'), value: 'monthly' }
    ];
  }

  /** Monday (1) to Sunday (7), named in the person's language: 1 January 2024 was a Monday. */
  get weekdayOptions() {
    return [1, 2, 3, 4, 5, 6, 7].map((day) => ({ label: weekdayName(day), value: String(day) }));
  }

  get dayOptions() {
    return Array.from({ length: 28 }, (unused, index) => ({ label: String(index + 1), value: String(index + 1) }));
  }

  get draftWeekly() {
    return this.draft.frequency === 'weekly';
  }

  get draftMonthly() {
    return this.draft.frequency === 'monthly';
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
    return ((this.page && this.page.sets) || []).map((set) => ({
      ...set,
      scheduleText: scheduleText(set),
      editing: set.id === this.editingId
    }));
  }

  get anyScheduled() {
    return this.sets.some((set) => set.frequency && set.frequency !== 'off');
  }

  get nightlyOff() {
    return Boolean(this.page) && this.page.nightlyOn === false;
  }

  get scheduleNote() {
    return this.page ? format(helpText('Core', 'Core_BackupSets_ScheduleNote'), this.page.runsKept) : '';
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

  handleEditSchedule(event) {
    const set = this.sets.find((candidate) => candidate.id === event.target.dataset.id);
    this.editingId = set.id;
    this.draft = {
      frequency: set.frequency || 'off',
      weekday: String(set.weekday || 1),
      day: String(set.day || 1)
    };
  }

  handleFrequency(event) {
    this.draft = { ...this.draft, frequency: event.detail.value };
  }

  handleWeekday(event) {
    this.draft = { ...this.draft, weekday: event.detail.value };
  }

  handleDay(event) {
    this.draft = { ...this.draft, day: event.detail.value };
  }

  handleCancelSchedule() {
    this.editingId = undefined;
  }

  async handleSaveSchedule() {
    const queryId = this.editingId;
    const { frequency, weekday, day } = this.draft;
    await this.act(
      () =>
        setSchedule({
          queryId,
          frequency,
          weekday: frequency === 'weekly' ? Number(weekday) : null,
          day: frequency === 'monthly' ? Number(day) : null
        }),
      helpText('Core', 'Core_BackupSets_ScheduleSaved')
    );
    if (!this.errorMessage) {
      this.editingId = undefined;
    }
  }

  async handleOpenImport() {
    this[NavigationMixin.Navigate](await tabPageReference('Import'));
  }
}

/** A weekday's name, 1 Monday to 7 Sunday, in the person's language. */
function weekdayName(day) {
  return new Intl.DateTimeFormat(undefined, { weekday: 'long', timeZone: 'UTC' }).format(
    new Date(Date.UTC(2024, 0, day))
  );
}

/** What a set's schedule reads as beside its name. */
function scheduleText(set) {
  if (set.frequency === 'daily') {
    return helpText('Core', 'Core_BackupSets_FrequencyDaily');
  }
  if (set.frequency === 'weekly') {
    return format(helpText('Core', 'Core_BackupSets_WeeklyOn'), weekdayName(set.weekday));
  }
  if (set.frequency === 'monthly') {
    return format(helpText('Core', 'Core_BackupSets_MonthlyOn'), set.day);
  }
  return helpText('Core', 'Core_BackupSets_FrequencyOff');
}
