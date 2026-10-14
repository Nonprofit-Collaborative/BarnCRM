import { LightningElement, api } from 'lwc';
import getTargets from '@salesforce/apex/BulkUpdateController.getTargets';
import getCopySources from '@salesforce/apex/BulkUpdateController.getCopySources';
import previewUpdate from '@salesforce/apex/BulkUpdateController.preview';
import startUpdate from '@salesforce/apex/BulkUpdateController.start';
import getJob from '@salesforce/apex/BulkUpdateController.getJob';
import { startPolling } from 'c/jobPoller';

import TITLE from '@salesforce/label/c.Core_BulkUpdate_Title';
import PANEL_INTRO from '@salesforce/label/c.Core_BulkUpdate_PanelIntro';
import CHANGES from '@salesforce/label/c.Core_BulkUpdate_Changes';
import FIELD from '@salesforce/label/c.Core_BulkUpdate_Field';
import CHOOSE_FIELD from '@salesforce/label/c.Core_BulkUpdate_ChooseField';
import ACTION from '@salesforce/label/c.Core_BulkUpdate_Action';
import ACTION_SET from '@salesforce/label/c.Core_BulkUpdate_ActionSet';
import ACTION_CLEAR from '@salesforce/label/c.Core_BulkUpdate_ActionClear';
import ACTION_COPY from '@salesforce/label/c.Core_BulkUpdate_ActionCopy';
import ACTION_TRANSFORM from '@salesforce/label/c.Core_BulkUpdate_ActionTransform';
import NEW_VALUE from '@salesforce/label/c.Core_BulkUpdate_NewValue';
import COPY_FROM from '@salesforce/label/c.Core_BulkUpdate_CopyFrom';
import REMOVE from '@salesforce/label/c.Core_BulkUpdate_Remove';
import ADD_CHANGE from '@salesforce/label/c.Core_BulkUpdate_AddChange';
import PREVIEW from '@salesforce/label/c.Core_BulkUpdate_Preview';
import PREVIEW_COUNT from '@salesforce/label/c.Core_BulkUpdate_PreviewCount';
import RECORD from '@salesforce/label/c.Core_BulkUpdate_Record';
import BEFORE from '@salesforce/label/c.Core_BulkUpdate_Before';
import AFTER from '@salesforce/label/c.Core_BulkUpdate_After';
import CONFIRM from '@salesforce/label/c.Core_BulkUpdate_Confirm';
import UPDATE_BUTTON from '@salesforce/label/c.Core_BulkUpdate_UpdateButton';
import STARTED from '@salesforce/label/c.Core_BulkUpdate_Started';
import PROGRESS from '@salesforce/label/c.Core_BulkUpdate_Progress';
import SUMMARY from '@salesforce/label/c.Core_BulkUpdate_Summary';
import FAILURES from '@salesforce/label/c.Core_BulkUpdate_Failures';
import UNDO_FROM_TAB from '@salesforce/label/c.Core_BulkUpdate_UndoFromTab';
import CLOSE from '@salesforce/label/c.Core_BulkUpdate_Close';
import LOADING from '@salesforce/label/c.Core_BulkUpdate_Loading';
import TRUE_LABEL from '@salesforce/label/c.Core_BulkUpdate_True';
import FALSE_LABEL from '@salesforce/label/c.Core_BulkUpdate_False';

// BulkUpdateService.MAX_CHANGES. The server refuses more; this only disables Add change.
const MAX_CHANGES = 5;
const NUMBER_TYPES = new Set(['integer', 'double', 'currency', 'percent']);
const INPUT_TYPES = {
  email: 'email',
  phone: 'tel',
  url: 'url',
  date: 'date',
  datetime: 'datetime'
};

function format(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

function shown(value) {
  return value === null || value === undefined ? '' : String(value);
}

/**
 * Bulk update (C-35, admin guide bulk-update.md): up to five changes to every record a Find
 * query returns, previewed, confirmed by typing the count, run in the background with its
 * progress.
 *
 * Find opens it over the query it just ran (`queryJson`). The page sends only the query document
 * and the changes: BulkUpdateController checks both as the person, from describe, and never takes
 * SOQL (canonical model R-BU1, R-BU4). Undo is in Data jobs on the Data Manager tab (dataJobHistory).
 */
export default class BulkUpdate extends LightningElement {
  @api queryJson;

  labels = {
    title: TITLE,
    panelIntro: PANEL_INTRO,
    changes: CHANGES,
    field: FIELD,
    chooseField: CHOOSE_FIELD,
    action: ACTION,
    newValue: NEW_VALUE,
    copyFrom: COPY_FROM,
    remove: REMOVE,
    addChange: ADD_CHANGE,
    preview: PREVIEW,
    record: RECORD,
    before: BEFORE,
    after: AFTER,
    confirm: CONFIRM,
    failures: FAILURES,
    undoFromTab: UNDO_FROM_TAB,
    close: CLOSE,
    loading: LOADING
  };

  targets = [];
  changes = [];
  preview;
  confirmText = '';
  job;
  busy = false;
  errorMessage;
  noticeMessage;
  nextKey = 1;
  stopTimer;

  connectedCallback() {
    this.load();
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  async load() {
    await this.work(async () => {
      this.targets = await getTargets({ objectName: JSON.parse(this.queryJson).object });
      this.changes = [this.newChange()];
    });
  }

  /* ---------- what the template reads ---------- */

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get hasNotice() {
    return Boolean(this.noticeMessage);
  }

  get fieldOptions() {
    return this.targets.map((target) => ({ label: target.label, value: target.apiName }));
  }

  get changeRows() {
    return this.changes.map((change) => {
      const target = this.targetOf(change.field);
      const type = target ? target.dataType : undefined;
      const isSet = change.action === 'set';
      const hasPicklist = Boolean(target && target.picklistValues && target.picklistValues.length);
      const isBoolean = isSet && type === 'boolean';
      const isMulti = isSet && type === 'multipicklist' && hasPicklist;
      const isPicklist = isSet && !isMulti && hasPicklist;
      const isRecord = isSet && type === 'reference' && Boolean(target.referenceTo);
      return {
        ...change,
        hasField: Boolean(target),
        actionOptions: [
          { label: ACTION_SET, value: 'set' },
          ...(target && target.nillable ? [{ label: ACTION_CLEAR, value: 'clear' }] : []),
          { label: ACTION_COPY, value: 'copy' },
          ...(target && type !== 'reference'
            ? [{ label: ACTION_TRANSFORM, value: 'transform' }]
            : [])
        ],
        isBoolean,
        isMulti,
        isPicklist,
        isRecord,
        isInput: isSet && !isBoolean && !isMulti && !isPicklist && !isRecord,
        isCopy: change.action === 'copy',
        isTransform: change.action === 'transform',
        stepList: change.transforms || [],
        inputType: NUMBER_TYPES.has(type) ? 'number' : INPUT_TYPES[type] || 'text',
        referenceTo: target ? target.referenceTo : undefined,
        picklistOptions: target ? target.picklistValues : [],
        multiValue: change.value ? String(change.value).split(';') : [],
        booleanOptions: [
          { label: TRUE_LABEL, value: 'true' },
          { label: FALSE_LABEL, value: 'false' }
        ],
        sourceOptions: change.sources || []
      };
    });
  }

  get addDisabled() {
    return this.busy || this.changes.length >= MAX_CHANGES;
  }

  get previewDisabled() {
    return this.busy || !this.changes.some((change) => change.field);
  }

  get previewLine() {
    return this.preview ? format(PREVIEW_COUNT, this.preview.count) : '';
  }

  get sampleRows() {
    const rows = [];
    for (const record of (this.preview && this.preview.sample) || []) {
      record.changes.forEach((change, index) => {
        rows.push({
          key: `${record.recordId}-${index}`,
          name: record.name,
          label: change.label,
          before: shown(change.before),
          after: change.problem ? change.problem : shown(change.after),
          afterClass: change.problem ? 'slds-text-color_error' : ''
        });
      });
    }
    return rows;
  }

  get updateLabel() {
    return this.preview ? format(UPDATE_BUTTON, this.preview.count) : '';
  }

  get startDisabled() {
    return (
      this.busy || !this.preview || String(this.confirmText).trim() !== String(this.preview.count)
    );
  }

  get jobView() {
    return this.job ? this.decorate(this.job) : undefined;
  }

  decorate(job) {
    const total = job.chunksTotal || 0;
    return {
      ...job,
      summary: format(SUMMARY, job.matched, job.updated, job.unchanged, job.failed),
      progressLine: job.running ? format(PROGRESS, job.chunksDone || 0, total) : '',
      progressValue: total ? Math.round(((job.chunksDone || 0) * 100) / total) : 0,
      hasFailures: Boolean(job.failures && job.failures.length),
      showUndo: Boolean(job.canUndo && !job.running)
    };
  }

  targetOf(fieldName) {
    return this.targets.find((target) => target.apiName === fieldName);
  }

  /* ---------- changes ---------- */

  newChange() {
    const key = this.nextKey;
    this.nextKey += 1;
    return { key: String(key), field: undefined, action: 'set', value: '', source: undefined };
  }

  handleAddChange() {
    this.changes = [...this.changes, this.newChange()];
    this.invalidate();
  }

  handleRemoveChange(event) {
    const key = event.currentTarget.dataset.key;
    this.changes = this.changes.filter((change) => change.key !== key);
    this.invalidate();
  }

  async handleChangeEdit(event) {
    const key = event.currentTarget.dataset.key;
    const part = event.currentTarget.dataset.part;
    let value = event.detail.value;
    if (part === 'record') {
      value = event.detail.recordId;
    } else if (Array.isArray(value)) {
      value = value.join(';');
    }
    const fresh = part === 'field';
    this.changes = this.changes.map((change) => {
      if (change.key !== key) {
        return change;
      }
      if (fresh) {
        return {
          ...change,
          field: value,
          action: 'set',
          value: '',
          source: undefined,
          sources: undefined,
          transforms: undefined
        };
      }
      return { ...change, [part === 'record' ? 'value' : part]: value };
    });
    this.invalidate();
    const edited = this.changes.find((change) => change.key === key);
    if (edited && (edited.action === 'copy' || edited.action === 'transform') && !edited.sources) {
      await this.loadSources(edited);
    }
  }

  /** A change with steps (C-37): the steps as the step editor last sent them. */
  handleStepsChange(event) {
    const key = event.currentTarget.dataset.key;
    const transforms = event.detail.transforms;
    this.changes = this.changes.map((change) => {
      return change.key === key ? { ...change, transforms } : change;
    });
    this.invalidate();
  }

  async loadSources(change) {
    await this.work(async () => {
      const sources = await getCopySources({
        objectName: JSON.parse(this.queryJson).object,
        fieldName: change.field
      });
      this.changes = this.changes.map((each) => {
        return each.key === change.key ? { ...each, sources } : each;
      });
    });
  }

  changesJson() {
    return JSON.stringify(
      this.changes
        .filter((change) => change.field)
        .map((change) => {
          const entry = { field: change.field, action: change.action };
          if (change.action === 'set') {
            entry.value = change.value;
          }
          if (change.action === 'copy') {
            entry.source = change.source;
          }
          if (change.action === 'transform') {
            entry.transforms = change.transforms || [];
          }
          return entry;
        })
    );
  }

  invalidate() {
    this.preview = undefined;
    this.confirmText = '';
  }

  /* ---------- preview and start ---------- */

  async handlePreview() {
    this.noticeMessage = undefined;
    this.invalidate();
    await this.work(async () => {
      this.preview = await previewUpdate({
        queryJson: this.queryJson,
        changesJson: this.changesJson()
      });
    });
  }

  handleConfirmText(event) {
    this.confirmText = event.detail.value;
  }

  async handleStart() {
    await this.work(async () => {
      this.job = await startUpdate({
        queryJson: this.queryJson,
        changesJson: this.changesJson(),
        confirmedCount: this.preview.count
      });
      this.noticeMessage = STARTED;
      this.invalidate();
      this.startPolling();
    });
  }

  /** Slows down after the first minute and retries once on an error (c/jobPoller, FINDB-19). */
  startPolling() {
    this.stopPolling();
    this.stopTimer = startPolling(
      () => this.poll(),
      (error) => {
        this.errorMessage = this.messageFrom(error);
      }
    );
  }

  stopPolling() {
    if (this.stopTimer) {
      this.stopTimer();
      this.stopTimer = undefined;
    }
  }

  /** One read of the job; true once it has finished. */
  async poll() {
    this.job = await getJob({ jobId: this.job.recordId });
    if (!this.job.running) {
      this.stopPolling();
      this.noticeMessage = undefined;
      return true;
    }
    return false;
  }

  handleClose() {
    this.stopPolling();
    this.dispatchEvent(new CustomEvent('close'));
  }

  /* ---------- plumbing ---------- */

  async work(action) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return error && error.message ? error.message : String(error);
  }
}
