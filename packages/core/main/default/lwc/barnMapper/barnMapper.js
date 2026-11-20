import { LightningElement, api, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import getObjects from '@salesforce/apex/MapController.getObjects';
import getTargetFields from '@salesforce/apex/MapController.getTargetFields';
import previewMap from '@salesforce/apex/MapController.previewMap';
import listObjects from '@salesforce/apex/FindController.listObjects';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import GUESS_BADGE from '@salesforce/label/c.Core_Import_GuessBadge';
import GUESS_ACCEPT from '@salesforce/label/c.Core_Import_GuessAccept';
import GUESS_ACCEPT_ALL from '@salesforce/label/c.Core_Import_GuessAcceptAll';
import opTrim from '@salesforce/label/c.Core_Import_ChangesOpTrim';
import opUpper from '@salesforce/label/c.Core_Import_ChangesOpUpper';
import opLower from '@salesforce/label/c.Core_Import_ChangesOpLower';
import opProper from '@salesforce/label/c.Core_Import_ChangesOpProper';
import opReplace from '@salesforce/label/c.Core_Import_ChangesOpReplace';
import opIfBlank from '@salesforce/label/c.Core_Import_ChangesOpIfBlank';
import opAppend from '@salesforce/label/c.Core_Import_ChangesOpAppend';
import opDate from '@salesforce/label/c.Core_Import_ChangesOpDate';
import opMap from '@salesforce/label/c.Core_Import_StepsOpMap';
import opIfThen from '@salesforce/label/c.Core_Import_StepsOpIfThen';
import opPart from '@salesforce/label/c.Core_Import_StepsOpPart';
import opFirst from '@salesforce/label/c.Core_Import_StepsOpFirst';
import opLast from '@salesforce/label/c.Core_Import_StepsOpLast';
import opShiftDate from '@salesforce/label/c.Core_Import_StepsOpShiftDate';
import opToday from '@salesforce/label/c.Core_Import_StepsOpToday';
import opDigits from '@salesforce/label/c.Core_Import_StepsOpDigits';
import BLANK_CLEARS from '@salesforce/label/c.Core_Import_BlankClearsLabel';
import { parseCsv, detectDelimiter, toRecords } from 'c/csvParser';
import { createDragController } from 'c/barnDrag';
import { dragMessages, dragInstructions } from 'c/barnDragText';
import { score } from 'c/importFieldPicker';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import {
  autoMatch,
  columnSentence,
  format,
  isPath,
  keptSample,
  parseMap,
  previewRows,
  problems,
  RECORD,
  sampleValues,
  samplesFromJson,
  serialize,
  sourcesFromJson,
  sourcesFromRecord,
  sourcesFromRows,
  summarize,
  MAX_SAMPLES
} from 'c/mapDocument';

/** The pinned choice of the Pick list: no source. */
const NONE = '__none';
/** Samples the preview steps through with Previous and Next. */
const PREVIEW_SAMPLES = 10;
const PREVIEW_DELAY_MS = 300;
const MAX_FILE_ROWS = MAX_SAMPLES + 1;
const STEP_WORDS = {
  trim: opTrim,
  upper: opUpper,
  lower: opLower,
  proper: opProper,
  replace: opReplace,
  ifBlank: opIfBlank,
  append: opAppend,
  date: opDate,
  map: opMap,
  ifThen: opIfThen,
  part: opPart,
  first: opFirst,
  last: opLast,
  shiftDate: opShiftDate,
  today: opToday,
  digits: opDigits
};
/** Field types whose values a match by field may compare (R-IT8). */
const MATCH_TYPES = ['string', 'email', 'phone'];

function errorText(error) {
  return (error && error.body && error.body.message) || UNEXPECTED_ERROR;
}

function lowerFirst(text) {
  const value = String(text || '');
  return value.charAt(0).toLowerCase() + value.slice(1);
}

function lower(text) {
  return String(text || '').toLowerCase();
}

/**
 * The Mapper (integration hub design Section 2.4; admin guide mapper.md): one screen that says
 * where each value goes. Three panes: From (the sources, each with real example values from a
 * file's first rows, a chosen record or pasted JSON), To (the target fields grouped Required,
 * Suggested and All, each filled field read as a sentence) and Preview (what the sample produces,
 * with a badge on each problem), plus matching in one sentence and Check Before Running.
 *
 * The logic is the framework-free c/mapDocument; the server only runs the steps and the lookups
 * (MapController.previewMap). Drag and drop (c/barnDrag) is always beside Pick. The component
 * edits a map document and fires `change` with `{ document, pendingGuesses, problems }`; the page
 * around it (c/savedMaps) names and saves it.
 */
export default class BarnMapper extends LightningElement {
  helpReady = isHelpLoaded('Core');

  /** The map being edited (a document or its JSON). */
  @api
  get value() {
    return serialize(this.document);
  }

  set value(input) {
    const { document, skipped } = parseMap(input);
    this.document = document;
    this.skipped = skipped;
    this.autoMatched = Boolean(this.importing) || document.columns.length > 0;
    const sample = document.from.sample;
    if (sample) {
      this.samples = [sample];
      this.jsonText = JSON.stringify(sample, null, 2);
    }
    if (this.importing) {
      // Super Importer hands its columns back after each change: same file, same fields.
      this.schedulePreview();
    } else if (this.connected) {
      this.loadSchema();
    }
  }

  /**
   * Super Importer's Check Columns step drawn by the Mapper (MAP-05; admin guide importing.md
   * section 3): `{ objectName, headers, rows, targets: [{ value, label }], lookupChoices:
   * { target: [{ label, value }] }, canCreateFields }`. The file and the template's record are
   * fixed, the fields offered are the template's, a column fills one field, and matching, fixed
   * values and defaults stay with the template's own steps. Each change fires `change` with the
   * columns, guesses kept; Create Field fires `createfield` with `{ source }`.
   */
  @api
  get importSetup() {
    return this.importing;
  }

  set importSetup(setup) {
    const objectChanged =
      !this.importing || !setup || this.importing.objectName !== setup.objectName;
    this.importing = setup || undefined;
    if (!setup) {
      return;
    }
    this.headers = setup.headers || [];
    this.samples = setup.rows || [];
    this.autoMatched = true;
    this.document = {
      ...this.document,
      from: { kind: 'columns' },
      to: { kind: 'record', object: setup.objectName }
    };
    if (this.connected && objectChanged) {
      this.loadSchema();
    } else {
      this.schedulePreview();
    }
  }

  importing;

  get notImporting() {
    return !this.importing;
  }

  get showMatch() {
    return this.isToRecord && !this.importing;
  }

  document = parseMap({ version: 4 }).document;
  skipped = 0;
  autoMatched = false;
  connected = false;
  /** Worked-out values kept between renders; changing its contents never re-renders. */
  cache = {};

  /** The raw samples: file rows, the chosen record, or the items of the pasted JSON. */
  samples = [];
  headers = [];
  jsonText = '';
  sampleError;
  recordId;
  record;
  sourceFields = [];
  targetFields = [];
  readableObjects = [];
  writableObjects = [];
  lookupFieldsByObject = {};
  /** Keys added for a JSON body, before a column fills them. */
  addedKeys = [];
  newKey = '';
  fieldQuery = '';
  pickingTarget;
  openTarget;
  previewSamples = [];
  previewIndex = 0;
  previewError;
  checking = false;
  checkResults;
  announcement = '';
  dragState;
  loadError;

  none = NONE;
  previewTimer;

  // ---- text -------------------------------------------------------------------------------

  get text() {
    return {
      fromKind: helpText('Core', 'Core_Mapper_FromKind'),
      fromObject: helpText('Core', 'Core_Mapper_FromObject'),
      toKind: helpText('Core', 'Core_Mapper_ToKind'),
      toObject: helpText('Core', 'Core_Mapper_ToObject'),
      chooseFile: helpText('Core', 'Core_Mapper_ChooseFile'),
      chooseRecord: helpText('Core', 'Core_Mapper_ChooseRecord'),
      sampleJson: helpText('Core', 'Core_Mapper_SampleJson'),
      useSample: helpText('Core', 'Core_Mapper_UseSample'),
      fromHeading: helpText('Core', 'Core_Mapper_FromHeading'),
      toHeading: helpText('Core', 'Core_Mapper_ToHeading'),
      previewHeading: helpText('Core', 'Core_Mapper_PreviewHeading'),
      noSources: helpText('Core', 'Core_Mapper_NoSources'),
      noTargets: helpText('Core', 'Core_Mapper_NoTargets'),
      noSamples: helpText('Core', 'Core_Mapper_NoSamples'),
      matchFields: helpText('Core', 'Core_Mapper_MatchFields'),
      findField: helpText('Core', 'Core_Mapper_FindField'),
      addKey: helpText('Core', 'Core_Mapper_AddKey'),
      addKeyButton: helpText('Core', 'Core_Mapper_AddKeyButton'),
      pick: helpText('Core', 'Core_Mapper_Pick'),
      details: helpText('Core', 'Core_Mapper_Details'),
      remove: helpText('Core', 'Core_Mapper_Remove'),
      required: helpText('Core', 'Core_Mapper_Required'),
      requiredBox: helpText('Core', 'Core_Mapper_RequiredBox'),
      alwaysUse: helpText('Core', 'Core_Mapper_AlwaysUse'),
      whenBlank: helpText('Core', 'Core_Mapper_WhenBlank'),
      lookupField: helpText('Core', 'Core_Mapper_LookupField'),
      lookupNotFound: helpText('Core', 'Core_Mapper_LookupNotFound'),
      matchHeading: helpText('Core', 'Core_Mapper_MatchHeading'),
      matchBy: helpText('Core', 'Core_Mapper_MatchBy'),
      matchField: helpText('Core', 'Core_Mapper_MatchField'),
      matchSeveral: helpText('Core', 'Core_Mapper_MatchSeveral'),
      matchNone: helpText('Core', 'Core_Mapper_MatchNone'),
      previous: helpText('Core', 'Core_Mapper_Previous'),
      next: helpText('Core', 'Core_Mapper_Next'),
      check: helpText('Core', 'Core_Mapper_Check'),
      fieldGone: helpText('Core', 'Core_Mapper_FieldGone'),
      guessBadge: GUESS_BADGE,
      guessBadgeHelp: helpText('Core', 'Core_Import_GuessBadgeHelp'),
      accept: GUESS_ACCEPT,
      acceptAll: GUESS_ACCEPT_ALL,
      fieldColumn: helpText('Core', 'Core_Mapper_FieldColumn'),
      valueColumn: helpText('Core', 'Core_Mapper_ValueColumn'),
      blankClears: BLANK_CLEARS,
      createField: helpText('Core', 'Core_Mapper_CreateField')
    };
  }

  get flagWords() {
    return {
      required: helpText('Core', 'Core_Mapper_FlagRequired'),
      tooLong: helpText('Core', 'Core_Mapper_FlagTooLong'),
      notNumber: helpText('Core', 'Core_Mapper_FlagNotNumber'),
      notDate: helpText('Core', 'Core_Mapper_FlagNotDate'),
      notBoolean: helpText('Core', 'Core_Mapper_FlagNotBoolean'),
      notInList: helpText('Core', 'Core_Mapper_FlagNotInList'),
      lookupNone: helpText('Core', 'Core_Mapper_FlagLookupNone'),
      lookupSeveral: helpText('Core', 'Core_Mapper_FlagLookupSeveral')
    };
  }

  get sentenceWords() {
    const steps = {};
    Object.keys(STEP_WORDS).forEach((op) => {
      steps[op] = lowerFirst(STEP_WORDS[op]);
    });
    return {
      gets: helpText('Core', 'Core_Mapper_SentenceGets'),
      fixed: helpText('Core', 'Core_Mapper_SentenceFixed'),
      then: helpText('Core', 'Core_Mapper_SentenceThen'),
      end: '.',
      steps
    };
  }

  get dragHelp() {
    return dragInstructions();
  }

  // ---- lifecycle --------------------------------------------------------------------------

  connectedCallback() {
    this.connected = true;
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.drag = createDragController({
      root: this.template,
      layout: 'columns',
      messages: dragMessages(),
      announce: (said) => {
        this.announcement = said;
      },
      onChange: (state) => {
        this.dragState = state;
      },
      canDrop: (itemId, fromZone, toZone) => toZone !== 'sources',
      onDrop: ({ itemId, toZone }) => {
        if (!toZone || toZone === 'sources') {
          return false;
        }
        this.setSource(toZone, itemId);
        return true;
      }
    });
    if (!this.importing) {
      this.loadObjects();
    }
    this.loadSchema();
  }

  disconnectedCallback() {
    this.connected = false;
    if (this.drag) {
      this.drag.destroy();
    }
    clearTimeout(this.previewTimer);
  }

  async loadObjects() {
    try {
      const [writable, readable] = await Promise.all([getObjects(), listObjects()]);
      this.writableObjects = writable || [];
      this.readableObjects = readable || [];
    } catch (error) {
      this.loadError = errorText(error);
    }
  }

  /** The target fields and, for a record source, its fields; then auto-match and preview. */
  async loadSchema() {
    try {
      const toObject = this.toObject;
      this.targetFields =
        this.isToRecord && toObject ? (await getTargetFields({ objectName: toObject })) || [] : [];
      const fromObject = this.fromObject;
      const info =
        this.isFromRecord && fromObject ? await getObjectInfo({ objectApiName: fromObject }) : null;
      this.sourceFields = info ? info.fields || [] : [];
      this.loadError = undefined;
    } catch (error) {
      this.targetFields = [];
      this.loadError = errorText(error);
    }
    this.maybeAutoMatch();
    this.schedulePreview();
  }

  @wire(getRecord, { recordId: '$recordId', optionalFields: '$recordFields' })
  wiredRecord({ data, error }) {
    if (data) {
      const values = {};
      Object.keys(data.fields || {}).forEach((name) => {
        values[name] = data.fields[name].value;
      });
      this.record = values;
      this.samples = [values];
      this.maybeAutoMatch();
      this.schedulePreview();
    } else if (error) {
      this.sampleError = errorText(error);
    }
  }

  get recordFields() {
    return this.recordId
      ? this.sourceFields.map((field) => `${this.fromObject}.${field.apiName}`)
      : undefined;
  }

  // ---- the map's setup --------------------------------------------------------------------

  get fromKind() {
    return this.document.from.kind;
  }

  get fromObject() {
    return this.document.from.object;
  }

  get toKind() {
    return this.document.to.kind;
  }

  get toObject() {
    return this.document.to.object;
  }

  get isFromColumns() {
    return this.fromKind === 'columns';
  }

  get isFromRecord() {
    return this.fromKind === 'record';
  }

  get isFromJson() {
    return this.fromKind === 'json';
  }

  get isToRecord() {
    return this.toKind === 'record';
  }

  get isToJson() {
    return this.toKind === 'json';
  }

  get fromKindOptions() {
    return [
      { label: helpText('Core', 'Core_Mapper_FromColumns'), value: 'columns' },
      { label: helpText('Core', 'Core_Mapper_FromRecord'), value: 'record' },
      { label: helpText('Core', 'Core_Mapper_FromJson'), value: 'json' }
    ];
  }

  get toKindOptions() {
    return [
      { label: helpText('Core', 'Core_Mapper_ToRecord'), value: 'record' },
      { label: helpText('Core', 'Core_Mapper_ToJson'), value: 'json' }
    ];
  }

  handleFromKind(event) {
    this.update({ from: { kind: event.detail.value } });
    this.samples = [];
    this.headers = [];
    this.record = undefined;
    this.recordId = undefined;
    this.sampleError = undefined;
    this.loadSchema();
  }

  handleFromObject(event) {
    this.update({ from: { kind: 'record', object: event.detail.value } });
    this.samples = [];
    this.recordId = undefined;
    this.loadSchema();
  }

  /** Another kind of target starts the columns again: they named the other target's fields. */
  handleToKind(event) {
    this.update({ to: { kind: event.detail.value }, columns: [], defaults: [] });
    delete this.document.match;
    this.autoMatched = false;
    this.loadSchema();
  }

  handleToObject(event) {
    this.update({ to: { kind: 'record', object: event.detail.value }, columns: [], defaults: [] });
    delete this.document.match;
    this.autoMatched = false;
    this.loadSchema();
  }

  // ---- samples ----------------------------------------------------------------------------

  handleFile(event) {
    const file = event.target.files && event.target.files[0];
    if (!file) {
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      const content = String(reader.result || '');
      const { headers, records } = toRecords(
        parseCsv(content, detectDelimiter(content), MAX_FILE_ROWS)
      );
      this.headers = headers;
      this.samples = records;
      this.sampleError =
        headers.length === 0 ? helpText('Core', 'Core_Mapper_FileEmpty') : undefined;
      this.maybeAutoMatch();
      this.schedulePreview();
    };
    reader.readAsText(file);
  }

  handleRecord(event) {
    this.recordId = event.detail.recordId || undefined;
    if (!this.recordId) {
      this.samples = [];
      this.record = undefined;
    }
  }

  handleJsonText(event) {
    this.jsonText = event.detail.value;
  }

  handleUseJson() {
    const { samples, error } = samplesFromJson(this.jsonText);
    if (error) {
      this.sampleError =
        error === 'tooBig'
          ? helpText('Core', 'Core_Mapper_JsonTooBig')
          : helpText('Core', 'Core_Mapper_JsonUnreadable');
      return;
    }
    this.sampleError = undefined;
    this.samples = samples;
    const kept = keptSample(samples);
    const from = { ...this.document.from };
    if (kept) {
      from.sample = kept;
    } else {
      delete from.sample;
    }
    this.update({ from });
    this.maybeAutoMatch();
  }

  get hasSamples() {
    return this.samples.length > 0;
  }

  // ---- sources ----------------------------------------------------------------------------

  /** Every source: the sample's, then any a column names that the sample lacks. */
  get sources() {
    const key = [
      this.fromKind,
      this.samples,
      this.headers,
      this.record,
      this.sourceFields,
      this.document.columns
    ];
    const kept = this.cache.sources;
    if (kept && kept.key.every((part, index) => part === key[index])) {
      return kept.list;
    }
    const list = this.readSources();
    this.cache.sources = { key, list };
    return list;
  }

  readSources() {
    let found = [];
    if (this.isFromColumns) {
      found = sourcesFromRows(this.headers, this.samples);
    } else if (this.isFromJson) {
      found = sourcesFromJson(this.samples);
    } else {
      found = sourcesFromRecord(this.sourceFields, this.record);
    }
    const known = new Set(found.map((source) => lower(source.name)));
    this.document.columns.forEach((column) => {
      if (column.source && !known.has(lower(column.source))) {
        known.add(lower(column.source));
        found.push({ name: column.source, label: column.source, examples: [] });
      }
    });
    return found;
  }

  get hasSources() {
    return this.sources.length > 0;
  }

  get sourceRows() {
    const dragging = this.dragState && this.dragState.active ? this.dragState.itemId : null;
    const used = new Set(this.usedSources.map(lower));
    const canCreate = Boolean(this.importing && this.importing.canCreateFields);
    return this.sources.map((source) => ({
      ...source,
      canCreate: canCreate && !used.has(lower(source.name)),
      createLabel: format(helpText('Core', 'Core_Mapper_CreateFieldFor'), source.label),
      exampleText: source.examples.join(', '),
      itemClass: `barn-mapper-source slds-var-p-around_x-small${source.name === dragging ? ' barn-mapper-dragging' : ''}`
    }));
  }

  get sourceOptions() {
    return [{ label: helpText('Core', 'Core_Mapper_LeaveEmpty'), value: NONE }].concat(
      this.sources.map((source) => ({ label: source.label, value: source.name }))
    );
  }

  /** For a step that adds other columns: every source but the pinned choice. */
  get stepSourceOptions() {
    return this.sources.map((source) => ({ label: source.label, value: source.name }));
  }

  get usedSources() {
    return this.document.columns.filter((column) => column.source).map((column) => column.source);
  }

  sourceLabel(name) {
    const found = this.sources.find((source) => source.name === name);
    return found ? found.label : name;
  }

  // ---- targets ----------------------------------------------------------------------------

  /** Field information by target (`Record.Email`), for the preview's checks. */
  get fieldsByTarget() {
    const byTarget = {};
    this.offeredFields.forEach((field) => {
      byTarget[`${RECORD}.${field.apiName}`] = field;
    });
    return byTarget;
  }

  /**
   * The fields the To pane offers: the object's, or in Super Importer the template's, in its
   * order. A field created a moment ago, not yet in the cached describe, is offered as text.
   */
  get offeredFields() {
    if (!this.importing) {
      return this.targetFields;
    }
    const byTarget = new Map(
      this.targetFields.map((field) => [lower(`${RECORD}.${field.apiName}`), field])
    );
    return (this.importing.targets || []).map(
      (target) =>
        byTarget.get(lower(target.value)) || {
          apiName: String(target.value).slice(RECORD.length + 1),
          label: target.label,
          dataType: 'string'
        }
    );
  }

  /** Every target the To pane lists: the object's fields, or a JSON body's keys. */
  get targets() {
    if (this.isToRecord) {
      return this.offeredFields.map((field) => ({
        value: `${RECORD}.${field.apiName}`,
        label: field.label,
        name: field.apiName,
        field
      }));
    }
    const keys = [];
    const seen = new Set();
    this.document.columns
      .map((column) => column.target)
      .concat(this.document.defaults.map((entry) => entry.target))
      .concat(this.addedKeys)
      .forEach((key) => {
        if (!seen.has(lower(key))) {
          seen.add(lower(key));
          keys.push({ value: key, label: key, name: key });
        }
      });
    return keys;
  }

  columnFor(target) {
    return this.document.columns.find((column) => lower(column.target) === lower(target));
  }

  defaultFor(target) {
    const found = this.document.defaults.find((entry) => lower(entry.target) === lower(target));
    return found ? found.value : '';
  }

  /** The To pane: Required, Suggested (filled, guessed or alike a source) and All Fields. */
  get targetGroups() {
    const query = lower(this.fieldQuery).trim();
    const sourceWords = this.sources.map((source) => source.label);
    const rows = this.targets
      .filter((target) => !query || lower(`${target.label} ${target.name}`).includes(query))
      .map((target) => this.targetRow(target, sourceWords));
    // A column whose field is gone or not editable is listed too, so it can be removed.
    if (this.isToRecord && this.toObject && this.targetFields.length > 0) {
      const known = new Set(this.targets.map((target) => lower(target.value)));
      this.document.columns
        .filter((column) => !known.has(lower(column.target)))
        .forEach((column) => {
          rows.push({
            ...this.targetRow(
              { value: column.target, label: column.target, name: column.target },
              []
            ),
            gone: true
          });
        });
    }
    const groups = [
      {
        key: 'required',
        label: helpText('Core', 'Core_Mapper_GroupRequired'),
        rows: rows.filter((row) => row.required)
      },
      {
        key: 'suggested',
        label: helpText('Core', 'Core_Mapper_GroupSuggested'),
        rows: rows.filter((row) => !row.required && row.suggested)
      },
      {
        key: 'all',
        label: helpText('Core', 'Core_Mapper_GroupAll'),
        rows: rows.filter((row) => !row.required && !row.suggested)
      }
    ];
    return groups.filter((group) => group.rows.length > 0);
  }

  get hasTargets() {
    return this.targetGroups.length > 0;
  }

  targetRow(target, sourceWords) {
    const column = this.columnFor(target.value);
    const field = target.field || {};
    const defaultValue = this.defaultFor(target.value);
    const dragging = this.dragState && this.dragState.active ? this.dragState.overZone : null;
    const isLookup = Boolean(field.referenceTo) && lower(field.dataType) === 'reference';
    const lookup = (column && column.lookup) || {};
    const isOpen = this.openTarget === target.value;
    const row = {
      key: target.value,
      target: target.value,
      label: target.label,
      required: Boolean(field.required),
      mapped: Boolean(column),
      notMapped: !column,
      guessed: Boolean(column && column.guessed),
      gone: false,
      source: column && column.source ? column.source : NONE,
      sentence: this.sentenceFor(target.label, column, defaultValue),
      suggested:
        Boolean(column) ||
        defaultValue !== '' ||
        (sourceWords.length > 0 && sourceWords.some((words) => score(words, target.label) >= 2)),
      isPicking: this.pickingTarget === target.value,
      isOpen,
      pickLabel: format(helpText('Core', 'Core_Mapper_PickFor'), target.label),
      detailsLabel: format(helpText('Core', 'Core_Mapper_DetailsFor'), target.label),
      removeLabel: format(helpText('Core', 'Core_Mapper_RemoveFor'), target.label),
      acceptLabel: format(helpText('Core', 'Core_Mapper_AcceptFor'), target.label),
      transforms: (column && column.transforms) || [],
      fixedValue: column && typeof column.value === 'string' ? column.value : '',
      defaultValue,
      columnRequired: Boolean(column && column.required),
      isLookup,
      lookupObject: field.referenceTo,
      lookupField: (this.importing ? column && column.lookupField : lookup.field) || 'Id',
      notFound: lookup.notFound || 'reject',
      lookupFieldOptions: isLookup && isOpen ? this.lookupOptionsFor(target.value, field) : [],
      lookupSentence:
        isLookup && column && !this.importing ? this.lookupSentence(field, column) : '',
      blankClears: Boolean(column && column.blankClears),
      rowClass: `barn-mapper-target slds-var-p-around_x-small${dragging === target.value ? ' barn-mapper-drop' : ''}`
    };
    return row;
  }

  sentenceFor(label, column, defaultValue) {
    let sentence = '';
    if (column) {
      sentence = columnSentence(label, this.sourceLabel(column.source), column, this.sentenceWords);
    } else {
      sentence = helpText('Core', 'Core_Mapper_NotFilled');
    }
    if (defaultValue) {
      sentence = `${sentence} ${format(helpText('Core', 'Core_Mapper_SentenceDefault'), defaultValue)}`;
    }
    return sentence;
  }

  lookupSentence(field, column) {
    const lookup = column.lookup || {};
    const notFound =
      lookup.notFound === 'leaveEmpty'
        ? helpText('Core', 'Core_Mapper_LookupLeaveEmpty')
        : helpText('Core', 'Core_Mapper_LookupReject');
    const options = this.lookupFieldOptions(field.referenceTo);
    const chosen = options.find((option) => option.value === (lookup.field || 'Id'));
    return format(
      helpText('Core', 'Core_Mapper_LookupSentence'),
      field.referenceTo,
      chosen ? chosen.label : lookup.field || 'Id',
      this.sourceLabel(column.source) || column.value,
      notFound
    );
  }

  /** Super Importer offers the parent fields the template allows (R-IT13). */
  lookupOptionsFor(target, field) {
    if (this.importing) {
      return (this.importing.lookupChoices || {})[target] || [];
    }
    return this.lookupFieldOptions(field.referenceTo);
  }

  lookupFieldOptions(objectName) {
    const fields = this.lookupFieldsByObject[objectName];
    if (!fields) {
      this.loadLookupFields(objectName);
      return [{ label: helpText('Core', 'Core_Mapper_RecordId'), value: 'Id' }];
    }
    return fields;
  }

  async loadLookupFields(objectName) {
    if (!objectName || this.lookupFieldsByObject[objectName]) {
      return;
    }
    this.lookupFieldsByObject = {
      ...this.lookupFieldsByObject,
      [objectName]: [{ label: helpText('Core', 'Core_Mapper_RecordId'), value: 'Id' }]
    };
    try {
      const info = await getObjectInfo({ objectApiName: objectName });
      const options = [{ label: helpText('Core', 'Core_Mapper_RecordId'), value: 'Id' }].concat(
        (info.fields || [])
          .filter(
            (field) =>
              field.filterable &&
              MATCH_TYPES.concat(['id', 'picklist']).includes(field.dataType) &&
              field.apiName !== 'Id'
          )
          .map((field) => ({ label: field.label, value: field.apiName }))
      );
      this.lookupFieldsByObject = { ...this.lookupFieldsByObject, [objectName]: options };
    } catch {
      // The record ID stays the one choice; the preview reports a lookup it cannot read.
    }
  }

  get notFoundOptions() {
    return [
      { label: helpText('Core', 'Core_Mapper_LookupReject'), value: 'reject' },
      { label: helpText('Core', 'Core_Mapper_LookupLeaveEmpty'), value: 'leaveEmpty' }
    ];
  }

  // ---- editing the columns ------------------------------------------------------------------

  update(changes) {
    this.document = { ...this.document, ...changes };
    this.checkResults = undefined;
    this.notify();
    this.schedulePreview();
  }

  setColumns(columns) {
    this.update({ columns });
  }

  /** Gives a target this source (or none), keeping its steps, lookup and other settings. */
  setSource(target, source) {
    const existing = this.columnFor(target);
    let columns = this.document.columns.filter((column) => lower(column.target) !== lower(target));
    if (source && source !== NONE && this.importing) {
      // A file column loads into one field (R-IT1): it moves here from any other.
      columns = columns.filter((column) => lower(column.source) !== lower(source));
    }
    if (source && source !== NONE) {
      const next = { ...(existing || {}), source, target };
      delete next.guessed;
      delete next.value;
      columns = columns.concat(next);
      this.announcement = format(
        helpText('Core', 'Core_Mapper_Mapped'),
        this.sourceLabel(source),
        this.targetLabel(target)
      );
    }
    this.setColumns(columns);
  }

  changeColumn(target, change) {
    const existing = this.columnFor(target) || { target };
    const next = change({ ...existing });
    const columns = this.document.columns.filter(
      (column) => lower(column.target) !== lower(target)
    );
    this.setColumns(next ? columns.concat(next) : columns);
  }

  targetLabel(target) {
    const found = this.targets.find((each) => each.value === target);
    return found ? found.label : target;
  }

  handlePick(event) {
    const target = event.currentTarget.dataset.target;
    this.pickingTarget = this.pickingTarget === target ? undefined : target;
  }

  handlePicked(event) {
    const target = event.currentTarget.dataset.target;
    this.setSource(target, event.detail.value);
    this.pickingTarget = undefined;
  }

  handleAccept(event) {
    const target = event.currentTarget.dataset.target;
    this.changeColumn(target, (column) => {
      delete column.guessed;
      return column;
    });
  }

  handleAcceptAll() {
    this.setColumns(
      this.document.columns.map((column) => {
        const next = { ...column };
        delete next.guessed;
        return next;
      })
    );
  }

  handleRemove(event) {
    const target = event.currentTarget.dataset.target;
    this.setColumns(
      this.document.columns.filter((column) => lower(column.target) !== lower(target))
    );
    if (this.openTarget === target) {
      this.openTarget = undefined;
    }
  }

  handleDetails(event) {
    const target = event.currentTarget.dataset.target;
    this.openTarget = this.openTarget === target ? undefined : target;
  }

  handleSteps(event) {
    const target = event.currentTarget.dataset.target;
    const transforms = event.detail.transforms || [];
    this.changeColumn(target, (column) => {
      if (!column.source && typeof column.value !== 'string') {
        return null;
      }
      return { ...column, transforms };
    });
  }

  handleFixed(event) {
    const target = event.currentTarget.dataset.target;
    const value = event.detail.value || '';
    this.changeColumn(target, (column) => {
      const next = { ...column };
      if (value) {
        next.value = value;
        delete next.source;
      } else {
        delete next.value;
      }
      return next.source || typeof next.value === 'string' ? next : null;
    });
  }

  handleDefault(event) {
    const target = event.currentTarget.dataset.target;
    const value = event.detail.value || '';
    const defaults = this.document.defaults.filter(
      (entry) => lower(entry.target) !== lower(target)
    );
    this.update({ defaults: value ? defaults.concat({ target, value }) : defaults });
  }

  handleRequired(event) {
    const target = event.currentTarget.dataset.target;
    const checked = event.detail.checked;
    this.changeColumn(target, (column) => {
      if (!column.source && typeof column.value !== 'string') {
        return null;
      }
      const next = { ...column };
      if (checked) {
        next.required = true;
      } else {
        delete next.required;
      }
      return next;
    });
  }

  handleLookupField(event) {
    const target = event.currentTarget.dataset.target;
    const field = event.detail.value;
    if (!this.importing) {
      this.changeLookup(target, { field });
      return;
    }
    // Super Importer keeps the parent's field as `lookupField` (R-IT13).
    this.changeColumn(target, (column) => {
      const next = { ...column, lookupField: field };
      if (!field || field === 'Id') {
        delete next.lookupField;
      }
      return column.source ? next : null;
    });
  }

  /** Whether an empty cell clears the field (R-IT19, Super Importer only). */
  handleBlankClears(event) {
    const checked = event.detail.checked;
    this.changeColumn(event.currentTarget.dataset.target, (column) => {
      const next = { ...column, blankClears: true };
      if (!checked) {
        delete next.blankClears;
      }
      return column.source ? next : null;
    });
  }

  /** Create Field on a source not yet loaded (C-49d): Super Importer opens its dialog. */
  handleCreateField(event) {
    event.stopPropagation();
    this.dispatchEvent(
      new CustomEvent('createfield', { detail: { source: event.currentTarget.dataset.source } })
    );
  }

  /** Keeps a press on Create Field from picking the source up to drag. */
  handleCreateKey(event) {
    event.stopPropagation();
  }

  handleNotFound(event) {
    this.changeLookup(event.currentTarget.dataset.target, { notFound: event.detail.value });
  }

  changeLookup(target, change) {
    const field = this.fieldsByTarget[target] || {};
    this.changeColumn(target, (column) => {
      if (!column.source && typeof column.value !== 'string') {
        return null;
      }
      const lookup = {
        object: field.referenceTo,
        field: 'Id',
        notFound: 'reject',
        ...(column.lookup || {}),
        ...change
      };
      return { ...column, lookup };
    });
  }

  handleFieldQuery(event) {
    this.fieldQuery = event.detail.value || '';
  }

  handleNewKey(event) {
    this.newKey = (event.detail.value || '').trim();
  }

  handleAddKey() {
    if (!isPath(this.newKey)) {
      this.keyError = helpText('Core', 'Core_Mapper_KeyNotPath');
      return;
    }
    this.keyError = undefined;
    if (!this.targets.some((target) => lower(target.value) === lower(this.newKey))) {
      this.addedKeys = this.addedKeys.concat(this.newKey);
    }
    this.newKey = '';
  }

  keyError;

  handleMatch() {
    this.autoMatched = false;
    this.maybeAutoMatch();
  }

  /** Matches sources to targets once both are in (and again on Match Fields). */
  maybeAutoMatch() {
    if (this.autoMatched || this.sources.length === 0 || this.targets.length === 0) {
      return;
    }
    this.autoMatched = true;
    const before = this.document.columns.length;
    const columns = autoMatch(this.sources, this.targets, this.document.columns, score);
    if (columns.length !== before) {
      this.setColumns(columns);
      this.announcement = format(helpText('Core', 'Core_Mapper_Matched'), columns.length - before);
    }
  }

  get pendingGuesses() {
    return this.document.columns.filter((column) => column.guessed).length;
  }

  get hasGuesses() {
    return this.pendingGuesses > 0;
  }

  get guessText() {
    return format(helpText('Core', 'Core_Mapper_GuessPending'), this.pendingGuesses);
  }

  get skippedText() {
    return this.skipped > 0 ? format(helpText('Core', 'Core_Mapper_Skipped'), this.skipped) : '';
  }

  get problemTexts() {
    return problems(this.document).map((problem, index) => ({
      key: `problem-${index}`,
      text: this.problemText(problem)
    }));
  }

  get hasProblems() {
    return this.problemTexts.length > 0;
  }

  problemText(problem) {
    const args = problem.args || [];
    switch (problem.code) {
      case 'tooManyColumns':
        return format(helpText('Core', 'Core_Mapper_ProblemTooManyColumns'), ...args);
      case 'tooManyDefaults':
        return format(helpText('Core', 'Core_Mapper_ProblemTooManyDefaults'), ...args);
      case 'valueTooLong':
        return format(helpText('Core', 'Core_Mapper_ProblemValueTooLong'), ...args);
      case 'sampleTooBig':
        return format(helpText('Core', 'Core_Mapper_ProblemSampleTooBig'), ...args);
      case 'badPath':
        return format(helpText('Core', 'Core_Mapper_ProblemBadPath'), ...args);
      default:
        return helpText('Core', 'Core_Mapper_ProblemOther');
    }
  }

  notify() {
    this.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          document: serialize(this.document),
          columns: this.document.columns,
          pendingGuesses: this.pendingGuesses,
          problems: problems(this.document).length
        }
      })
    );
  }

  // ---- matching (R-IT2, R-IT8, R-IT9, R-IT16) -------------------------------------------------

  get match() {
    return this.document.match || {};
  }

  get matchBy() {
    return this.match.by || '';
  }

  get hasMatch() {
    return Boolean(this.match.by);
  }

  get matchNeedsField() {
    return this.matchBy === 'field' || this.matchBy === 'externalId';
  }

  get matchByOptions() {
    return [
      { label: helpText('Core', 'Core_Mapper_MatchByNone'), value: '' },
      { label: helpText('Core', 'Core_Mapper_MatchById'), value: 'id' },
      { label: helpText('Core', 'Core_Mapper_MatchByField'), value: 'field' },
      { label: helpText('Core', 'Core_Mapper_MatchByExternalId'), value: 'externalId' },
      { label: helpText('Core', 'Core_Mapper_MatchByDuplicateRules'), value: 'duplicateRules' }
    ];
  }

  get matchFieldOptions() {
    return this.targetFields
      .filter((field) => {
        if (this.matchBy === 'externalId') {
          return Boolean(field.externalId);
        }
        return MATCH_TYPES.includes(lower(field.dataType));
      })
      .map((field) => ({ label: field.label, value: field.apiName }));
  }

  get severalOptions() {
    return [
      { label: helpText('Core', 'Core_Mapper_SeveralReject'), value: 'reject' },
      { label: helpText('Core', 'Core_Mapper_SeveralNewest'), value: 'newest' }
    ];
  }

  get noneOptions() {
    return [
      { label: helpText('Core', 'Core_Mapper_NoneCreate'), value: 'create' },
      { label: helpText('Core', 'Core_Mapper_NoneSkip'), value: 'skip' },
      { label: helpText('Core', 'Core_Mapper_NoneReject'), value: 'reject' }
    ];
  }

  get matchSeveral() {
    return this.match.several || 'reject';
  }

  get matchNone() {
    return this.match.none || 'create';
  }

  get matchField() {
    return this.match.field || '';
  }

  handleMatchBy(event) {
    const by = event.detail.value;
    if (!by) {
      const next = { ...this.document };
      delete next.match;
      this.document = next;
      this.update({});
      return;
    }
    const match = { by, several: this.matchSeveral, none: this.matchNone };
    if ((by === 'field' || by === 'externalId') && this.match.field) {
      match.field = this.match.field;
    }
    this.update({ match });
  }

  handleMatchField(event) {
    this.update({ match: { ...this.match, field: event.detail.value } });
  }

  handleMatchSeveral(event) {
    this.update({ match: { ...this.match, several: event.detail.value } });
  }

  handleMatchNone(event) {
    this.update({ match: { ...this.match, none: event.detail.value } });
  }

  /** "This is an existing record when Email matches; if several match, ...; if none match, ..." */
  get matchSentence() {
    const by = this.matchBy;
    const field = this.targetFields.find((each) => each.apiName === this.match.field);
    const fieldLabel = field ? field.label : this.match.field || '';
    let when = '';
    if (by === 'id') {
      when = helpText('Core', 'Core_Mapper_MatchWhenId');
    } else if (by === 'duplicateRules') {
      when = helpText('Core', 'Core_Mapper_MatchWhenRules');
    } else {
      when = format(helpText('Core', 'Core_Mapper_MatchWhenField'), fieldLabel);
    }
    const several = this.severalOptions.find((option) => option.value === this.matchSeveral);
    const none = this.noneOptions.find((option) => option.value === this.matchNone);
    return format(
      helpText('Core', 'Core_Mapper_MatchSentence'),
      when,
      lowerFirst(several.label),
      lowerFirst(none.label)
    );
  }

  get matchRisk() {
    switch (this.matchBy) {
      case 'id':
        return helpText('Core', 'Core_Mapper_MatchRiskId');
      case 'field':
        return helpText('Core', 'Core_Mapper_MatchRiskField');
      case 'externalId':
        return helpText('Core', 'Core_Mapper_MatchRiskExternalId');
      default:
        return helpText('Core', 'Core_Mapper_MatchRiskRules');
    }
  }

  // ---- preview and Check Before Running (R-MAP4) ----------------------------------------------

  schedulePreview() {
    clearTimeout(this.previewTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.previewTimer = setTimeout(() => this.refreshPreview(), PREVIEW_DELAY_MS);
  }

  sampleRequest(count) {
    const names = this.sources.map((source) => source.name);
    return JSON.stringify(
      this.samples.slice(0, count).map((sample) => sampleValues(this.fromKind, sample, names))
    );
  }

  async refreshPreview() {
    if (!this.hasSamples || this.hasProblems) {
      this.previewSamples = [];
      return;
    }
    try {
      const result = await previewMap({
        definitionJson: serialize(this.document),
        samplesJson: this.sampleRequest(PREVIEW_SAMPLES)
      });
      this.previewSamples = (result && result.samples) || [];
      this.previewIndex = Math.min(this.previewIndex, Math.max(this.previewSamples.length - 1, 0));
      this.previewError = undefined;
    } catch (error) {
      this.previewSamples = [];
      this.previewError = errorText(error);
    }
  }

  get previewRows() {
    const sample = this.previewSamples[this.previewIndex];
    if (!sample) {
      return [];
    }
    const words = this.flagWords;
    return previewRows(this.document, this.fieldsByTarget, sample).map((row) => ({
      ...row,
      key: row.target,
      shown: row.value === '' ? '-' : row.value,
      hasFlags: row.flags.length > 0,
      badges: row.flags.map((flag) => ({
        key: `${row.target}-${flag}`,
        label: words[flag] || flag
      }))
    }));
  }

  get hasPreviewRows() {
    return this.previewRows.length > 0;
  }

  get sampleCounter() {
    return format(
      helpText('Core', 'Core_Mapper_SampleCounter'),
      this.previewIndex + 1,
      this.previewSamples.length
    );
  }

  get isFirstSample() {
    return this.previewIndex <= 0;
  }

  get isLastSample() {
    return this.previewIndex >= this.previewSamples.length - 1;
  }

  handlePrevious() {
    this.previewIndex = Math.max(this.previewIndex - 1, 0);
  }

  handleNext() {
    this.previewIndex = Math.min(this.previewIndex + 1, this.previewSamples.length - 1);
  }

  async handleCheck() {
    if (this.hasProblems || !this.hasSamples) {
      return;
    }
    this.checking = true;
    try {
      const result = await previewMap({
        definitionJson: serialize(this.document),
        samplesJson: this.sampleRequest(MAX_SAMPLES)
      });
      const samples = (result && result.samples) || [];
      const words = this.flagWords;
      this.checkCount = samples.length;
      this.checkResults = summarize(this.document, this.fieldsByTarget, samples).map((entry) => ({
        key: entry.target,
        text: format(
          helpText('Core', 'Core_Mapper_CheckLine'),
          entry.label,
          Object.keys(entry.flags)
            .map((flag) =>
              format(
                helpText('Core', 'Core_Mapper_CheckFlag'),
                words[flag] || flag,
                entry.flags[flag]
              )
            )
            .join('; '),
          entry.samples.join(', ')
        )
      }));
      this.previewError = undefined;
      this.announcement = this.checkSummary;
    } catch (error) {
      this.checkResults = undefined;
      this.previewError = errorText(error);
    } finally {
      this.checking = false;
    }
  }

  checkCount = 0;

  get checkDone() {
    return Array.isArray(this.checkResults);
  }

  get checkClean() {
    return this.checkDone && this.checkResults.length === 0;
  }

  get checkSummary() {
    if (!this.checkDone) {
      return '';
    }
    return this.checkResults.length === 0
      ? format(helpText('Core', 'Core_Mapper_CheckClean'), this.checkCount)
      : format(
          helpText('Core', 'Core_Mapper_CheckFound'),
          this.checkResults.length,
          this.checkCount
        );
  }

  get checkDisabled() {
    return this.checking || this.hasProblems || !this.hasSamples;
  }

  // ---- drag and drop ------------------------------------------------------------------------

  handlePointerDown(event) {
    this.drag.pointerDown(event);
  }

  handleDragKey(event) {
    this.drag.keyDown(event);
  }
}
