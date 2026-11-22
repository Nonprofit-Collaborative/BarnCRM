import { LightningElement } from 'lwc';
import getRules from '@salesforce/apex/ArchiveController.getRules';
import saveRule from '@salesforce/apex/ArchiveController.saveRule';
import previewRule from '@salesforce/apex/ArchiveController.previewRule';
import runRule from '@salesforce/apex/ArchiveController.runRule';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { format, messageFrom } from 'c/findCsv';
import { startPolling } from 'c/jobPoller';

const FREQUENCIES = ['off', 'daily', 'weekly', 'monthly'];
const WEEKDAYS = [1, 2, 3, 4, 5, 6, 7];

/**
 * The Archive Rules panel on Data Manager (D-221, canonical model R-SQ18, admin guide
 * archive-rules.md): saved Find queries that move their records to Files, the big object or an
 * off-platform store, now or on a schedule. Each rule shows where it sends records and when it
 * runs; Preview and Run is the bulk delete preview with the typed count; turning a schedule on
 * asks for the same count once. The big object's use against the one million rows included is
 * shown, with a warning near the cap. Runs still going are read again until they end.
 */
export default class ArchiveRules extends LightningElement {
  helpReady = isHelpLoaded('Core');
  page;
  loading = true;
  busy = false;
  errorMessage;
  noticeMessage;
  chosen;
  editing;
  scheduledBefore = false;
  preview;
  typedCount;
  scheduleCount;
  stopTimer;

  get labels() {
    return {
      title: helpText('Core', 'Core_ArchiveRules_Title'),
      intro: helpText('Core', 'Core_ArchiveRules_Intro'),
      usage: helpText('Core', 'Core_ArchiveRules_Usage'),
      rulesHeading: helpText('Core', 'Core_ArchiveRules_RulesHeading'),
      none: helpText('Core', 'Core_ArchiveRules_None'),
      addLabel: helpText('Core', 'Core_ArchiveRules_AddLabel'),
      addNone: helpText('Core', 'Core_ArchiveRules_AddNone'),
      add: helpText('Core', 'Core_BackupSets_Add'),
      edit: helpText('Core', 'Core_ArchiveRules_Edit'),
      remove: helpText('Core', 'Core_BackupSets_Remove'),
      previewRun: helpText('Core', 'Core_ArchiveRules_PreviewRun'),
      destination: helpText('Core', 'Core_ArchiveRules_Destination'),
      frequency: helpText('Core', 'Core_ArchiveRules_Frequency'),
      weekday: helpText('Core', 'Core_ArchiveRules_Weekday'),
      monthDay: helpText('Core', 'Core_ArchiveRules_MonthDay'),
      active: helpText('Core', 'Core_ArchiveRules_Active'),
      typedCount: helpText('Core', 'Core_ArchiveRules_TypedCount'),
      save: helpText('Core', 'Core_ArchiveRules_Save'),
      cancel: helpText('Core', 'Core_ArchiveRules_Cancel'),
      runNow: helpText('Core', 'Core_ArchiveRules_RunNow'),
      runsHeading: helpText('Core', 'Core_ArchiveRules_RunsHeading'),
      runsNone: helpText('Core', 'Core_ArchiveRules_RunsNone'),
      log: helpText('Core', 'Core_ArchiveRules_Log')
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
    await this.act(() => getRules());
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
      return true;
    } catch (error) {
      this.errorMessage = messageFrom(error);
      return false;
    } finally {
      this.busy = false;
    }
  }

  get usage() {
    const count = (this.page && this.page.archivedCount) || 0;
    const cap = (this.page && this.page.cap) || 1;
    const warnAt = (this.page && this.page.warnAt) || cap;
    return {
      percent: Math.min(100, Math.round((count * 100) / cap)),
      text: format(helpText('Core', 'Core_ArchiveRules_UsageText'), count.toLocaleString(), cap.toLocaleString()),
      near: count >= warnAt,
      warning: format(helpText('Core', 'Core_ArchiveRules_NearCap'), cap.toLocaleString())
    };
  }

  scheduleText(rule) {
    if (!rule || rule.frequency === 'off') {
      return helpText('Core', 'Core_ArchiveRules_ScheduleOff');
    }
    let when = helpText('Core', 'Core_ArchiveRules_FrequencyDaily');
    if (rule.frequency === 'weekly') {
      when = format(helpText('Core', 'Core_ArchiveRules_ScheduleWeekly'), this.weekdayName(rule.weekday));
    } else if (rule.frequency === 'monthly') {
      when = format(helpText('Core', 'Core_ArchiveRules_ScheduleMonthly'), rule.monthDay);
    }
    return rule.active ? when : format(helpText('Core', 'Core_ArchiveRules_ScheduleInactive'), when);
  }

  weekdayName(day) {
    // 2024-01-01 was a Monday, so day 1 is Monday.
    return new Date(Date.UTC(2024, 0, day, 12)).toLocaleDateString(undefined, { weekday: 'long', timeZone: 'UTC' });
  }

  get rules() {
    return ((this.page && this.page.rules) || []).map((rule) => ({
      ...rule,
      scheduleText: this.scheduleText(rule.rule)
    }));
  }

  get hasRules() {
    return this.rules.length > 0;
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

  get destinationOptions() {
    return ((this.page && this.page.destinations) || []).map((choice) => ({
      label: choice.label,
      value: choice.key
    }));
  }

  get destinationReason() {
    const choice = ((this.page && this.page.destinations) || []).find(
      (one) => this.editing && one.key === this.editing.rule.destination
    );
    return choice ? choice.unavailableReason : null;
  }

  get frequencyOptions() {
    const labels = {
      off: helpText('Core', 'Core_ArchiveRules_FrequencyOff'),
      daily: helpText('Core', 'Core_ArchiveRules_FrequencyDaily'),
      weekly: helpText('Core', 'Core_ArchiveRules_FrequencyWeekly'),
      monthly: helpText('Core', 'Core_ArchiveRules_FrequencyMonthly')
    };
    return FREQUENCIES.map((value) => ({ label: labels[value], value }));
  }

  get weekdayOptions() {
    return WEEKDAYS.map((day) => ({ label: this.weekdayName(day), value: String(day) }));
  }

  get isWeekly() {
    return this.editing && this.editing.rule.frequency === 'weekly';
  }

  get isMonthly() {
    return this.editing && this.editing.rule.frequency === 'monthly';
  }

  get needsScheduleCount() {
    const rule = this.editing && this.editing.rule;
    return Boolean(rule && rule.active && rule.frequency !== 'off' && !this.scheduledBefore);
  }

  get scheduleConfirmText() {
    return this.scheduleCount === undefined
      ? ''
      : format(helpText('Core', 'Core_ArchiveRules_ScheduleConfirm'), this.scheduleCount);
  }

  /** The count a schedule is turned on with, read once per editor while it is needed. */
  async loadScheduleCount() {
    if (!this.needsScheduleCount || this.scheduleCount !== undefined) {
      return;
    }
    try {
      const shown = await previewRule({ queryId: this.editing.id });
      this.scheduleCount = shown.count;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  get runDisabled() {
    return this.busy || !this.typedCount;
  }

  get runs() {
    return ((this.page && this.page.runs) || []).map((run) => ({
      ...run,
      detail: format(helpText('Core', 'Core_ArchiveRules_RunDetail'), run.moved || 0, run.leftOut || 0)
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
        this.page = await getRules();
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

  /** Opens the editor for a query that is not a rule yet: Files, no schedule. */
  handleAdd() {
    const query = ((this.page && this.page.candidates) || []).find((one) => one.id === this.chosen);
    this.chosen = undefined;
    if (query) {
      this.openEditor(query, { destination: 'Files', frequency: 'off', active: true });
    }
  }

  handleEdit(event) {
    const rule = this.rules.find((one) => one.id === event.target.dataset.id);
    if (rule) {
      this.openEditor(rule, { ...rule.rule });
    }
  }

  openEditor(query, rule) {
    this.preview = undefined;
    this.typedCount = undefined;
    this.scheduleCount = undefined;
    this.scheduledBefore =Boolean(rule.active && rule.frequency && rule.frequency !== 'off' && query.rule);
    this.editing = {
      id: query.id,
      name: query.name,
      rule,
      weekdayText: rule.weekday ? String(rule.weekday) : undefined
    };
  }

  handleRuleChange(event) {
    const field = event.target.dataset.field;
    let value = event.detail.value;
    if (field === 'active') {
      value = event.detail.checked;
    } else if (field === 'weekday' || field === 'monthDay') {
      value = value ? Number.parseInt(value, 10) : null;
    }
    const rule = { ...this.editing.rule, [field]: value };
    this.editing = {
      ...this.editing,
      rule,
      weekdayText: rule.weekday ? String(rule.weekday) : undefined
    };
    this.loadScheduleCount();
  }

  handleTyped(event) {
    const value = Number.parseInt(event.detail.value, 10);
    this.typedCount = Number.isNaN(value) ? undefined : value;
  }

  handleCancel() {
    this.editing = undefined;
    this.preview = undefined;
    this.typedCount = undefined;
  }

  async handleSave() {
    const saved = await this.act(
      () =>
        saveRule({
          queryId: this.editing.id,
          ruleJson: JSON.stringify(this.editing.rule),
          confirmedCount: this.needsScheduleCount ? this.typedCount : null
        }),
      helpText('Core', 'Core_ArchiveRules_Saved')
    );
    if (saved) {
      this.handleCancel();
    }
  }

  handleRemove(event) {
    return this.act(() => saveRule({ queryId: event.target.dataset.id, ruleJson: null, confirmedCount: null }));
  }

  async handlePreview(event) {
    const rule = this.rules.find((one) => one.id === event.target.dataset.id);
    this.editing = undefined;
    this.typedCount = undefined;
    this.busy = true;
    this.errorMessage = undefined;
    try {
      const shown = await previewRule({ queryId: rule.id });
      const sample = shown.sample || [];
      const cascades = shown.cascades || [];
      this.preview = {
        ruleId: rule.id,
        ruleName: rule.name,
        countText: format(helpText('Core', 'Core_ArchiveRules_PreviewCount'), shown.count, shown.objectLabel),
        whereText: format(helpText('Core', 'Core_ArchiveRules_PreviewWhere'), rule.destinationLabel),
        sample,
        hasSample: sample.length > 0,
        cascades,
        hasCascades: cascades.length > 0,
        cascadeText: format(helpText('Core', 'Core_ArchiveRules_PreviewChildren'), cascades.join(', '))
      };
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  async handleRun() {
    const ran = await this.act(
      () => runRule({ queryId: this.preview.ruleId, confirmedCount: this.typedCount }),
      helpText('Core', 'Core_ArchiveRules_Started')
    );
    if (ran) {
      this.handleCancel();
    }
  }
}
