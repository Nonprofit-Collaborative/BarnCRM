import { LightningElement } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import { startPolling } from 'c/jobPoller';
import getPage from '@salesforce/apex/BulkUpdateController.getPage';
import getObjects from '@salesforce/apex/BulkUpdateController.getObjects';
import getTargets from '@salesforce/apex/BulkUpdateController.getTargets';
import getCopySources from '@salesforce/apex/BulkUpdateController.getCopySources';
import countMatches from '@salesforce/apex/BulkUpdateController.countMatches';
import previewSample from '@salesforce/apex/BulkUpdateController.previewSample';
import startUpdate from '@salesforce/apex/BulkUpdateController.start';
import getJob from '@salesforce/apex/BulkUpdateController.getJob';
import getSavedLists from '@salesforce/apex/BulkUpdateController.getSavedLists';
import loadSavedList from '@salesforce/apex/BulkUpdateController.loadSavedList';
import saveSavedList from '@salesforce/apex/BulkUpdateController.saveSavedList';
import renameSavedList from '@salesforce/apex/BulkUpdateController.renameSavedList';
import deleteSavedList from '@salesforce/apex/BulkUpdateController.deleteSavedList';
import { PHONE_PRESET_STEPS } from 'c/transformFormat';

import NO_PERMISSION from '@salesforce/label/c.Core_BulkUpdate_ErrorNoPermission';
import RECORD from '@salesforce/label/c.Core_BulkUpdate_Record';
import REMOVE from '@salesforce/label/c.Core_BulkUpdate_Remove';
import STARTED from '@salesforce/label/c.Core_BulkUpdate_Started';
import PROGRESS from '@salesforce/label/c.Core_BulkUpdate_Progress';
import SUMMARY from '@salesforce/label/c.Core_BulkUpdate_Summary';
import FAILURES from '@salesforce/label/c.Core_BulkUpdate_Failures';
import LOADING from '@salesforce/label/c.Core_BulkUpdate_Loading';
import TRUE_LABEL from '@salesforce/label/c.Core_BulkUpdate_True';
import FALSE_LABEL from '@salesforce/label/c.Core_BulkUpdate_False';
import TITLE from '@salesforce/label/c.Core_SuperTransform_Title';
import INTRO from '@salesforce/label/c.Core_SuperTransform_Intro';
import STEP_OBJECT from '@salesforce/label/c.Core_SuperTransform_StepObject';
import STEP_RECORDS from '@salesforce/label/c.Core_SuperTransform_StepRecords';
import STEP_CHANGES from '@salesforce/label/c.Core_SuperTransform_StepChanges';
import STEP_PREVIEW from '@salesforce/label/c.Core_SuperTransform_StepPreview';
import STEP_RUN from '@salesforce/label/c.Core_SuperTransform_StepRun';
import SEARCH_OBJECTS from '@salesforce/label/c.Core_SuperTransform_SearchObjects';
import OBJECT from '@salesforce/label/c.Core_SuperTransform_Object';
import CHOOSE_OBJECT from '@salesforce/label/c.Core_SuperTransform_ChooseObject';
import NO_OBJECTS from '@salesforce/label/c.Core_SuperTransform_NoObjects';
import OBJECT_FIRST from '@salesforce/label/c.Core_SuperTransform_ObjectFirst';
import COUNTING from '@salesforce/label/c.Core_SuperTransform_Counting';
import MATCH_COUNT from '@salesforce/label/c.Core_SuperTransform_MatchCount';
import NONE_MATCH from '@salesforce/label/c.Core_SuperTransform_NoneMatch';
import NO_FILTER from '@salesforce/label/c.Core_SuperTransform_NoFilter';
import OVER_LIMIT from '@salesforce/label/c.Core_SuperTransform_OverLimit';
import TOO_MANY from '@salesforce/label/c.Core_SuperTransform_TooManyToCount';
import FIX_CONDITIONS from '@salesforce/label/c.Core_SuperTransform_FixConditions';
import FIELD from '@salesforce/label/c.Core_SuperTransform_Field';
import CHOOSE_FIELD from '@salesforce/label/c.Core_SuperTransform_ChooseField';
import ACTION from '@salesforce/label/c.Core_SuperTransform_Action';
import ACTION_SET from '@salesforce/label/c.Core_SuperTransform_ActionSet';
import ACTION_CLEAR from '@salesforce/label/c.Core_SuperTransform_ActionClear';
import ACTION_COPY from '@salesforce/label/c.Core_SuperTransform_ActionCopy';
import ACTION_TRANSFORM from '@salesforce/label/c.Core_SuperTransform_ActionTransform';
import NEW_VALUE from '@salesforce/label/c.Core_SuperTransform_NewValue';
import COPY_FROM from '@salesforce/label/c.Core_SuperTransform_CopyFrom';
import ADD_FIELD from '@salesforce/label/c.Core_SuperTransform_AddField';
import FIELD_LIMIT from '@salesforce/label/c.Core_SuperTransform_FieldLimit';
import PREVIEW from '@salesforce/label/c.Core_SuperTransform_Preview';
import PREVIEW_HINT from '@salesforce/label/c.Core_SuperTransform_PreviewHint';
import PREVIEW_COUNT from '@salesforce/label/c.Core_SuperTransform_PreviewCount';
import ALREADY_HELD from '@salesforce/label/c.Core_SuperTransform_AlreadyHeld';
import CHANGES_TO from '@salesforce/label/c.Core_SuperTransform_ChangesTo';
import NO_CHANGE from '@salesforce/label/c.Core_SuperTransform_NoChange';
import BLANK from '@salesforce/label/c.Core_SuperTransform_Blank';
import RUN from '@salesforce/label/c.Core_SuperTransform_Run';
import RUN_HINT from '@salesforce/label/c.Core_SuperTransform_RunHint';
import CONFIRM_MESSAGE from '@salesforce/label/c.Core_SuperTransform_ConfirmMessage';
import CONFIRM_DETAIL from '@salesforce/label/c.Core_SuperTransform_ConfirmDetail';
import CONFIRM_BUTTON from '@salesforce/label/c.Core_SuperTransform_ConfirmButton';
import CANCEL from '@salesforce/label/c.Core_SuperTransform_Cancel';
import TYPE_TO_CONFIRM from '@salesforce/label/c.Core_SuperTransform_TypeToConfirm';
import UNDO_HINT from '@salesforce/label/c.Core_SuperTransform_UndoHint';
import START_ANOTHER from '@salesforce/label/c.Core_SuperTransform_StartAnother';
import HELP from '@salesforce/label/c.Core_SuperTransform_Help';
import NO_PERMISSION_HEADING from '@salesforce/label/c.Core_SuperTransform_NoPermissionHeading';
import NO_OBJECTS_HEADING from '@salesforce/label/c.Core_SuperTransform_NoObjectsHeading';
import MATCHING from '@salesforce/label/c.Core_SuperTransform_Matching';
import BADGE_EVERY from '@salesforce/label/c.Core_SuperTransform_BadgeEvery';
import BADGE_OVER from '@salesforce/label/c.Core_SuperTransform_BadgeOver';
import ACTION_NAME_CASE from '@salesforce/label/c.Core_SuperTransform_ActionNameCase';
import ACTION_PHONE_FORMAT from '@salesforce/label/c.Core_SuperTransform_ActionPhoneFormat';
import SAVED_HEADING from '@salesforce/label/c.Core_SuperTransform_SavedHeading';
import SAVED_HELP from '@salesforce/label/c.Core_SuperTransform_SavedHelp';
import SAVED_CHOOSE from '@salesforce/label/c.Core_SuperTransform_SavedChoose';
import SAVED_PLACEHOLDER from '@salesforce/label/c.Core_SuperTransform_SavedPlaceholder';
import SAVED_NONE from '@salesforce/label/c.Core_SuperTransform_SavedNone';
import SAVED_OPTION from '@salesforce/label/c.Core_SuperTransform_SavedOption';
import SAVED_LOAD from '@salesforce/label/c.Core_SuperTransform_SavedLoad';
import SAVED_NAME from '@salesforce/label/c.Core_SuperTransform_SavedNameLabel';
import SAVED_SAVE from '@salesforce/label/c.Core_SuperTransform_SavedSave';
import SAVED_RENAME from '@salesforce/label/c.Core_SuperTransform_SavedRename';
import SAVED_DELETE from '@salesforce/label/c.Core_SuperTransform_SavedDelete';
import SAVED_DELETE_MESSAGE from '@salesforce/label/c.Core_SuperTransform_SavedDeleteMessage';
import SAVED_DELETE_DETAIL from '@salesforce/label/c.Core_SuperTransform_SavedDeleteDetail';
import SAVED_SAVED from '@salesforce/label/c.Core_SuperTransform_SavedSaved';
import SAVED_LOADED from '@salesforce/label/c.Core_SuperTransform_SavedLoaded';
import SAVED_RENAMED from '@salesforce/label/c.Core_SuperTransform_SavedRenamed';
import SAVED_DELETED from '@salesforce/label/c.Core_SuperTransform_SavedDeleted';
import SAVED_SKIPPED from '@salesforce/label/c.Core_SuperTransform_SavedSkipped';

/** A shipped step list: tidy spaces, then capitalize each word (for names). */
const NAME_CASE_STEPS = [{ op: 'trim' }, { op: 'proper' }];

/** Over this many records the confirmation asks for the number to be typed. */
const TYPE_TO_CONFIRM_OVER = 200;
/** How long the conditions rest before the count is asked for again. */
const COUNT_DELAY = 500;
const NUMBER_TYPES = new Set(['integer', 'double', 'currency', 'percent']);
/** Fields a transform result is written to as text (BulkUpdateFields.canTransform). */
const TEXT_TYPES = new Set(['string', 'textarea']);
/** Fields the one-click phone format is offered on: phone fields and short text. */
const PHONE_TYPES = new Set(['phone', 'string']);
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
  return value === null || value === undefined || value === '' ? BLANK : String(value);
}

function messageFrom(error) {
  if (error && error.body && error.body.message) {
    return error.body.message;
  }
  return error && error.message ? error.message : String(error);
}

/**
 * Super Transform (C-50, admin guide super-transform.md): a bulk update built on one page, in
 * five numbered cards (object, which records, what to change, preview, run), without a file or
 * a Find query.
 *
 * It is a front for the bulk update engine (C-35, C-37): the page sends only a query document and
 * the changes, which BulkUpdateController checks as the person, counts, previews with the run's
 * own code and runs as a journaled, undoable job. Undo is on the Data Jobs list below it.
 */
export default class SuperTransform extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    help: HELP,
    noPermission: NO_PERMISSION,
    noPermissionHeading: NO_PERMISSION_HEADING,
    noObjectsHeading: NO_OBJECTS_HEADING,
    matching: MATCHING,
    stepObject: STEP_OBJECT,
    stepRecords: STEP_RECORDS,
    stepChanges: STEP_CHANGES,
    stepPreview: STEP_PREVIEW,
    stepRun: STEP_RUN,
    searchObjects: SEARCH_OBJECTS,
    object: OBJECT,
    chooseObject: CHOOSE_OBJECT,
    noObjects: NO_OBJECTS,
    objectFirst: OBJECT_FIRST,
    counting: COUNTING,
    field: FIELD,
    chooseField: CHOOSE_FIELD,
    action: ACTION,
    newValue: NEW_VALUE,
    copyFrom: COPY_FROM,
    remove: REMOVE,
    addField: ADD_FIELD,
    preview: PREVIEW,
    previewHint: PREVIEW_HINT,
    record: RECORD,
    changesTo: CHANGES_TO,
    noChange: NO_CHANGE,
    run: RUN,
    runHint: RUN_HINT,
    failures: FAILURES,
    undoHint: UNDO_HINT,
    startAnother: START_ANOTHER,
    loading: LOADING,
    savedHeading: SAVED_HEADING,
    savedHelp: SAVED_HELP,
    savedChoose: SAVED_CHOOSE,
    savedPlaceholder: SAVED_PLACEHOLDER,
    savedNone: SAVED_NONE,
    savedLoad: SAVED_LOAD,
    savedName: SAVED_NAME,
    savedSave: SAVED_SAVE,
    savedRename: SAVED_RENAME,
    savedDelete: SAVED_DELETE
  };

  loaded = false;
  allowed = false;
  maxChanges = 5;
  objects = [];
  objectSearch = '';
  objectApiName;
  targets = [];
  filterJson = '';
  filterValid = true;
  counted;
  counting = false;
  changes = [];
  preview;
  job;
  busy = false;
  errorMessage;
  noticeMessage;
  nextKey = 1;
  countTimer;
  countRequest = 0;
  stopTimer;
  savedLists = [];
  savedListId;
  savedNameText = '';

  connectedCallback() {
    this.load();
  }

  disconnectedCallback() {
    clearTimeout(this.countTimer);
    this.stopPolling();
  }

  async load() {
    await this.work(async () => {
      const page = await getPage({ everyone: false });
      this.allowed = Boolean(page && page.allowed);
      if (this.allowed) {
        this.maxChanges = page.maxChanges || this.maxChanges;
        this.objects = await getObjects();
        this.savedLists = await getSavedLists();
      }
    });
    this.loaded = true;
  }

  /* ---------- what the template reads ---------- */

  get showNoPermission() {
    return this.loaded && !this.allowed && !this.errorMessage;
  }

  get showCards() {
    return this.loaded && this.allowed;
  }

  get hasObjects() {
    return this.objects.length > 0;
  }

  get objectOptions() {
    const search = this.objectSearch.trim().toLowerCase();
    return this.objects.filter(
      (option) =>
        !search ||
        option.value === this.objectApiName ||
        option.label.toLowerCase().includes(search) ||
        option.value.toLowerCase().includes(search)
    );
  }

  /* ---------- saved step lists (C-50f1) ---------- */

  get hasSavedLists() {
    return this.savedLists.length > 0;
  }

  get savedOptions() {
    return this.savedLists.map((entry) => ({
      label: format(SAVED_OPTION, entry.name, entry.objectLabel || entry.objectName),
      value: entry.recordId
    }));
  }

  get pickDisabled() {
    return this.busy || !this.savedListId;
  }

  get saveDisabled() {
    return this.busy || !this.objectApiName || !this.filterValid || !this.savedNameText.trim();
  }

  get renameDisabled() {
    return this.busy || !this.savedListId || !this.savedNameText.trim();
  }

  get hasObject() {
    return Boolean(this.objectApiName);
  }

  get objectLabel() {
    const found = this.objects.find((option) => option.value === this.objectApiName);
    return found ? found.label : this.objectApiName;
  }

  get countMessage() {
    if (!this.filterValid) {
      return FIX_CONDITIONS;
    }
    if (this.counting || !this.counted) {
      return COUNTING;
    }
    const { count, runLimit, objectLabel } = this.counted;
    if (count === null || count === undefined) {
      return format(TOO_MANY, runLimit.toLocaleString());
    }
    return count === 0
      ? format(NONE_MATCH, objectLabel)
      : format(MATCH_COUNT, count.toLocaleString(), objectLabel);
  }

  /** The page's one polite live region: progress, else the preview, else the count. */
  get statusMessage() {
    if (this.jobView) {
      return this.jobView.running ? this.jobView.progressLine : this.jobView.summary;
    }
    if (this.preview) {
      return this.previewLine;
    }
    return this.hasObject ? this.countMessage : '';
  }

  get countValue() {
    if (!this.counted || this.counting || !this.filterValid) {
      return '-';
    }
    const count = this.counted.count;
    return count === null || count === undefined
      ? `${this.counted.runLimit.toLocaleString()}+`
      : count;
  }

  get countBadge() {
    if (!this.counted || this.counting || !this.filterValid) {
      return '';
    }
    if (this.counted.overLimit) {
      return BADGE_OVER;
    }
    return !this.filterJson && this.counted.count ? BADGE_EVERY : '';
  }

  get countBadgeVariant() {
    return this.counted && this.counted.overLimit ? 'error' : 'warning';
  }

  get warnings() {
    const found = [];
    const counted = this.counted;
    if (!counted || this.counting || !this.filterValid) {
      return found;
    }
    if (!this.filterJson && counted.count) {
      found.push({
        key: 'no-filter',
        text: format(NO_FILTER, this.objectLabel, counted.count.toLocaleString())
      });
    }
    if (counted.overLimit && counted.count) {
      found.push({
        key: 'over-limit',
        text: format(OVER_LIMIT, counted.count.toLocaleString(), counted.runLimit.toLocaleString())
      });
    }
    return found;
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
            : []),
          ...(target && TEXT_TYPES.has(type)
            ? [{ label: ACTION_NAME_CASE, value: 'nameCase' }]
            : []),
          ...(target && PHONE_TYPES.has(type)
            ? [{ label: ACTION_PHONE_FORMAT, value: 'phoneFormat' }]
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
    return this.busy || this.changes.length >= this.maxChanges;
  }

  get fieldLimitLine() {
    return format(FIELD_LIMIT, this.maxChanges);
  }

  get hasChange() {
    return this.changes.some((change) => change.field);
  }

  get previewDisabled() {
    return (
      this.busy ||
      !this.hasChange ||
      !this.filterValid ||
      Boolean(this.counted && this.counted.overLimit)
    );
  }

  get previewLine() {
    return this.preview
      ? format(PREVIEW_COUNT, this.preview.count.toLocaleString(), this.preview.sample.length)
      : '';
  }

  /** Columns: one per changed field, in the order the changes were chosen. */
  get previewColumns() {
    const first = this.preview && this.preview.sample[0];
    return first
      ? first.changes.map((change, index) => ({ key: `col-${index}`, label: change.label }))
      : [];
  }

  get previewRows() {
    return ((this.preview && this.preview.sample) || []).map((record) => ({
      key: record.recordId,
      name: record.name,
      cells: record.changes.map((change, index) => {
        const changed = !change.problem && !change.unchanged;
        let cellClass = 'slds-cell-wrap';
        if (change.problem) {
          cellClass += ' slds-text-color_error';
        } else if (changed) {
          cellClass += ' changed';
        }
        return {
          key: `${record.recordId}-${index}`,
          before: shown(change.before),
          after: change.problem ? change.problem : shown(change.after),
          changed,
          unchanged: Boolean(change.unchanged),
          problem: Boolean(change.problem),
          cellClass
        };
      })
    }));
  }

  get alreadyHeldLine() {
    if (!this.preview) {
      return '';
    }
    const held = this.preview.sample.filter((record) =>
      record.changes.every((change) => change.unchanged)
    ).length;
    return format(ALREADY_HELD, held, this.preview.sample.length);
  }

  get runDisabled() {
    return this.busy || !this.preview || Boolean(this.job && this.job.running);
  }

  get jobView() {
    if (!this.job) {
      return undefined;
    }
    const job = this.job;
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

  /* ---------- 1. object ---------- */

  handleObjectSearch(event) {
    this.objectSearch = event.detail.value || '';
  }

  async handleObjectChange(event) {
    this.objectApiName = event.detail.value;
    this.filterJson = '';
    this.filterValid = true;
    this.targets = [];
    this.changes = [];
    this.job = undefined;
    this.noticeMessage = undefined;
    this.invalidate();
    await this.work(async () => {
      this.targets = await getTargets({ objectName: this.objectApiName });
      this.changes = [this.newChange()];
    });
    this.scheduleCount(0);
  }

  /* ---------- 2. which records ---------- */

  handleFilterChange(event) {
    this.filterJson = event.detail.value || '';
    this.filterValid = event.detail.valid !== false;
    this.invalidate();
    this.scheduleCount(COUNT_DELAY);
  }

  queryJson() {
    const document = { version: 1, object: this.objectApiName, fields: ['Id'] };
    if (this.filterJson) {
      document.filter = JSON.parse(this.filterJson);
    }
    return JSON.stringify(document);
  }

  /** Asks for the count once the conditions have rested; a later answer wins. */
  scheduleCount(delay) {
    clearTimeout(this.countTimer);
    if (!this.objectApiName || !this.filterValid) {
      return;
    }
    this.counting = true;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.countTimer = setTimeout(() => this.count(), delay);
  }

  async count() {
    this.countRequest += 1;
    const request = this.countRequest;
    try {
      const counted = await countMatches({ queryJson: this.queryJson() });
      if (request === this.countRequest) {
        this.counted = counted;
        this.errorMessage = undefined;
      }
    } catch (error) {
      if (request === this.countRequest) {
        this.counted = undefined;
        this.errorMessage = messageFrom(error);
      }
    } finally {
      if (request === this.countRequest) {
        this.counting = false;
      }
    }
  }

  /* ---------- 3. what to change ---------- */

  newChange() {
    const key = String(this.nextKey);
    this.nextKey += 1;
    return { key, field: undefined, action: 'set', value: '', source: undefined };
  }

  handleAddChange() {
    this.changes = [...this.changes, this.newChange()];
  }

  handleRemoveChange(event) {
    const key = event.currentTarget.dataset.key;
    this.changes = this.changes.filter((change) => change.key !== key);
    this.invalidate();
  }

  async handleChangeEdit(event) {
    const key = event.currentTarget.dataset.key;
    const part = event.currentTarget.dataset.part;
    let value = part === 'record' ? event.detail.recordId : event.detail.value;
    if (Array.isArray(value)) {
      value = value.join(';');
    }
    this.changes = this.changes.map((change) => {
      if (change.key !== key) {
        return change;
      }
      if (part === 'field') {
        return { key, field: value, action: 'set', value: '', source: undefined };
      }
      if (part === 'action' && value === 'nameCase') {
        // A shipped step list: shown and editable as Change With Steps.
        return {
          ...change,
          action: 'transform',
          transforms: NAME_CASE_STEPS.map((s) => ({ ...s }))
        };
      }
      if (part === 'action' && value === 'phoneFormat') {
        // A shipped step list with a digit-format step, shown and editable as Change With Steps.
        return {
          ...change,
          action: 'transform',
          transforms: PHONE_PRESET_STEPS.map((s) => ({ ...s }))
        };
      }
      return { ...change, [part === 'record' ? 'value' : part]: value };
    });
    this.invalidate();
    const edited = this.changes.find((change) => change.key === key);
    if (edited && (edited.action === 'copy' || edited.action === 'transform') && !edited.sources) {
      await this.work(async () => {
        const sources = await getCopySources({
          objectName: this.objectApiName,
          fieldName: edited.field
        });
        this.changes = this.changes.map((each) => (each.key === key ? { ...each, sources } : each));
      });
    }
  }

  handleStepsChange(event) {
    const key = event.currentTarget.dataset.key;
    const transforms = event.detail.transforms;
    this.changes = this.changes.map((change) => {
      return change.key === key ? { ...change, transforms } : change;
    });
    this.invalidate();
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
  }

  /* ---------- 4. preview ---------- */

  async handlePreview() {
    this.invalidate();
    this.noticeMessage = undefined;
    await this.work(async () => {
      this.preview = await previewSample({
        queryJson: this.queryJson(),
        changesJson: this.changesJson()
      });
    });
  }

  /* ---------- 5. run ---------- */

  async handleRun() {
    const count = this.preview.count;
    const fields = this.changes
      .filter((change) => change.field)
      .map((change) => this.targetOf(change.field).label);
    const asksToType = count > TYPE_TO_CONFIRM_OVER;
    const confirmed = await BarnConfirmModal.open({
      label: RUN,
      size: 'small',
      message: format(
        CONFIRM_MESSAGE,
        fields.join(', '),
        count.toLocaleString(),
        this.preview.objectLabel
      ),
      details: [CONFIRM_DETAIL],
      confirmLabel: CONFIRM_BUTTON,
      cancelLabel: CANCEL,
      typeToConfirm: asksToType ? String(count) : undefined,
      typeToConfirmLabel: asksToType ? format(TYPE_TO_CONFIRM, count) : undefined
    });
    if (confirmed !== true) {
      return;
    }
    await this.work(async () => {
      this.job = await startUpdate({
        queryJson: this.queryJson(),
        changesJson: this.changesJson(),
        confirmedCount: count
      });
      this.noticeMessage = STARTED;
      this.startPolling();
    });
  }

  /** Slows down after the first minute and retries once on an error (c/jobPoller). */
  startPolling() {
    this.stopPolling();
    this.stopTimer = startPolling(
      () => this.poll(),
      (error) => {
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

  async poll() {
    this.job = await getJob({ jobId: this.job.recordId });
    if (!this.job.running) {
      this.stopPolling();
      this.noticeMessage = undefined;
      return true;
    }
    return false;
  }

  handleStartAnother() {
    this.stopPolling();
    this.job = undefined;
    this.noticeMessage = undefined;
    this.invalidate();
    this.scheduleCount(0);
  }

  /* ---------- saved step lists (C-50f1, documented JSON, plan 9.9) ---------- */

  /** The page as a version 1 list document: object, filter and changes. */
  definitionJson() {
    const definition = {
      version: 1,
      object: this.objectApiName,
      changes: JSON.parse(this.changesJson())
    };
    if (this.filterJson) {
      definition.filter = JSON.parse(this.filterJson);
    }
    return JSON.stringify(definition);
  }

  selectedList() {
    return this.savedLists.find((entry) => entry.recordId === this.savedListId);
  }

  async refreshSavedLists(selectId) {
    this.savedLists = await getSavedLists();
    this.savedListId = selectId;
  }

  handleSavedPick(event) {
    this.savedListId = event.detail.value;
    const entry = this.selectedList();
    this.savedNameText = entry ? entry.name : this.savedNameText;
  }

  handleSavedName(event) {
    this.savedNameText = event.detail.value || '';
  }

  async handleSavedSave() {
    this.noticeMessage = undefined;
    await this.work(async () => {
      const saved = await saveSavedList({
        name: this.savedNameText,
        definitionJson: this.definitionJson()
      });
      await this.refreshSavedLists(saved.recordId);
      this.noticeMessage = format(SAVED_SAVED, saved.name);
    });
  }

  async handleSavedRename() {
    this.noticeMessage = undefined;
    await this.work(async () => {
      const saved = await renameSavedList({
        recordId: this.savedListId,
        name: this.savedNameText
      });
      await this.refreshSavedLists(saved.recordId);
      this.noticeMessage = format(SAVED_RENAMED, saved.name);
    });
  }

  async handleSavedDelete() {
    const entry = this.selectedList();
    if (!entry) {
      return;
    }
    const confirmed = await BarnConfirmModal.open({
      label: SAVED_DELETE,
      size: 'small',
      message: format(SAVED_DELETE_MESSAGE, entry.name),
      details: [SAVED_DELETE_DETAIL],
      confirmLabel: SAVED_DELETE,
      cancelLabel: CANCEL
    });
    if (confirmed !== true) {
      return;
    }
    this.noticeMessage = undefined;
    await this.work(async () => {
      await deleteSavedList({ recordId: entry.recordId });
      await this.refreshSavedLists(undefined);
      this.noticeMessage = format(SAVED_DELETED, entry.name);
    });
  }

  /**
   * Fills the page in from a saved list: object, conditions and changes. A change naming a field
   * the person may not change now is left out and counted; nothing runs until Preview and Run.
   */
  async handleSavedLoad() {
    this.noticeMessage = undefined;
    await this.work(async () => {
      const saved = await loadSavedList({ recordId: this.savedListId });
      const definition = JSON.parse(saved.definitionJson);
      const targets = await getTargets({ objectName: definition.object });
      this.stopPolling();
      this.job = undefined;
      this.objectApiName = definition.object;
      this.targets = targets;
      this.filterJson = definition.filter ? JSON.stringify(definition.filter) : '';
      this.filterValid = true;
      const wanted = definition.changes || [];
      const kept = wanted.filter((change) => this.targetOf(change.field));
      const loaded = await Promise.all(
        kept.map(async (change) => {
          const entry = {
            ...this.newChange(),
            field: change.field,
            action: change.action,
            value: change.value === undefined || change.value === null ? '' : change.value,
            source: change.source,
            transforms: change.transforms
          };
          if (entry.action === 'copy' || entry.action === 'transform') {
            entry.sources = await getCopySources({
              objectName: definition.object,
              fieldName: change.field
            });
          }
          return entry;
        })
      );
      this.changes = loaded.length ? loaded : [this.newChange()];
      this.invalidate();
      this.savedNameText = saved.name;
      const skipped = wanted.length - kept.length;
      this.noticeMessage = skipped
        ? format(SAVED_SKIPPED, saved.name, skipped)
        : format(SAVED_LOADED, saved.name);
      this.scheduleCount(0);
    });
  }

  /* ---------- plumbing ---------- */

  async work(action) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await action();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.busy = false;
    }
  }
}
