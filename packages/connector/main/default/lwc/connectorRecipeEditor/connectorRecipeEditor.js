import { LightningElement, api } from 'lwc';
import saveDraft from '@salesforce/apex/ConnectorRecipesController.saveDraft';
import publish from '@salesforce/apex/ConnectorRecipesController.publish';
import setRunAs from '@salesforce/apex/ConnectorRecipesController.setRunAs';
import deleteRecipe from '@salesforce/apex/ConnectorRecipesController.deleteRecipe';
import runNow from '@salesforce/apex/ConnectorRecipesController.runNow';
import testRecipe from '@salesforce/apex/ConnectorRecipesController.testRecipe';
import getRun from '@salesforce/apex/ConnectorRecipesController.getRun';
import saveRecipeSettings from '@salesforce/apex/ConnectorRecipesController.saveRecipeSettings';
import pauseRecipe from '@salesforce/apex/ConnectorRecipesController.pauseRecipe';
import resumeRecipe from '@salesforce/apex/ConnectorRecipesController.resumeRecipe';
import retryAllFailed from '@salesforce/apex/ConnectorRecipesController.retryAllFailed';
import BarnConfirmModal from 'c/barnConfirmModal';
import {
  TRIGGERS,
  EVERY,
  DAYS,
  STAMPS,
  MODES,
  RUN_AS_USER,
  setTrigger,
  updateTrigger,
  runAsKey,
  STEP_KINDS,
  RECORD_KINDS,
  CALL_KINDS,
  METHODS,
  OPERATORS,
  OUTCOMES,
  RUN_AS_AUTOMATION,
  RUN_AS_SYSTEM,
  readDocument,
  flatten,
  addStep,
  removeStep,
  moveStep,
  updateStep,
  syncSlots,
  isPill,
  problems,
  pathSuggestions,
  readSample,
  readCodes,
  stepRows,
  statusVariant,
  importLimits
} from 'c/connectorRecipeRules';
import { say as text } from 'c/connectorRecipeText';

const LIST_FIELDS = ['values', 'pathValues', 'query', 'headers', 'conditions'];

/**
 * The recipe editor of Super Connector (CN-02, CN-03; canonical model R-CR1 to R-CR7; design
 * Sections 3.2, 3.3, 3.4, 3.7, 3.8 and 3.10). When (Run Now or a flow, a Schedule, or a Record
 * Change through a saved Find query, with sample data), Then (the steps, nested If steps shown in
 * one list by c/connectorRecipeRules), Settings (Run As, with System behind a confirmation and
 * Integration User once one is chosen), Run Settings (retries, auto-pause, run cleanup, the loop
 * guard), Pause, Resume, Retry All Failed, Test, Publish, Run Now and Delete. Every rule is
 * checked here as you type and again on the server; a value that holds a merge field is refused
 * (F1).
 */
export default class ConnectorRecipeEditor extends LightningElement {
  @api page;

  _recipe;
  recipeId;
  name = '';
  description = '';
  ownerId;
  runAs = RUN_AS_AUTOMATION;
  document = readDocument('');
  sampleText = '{}';
  runInput = '';
  testRecordId = '';
  sendForReal = false;
  testRun;
  retryAttempts = 3;
  pauseAfterFailures = 10;
  keepRunsDays = 30;
  ignoreOwnChanges = true;
  working = false;
  message;
  error;

  @api
  get recipe() {
    return this._recipe;
  }

  set recipe(value) {
    this._recipe = value;
    this.recipeId = value ? value.id : undefined;
    this.name = value ? value.name : '';
    this.description = value ? value.description || '' : '';
    this.ownerId = value ? value.recordOwnerId : undefined;
    this.runAs = value ? value.runAs || RUN_AS_AUTOMATION : RUN_AS_AUTOMATION;
    this.document = readDocument(value && value.draftJson);
    this.sampleText = JSON.stringify(this.document.trigger.sample || {}, null, 2);
    this.readSettings(value);
  }

  /** Run Settings as saved, with the defaults the server applies to a blank. */
  readSettings(value) {
    const pick = (field, fallback) => {
      const saved = value ? value[field] : undefined;
      return saved === undefined || saved === null ? fallback : saved;
    };
    this.retryAttempts = pick('retryAttempts', 3);
    this.pauseAfterFailures = pick('pauseAfterFailures', 10);
    this.keepRunsDays = pick('keepRunsDays', 30);
    this.ignoreOwnChanges = pick('ignoreOwnChanges', true);
  }

  labels = {
    get newTitle() {
      return text('Connector_Editor_NewTitle');
    },
    get details() {
      return text('Connector_Editor_Details');
    },
    get name() {
      return text('Connector_Editor_Name');
    },
    get description() {
      return text('Connector_Editor_Description');
    },
    get owner() {
      return text('Connector_Editor_Owner');
    },
    get ownerHelp() {
      return text('Connector_Editor_OwnerHelp');
    },
    get when() {
      return text('Connector_Editor_When');
    },
    get whenManual() {
      return text('Connector_Editor_WhenManual');
    },
    get whenSchedule() {
      return text('Connector_Editor_WhenSchedule');
    },
    get whenRecord() {
      return text('Connector_Editor_WhenRecord');
    },
    get whenWebhook() {
      return text('Connector_Editor_WhenWebhook');
    },
    get whenAppPoll() {
      return text('Connector_Editor_WhenAppPoll');
    },
    get urlFrom() {
      return text('Connector_Editor_UrlFrom');
    },
    get urlFromHelp() {
      return text('Connector_Editor_UrlFromHelp');
    },
    get triggerKind() {
      return text('Connector_Editor_TriggerKind');
    },
    get every() {
      return text('Connector_Editor_Every');
    },
    get at() {
      return text('Connector_Editor_At');
    },
    get day() {
      return text('Connector_Editor_Day');
    },
    get on() {
      return text('Connector_Editor_On');
    },
    get mode() {
      return text('Connector_Editor_Mode');
    },
    get limit() {
      return text('Connector_Editor_Limit');
    },
    get limitHelp() {
      return text('Connector_Editor_LimitHelp');
    },
    get runAsHelp() {
      return text('Connector_Editor_RunAsHelp');
    },
    get runSettings() {
      return text('Connector_Editor_RunSettings');
    },
    get retryAttempts() {
      return text('Connector_Editor_RetryAttempts');
    },
    get retryAttemptsHelp() {
      return text('Connector_Editor_RetryAttemptsHelp');
    },
    get pauseAfter() {
      return text('Connector_Editor_PauseAfter');
    },
    get pauseAfterHelp() {
      return text('Connector_Editor_PauseAfterHelp');
    },
    get keepDays() {
      return text('Connector_Editor_KeepDays');
    },
    get keepDaysHelp() {
      return text('Connector_Editor_KeepDaysHelp');
    },
    get ignoreOwn() {
      return text('Connector_Editor_IgnoreOwn');
    },
    get ignoreOwnHelp() {
      return text('Connector_Editor_IgnoreOwnHelp');
    },
    get saveSettings() {
      return text('Connector_Editor_SaveSettings');
    },
    get pause() {
      return text('Connector_Editor_Pause');
    },
    get resume() {
      return text('Connector_Editor_Resume');
    },
    get retryAll() {
      return text('Connector_Editor_RetryAll');
    },
    get sample() {
      return text('Connector_Editor_Sample');
    },
    get sampleHelp() {
      return text('Connector_Editor_SampleHelp');
    },
    get then() {
      return text('Connector_Editor_Then');
    },
    get noSteps() {
      return text('Connector_Editor_NoSteps');
    },
    get addStep() {
      return text('Connector_Editor_AddStep');
    },
    get stepName() {
      return text('Connector_Editor_StepName');
    },
    get moveUp() {
      return text('Connector_Editor_MoveUp');
    },
    get moveDown() {
      return text('Connector_Editor_MoveDown');
    },
    get remove() {
      return text('Connector_Editor_Remove');
    },
    get pathsHint() {
      return text('Connector_Editor_PathsHint');
    },
    get savedQuery() {
      return text('Connector_Editor_SavedQuery');
    },
    get conditionValue() {
      return text('Connector_Editor_ConditionValue');
    },
    get stopIfNone() {
      return text('Connector_Editor_StopIfNone');
    },
    get map() {
      return text('Connector_Editor_Map');
    },
    get input() {
      return text('Connector_Editor_Input');
    },
    get recordId() {
      return text('Connector_Editor_RecordId');
    },
    get connection() {
      return text('Connector_Editor_Connection');
    },
    get method() {
      return text('Connector_Editor_Method');
    },
    get path() {
      return text('Connector_Editor_Path');
    },
    get pathHelp() {
      return text('Connector_Editor_PathHelp');
    },
    get slotValue() {
      return text('Connector_Editor_SlotValue');
    },
    get valueHelp() {
      return text('Connector_Editor_ValueHelp');
    },
    get queryParams() {
      return text('Connector_Editor_QueryParams');
    },
    get headers() {
      return text('Connector_Editor_Headers');
    },
    get entryName() {
      return text('Connector_Editor_EntryName');
    },
    get entryValue() {
      return text('Connector_Editor_EntryValue');
    },
    get addEntry() {
      return text('Connector_Editor_AddEntry');
    },
    get bodyMap() {
      return text('Connector_Editor_BodyMap');
    },
    get bodyInput() {
      return text('Connector_Editor_BodyInput');
    },
    get success() {
      return text('Connector_Editor_Success');
    },
    get successHelp() {
      return text('Connector_Editor_SuccessHelp');
    },
    get notFoundOk() {
      return text('Connector_Editor_NotFoundOk');
    },
    get template() {
      return text('Connector_Editor_Template');
    },
    get templateHelp() {
      return text('Connector_Editor_TemplateHelp');
    },
    get rows() {
      return text('Connector_Editor_Rows');
    },
    get rowsHelp() {
      return text('Connector_Editor_RowsHelp');
    },
    get limits() {
      return text('Connector_Editor_Limits');
    },
    get limitsHelp() {
      return text('Connector_Editor_LimitsHelp');
    },
    get match() {
      return text('Connector_Editor_Match');
    },
    get conditions() {
      return text('Connector_Editor_Conditions');
    },
    get conditionPath() {
      return text('Connector_Editor_ConditionPath');
    },
    get operator() {
      return text('Connector_Editor_Operator');
    },
    get value() {
      return text('Connector_Editor_Value');
    },
    get addThen() {
      return text('Connector_Editor_AddThen');
    },
    get addOtherwise() {
      return text('Connector_Editor_AddOtherwise');
    },
    get outcome() {
      return text('Connector_Editor_Outcome');
    },
    get stopMessage() {
      return text('Connector_Editor_StopMessage');
    },
    get settings() {
      return text('Connector_Editor_Settings');
    },
    get runAs() {
      return text('Connector_Editor_RunAs');
    },
    get saveFirst() {
      return text('Connector_Editor_SaveFirst');
    },
    get problemsHeading() {
      return text('Connector_Editor_Problems');
    },
    get save() {
      return text('Connector_Editor_Save');
    },
    get publish() {
      return text('Connector_Editor_Publish');
    },
    get close() {
      return text('Connector_Editor_Close');
    },
    get deleteLabel() {
      return text('Connector_Editor_Delete');
    },
    get testHeading() {
      return text('Connector_Editor_TestHeading');
    },
    get testIntro() {
      return text('Connector_Editor_TestIntro');
    },
    get testRecord() {
      return text('Connector_Editor_TestRecord');
    },
    get sendForReal() {
      return text('Connector_Editor_SendForReal');
    },
    get test() {
      return text('Connector_Editor_Test');
    },
    get checkResult() {
      return text('Connector_Editor_CheckResult');
    },
    get runHeading() {
      return text('Connector_Editor_RunHeading');
    },
    get runData() {
      return text('Connector_Editor_RunData');
    },
    get runNow() {
      return text('Connector_Editor_RunNow');
    },
    get working() {
      return text('Connector_Editor_Working');
    }
  };

  get title() {
    return this.recipeId ? this.name : this.labels.newTitle;
  }

  get canManage() {
    return Boolean(this.page && this.page.canManage);
  }

  get readOnly() {
    return !this.canManage;
  }

  get saved() {
    return Boolean(this.recipeId);
  }

  get active() {
    return Boolean(this._recipe && this._recipe.status === 'Active');
  }

  get statusLabel() {
    const status = this._recipe ? this._recipe.status : 'Draft';
    return text(`Connector_Status_${status}`);
  }

  get statusTone() {
    return statusVariant(this._recipe ? this._recipe.status : 'Draft');
  }

  get runAsChosen() {
    if (!this._recipe || !this._recipe.runAsChosenBy) {
      return '';
    }
    const at = this._recipe.runAsChosenAt
      ? new Date(this._recipe.runAsChosenAt).toLocaleString()
      : '';
    return text('Connector_Editor_RunAsChosen', this._recipe.runAsChosenBy, at);
  }

  // -------------------------------------------------------------------------------------------
  // Options
  // -------------------------------------------------------------------------------------------

  get addOptions() {
    return STEP_KINDS.map((kind) => ({ label: text(kind.key), value: kind.value }));
  }

  /** Integration User is offered once a user is chosen and active, or while it is the choice. */
  get runAsOptions() {
    const values = [RUN_AS_AUTOMATION, RUN_AS_SYSTEM];
    if ((this.page && this.page.integrationUserReady) || this.runAs === RUN_AS_USER) {
      values.push(RUN_AS_USER);
    }
    return values.map((value) => ({ label: text(runAsKey(value)), value }));
  }

  // -------------------------------------------------------------------------------------------
  // When: the trigger
  // -------------------------------------------------------------------------------------------

  get trigger() {
    return this.document.trigger || {};
  }

  get triggerOptions() {
    return TRIGGERS.map((entry) => ({ label: text(entry.key), value: entry.value }));
  }

  get isManual() {
    return !this.isSchedule && !this.isRecordChange && !this.isWebhook && !this.isAppPoll;
  }

  get isWebhook() {
    return this.trigger.kind === 'webhook';
  }

  get isAppPoll() {
    return this.trigger.kind === 'appPoll';
  }

  get isSchedule() {
    return this.trigger.kind === 'schedule';
  }

  get isRecordChange() {
    return this.trigger.kind === 'record';
  }

  get everyOptions() {
    return EVERY.map((value) => ({ label: text(`Connector_Every_${value}`), value }));
  }

  get dayOptions() {
    return DAYS.map((value) => ({ label: text(`Connector_Day_${value}`), value }));
  }

  get stampOptions() {
    return STAMPS.map((value) => ({ label: text(`Connector_On_${value}`), value }));
  }

  get modeOptions() {
    return MODES.map((value) => ({ label: text(`Connector_Mode_${value}`), value }));
  }

  get timed() {
    return this.trigger.every === 'day' || this.trigger.every === 'week';
  }

  get weekly() {
    return this.trigger.every === 'week';
  }

  /** The time input works in HH:mm:ss.SSS; the document keeps HH:mm. */
  get atValue() {
    return this.trigger.at ? `${this.trigger.at}:00.000` : '';
  }

  get nextRunText() {
    const recipe = this._recipe;
    return recipe && recipe.status === 'Active' && recipe.nextRunAt
      ? text('Connector_Editor_NextRun', new Date(recipe.nextRunAt).toLocaleString())
      : '';
  }

  get failuresText() {
    const count = this._recipe ? this._recipe.consecutiveFailures : 0;
    return count ? text('Connector_Editor_Failures', count) : '';
  }

  get canPause() {
    return this.active;
  }

  get canResume() {
    return Boolean(
      this._recipe &&
      (this._recipe.status === 'Paused' || this._recipe.status === 'PausedByFailures')
    );
  }

  get queryOptions() {
    return ((this.page && this.page.queries) || []).map((query) => ({
      label: query.label,
      value: query.value
    }));
  }

  mapOptions(kind) {
    return ((this.page && this.page.maps) || [])
      .filter((option) => option.kind === kind)
      .map((option) => ({ label: option.label, value: option.value }));
  }

  get connectionOptions() {
    return ((this.page && this.page.connections) || []).map((option) => ({
      label: option.label,
      value: option.value
    }));
  }

  get templateOptions() {
    return ((this.page && this.page.templates) || []).map((option) => ({
      label: option.label,
      value: option.value
    }));
  }

  get methodOptions() {
    return METHODS.map((method) => ({ label: method, value: method }));
  }

  get operatorOptions() {
    return OPERATORS.map((operator) => ({
      label: text(`Connector_Operator_${operator.replace(/ /g, '_')}`),
      value: operator
    }));
  }

  get outcomeOptions() {
    return OUTCOMES.map((outcome) => ({
      label: text(`Connector_Status_${outcome}`),
      value: outcome
    }));
  }

  get matchOptions() {
    return [
      { label: text('Connector_Editor_MatchAll'), value: 'all' },
      { label: text('Connector_Editor_MatchAny'), value: 'any' }
    ];
  }

  // -------------------------------------------------------------------------------------------
  // The steps as rows
  // -------------------------------------------------------------------------------------------

  get rows() {
    const recordMaps = this.mapOptions('record');
    const jsonMaps = this.mapOptions('json');
    return flatten(this.document).map((row) => {
      const step = row.step;
      const kind = STEP_KINDS.find((entry) => entry.value === step.kind);
      const hints = pathSuggestions(this.document, step);
      // A Find step's `query` is its query document, not a list: only arrays are entries.
      const list = (field) =>
        (Array.isArray(step[field]) ? step[field] : []).map((entry, index) => ({
          ...entry,
          index,
          key: `${row.key}-${field}-${index}`,
          shown: entry.path || entry.value || '',
          valueShown: !/null/.test(entry.operator || '')
        }));
      return {
        key: row.key,
        address: JSON.stringify(row.address),
        step,
        indentClass: `slds-var-m-bottom_small slds-box slds-box_x-small connector-depth-${row.depth}`,
        heading: text('Connector_Editor_StepHeading', kind ? text(kind.key) : step.kind, step.id),
        branchLabel:
          row.depth > 0
            ? text(
                row.branch === 'then' ? 'Connector_Editor_InThen' : 'Connector_Editor_InOtherwise'
              )
            : '',
        isFind: step.kind === 'find',
        isRecord: RECORD_KINDS.includes(step.kind),
        isUpdate: step.kind === 'update',
        isCall: CALL_KINDS.includes(step.kind),
        isCallApp: step.kind === 'callApp',
        pathHelp:
          step.kind === 'sendWebhook'
            ? text('Connector_Editor_WebhookPathHelp')
            : this.labels.pathHelp,
        isIf: step.kind === 'if',
        isStop: step.kind === 'stop',
        isImport: step.kind === 'importRows',
        limits:
          step.kind === 'importRows'
            ? importLimits(step).map((limit) => ({
                ...limit,
                label: text(limit.label),
                help: text(
                  limit.key === 'rows'
                    ? 'Connector_Editor_MostRowsHelp'
                    : 'Connector_Editor_MostHelp'
                )
              }))
            : [],
        canNest: step.kind === 'if' && row.depth < 1,
        maps: CALL_KINDS.includes(step.kind) ? jsonMaps : recordMaps,
        hints: hints.join(', '),
        findConditions: this.findConditions(step),
        pathValues: list('pathValues'),
        query: list('query'),
        headers: list('headers'),
        conditions: list('conditions'),
        successText: (step.success || []).join(', ')
      };
    });
  }

  /** A Find step's saved conditions, each with the value path that fills it, if any. */
  findConditions(step) {
    const filter = (step.query && step.query.filter) || {};
    return (filter.conditions || []).map((condition) => {
      const value = (step.values || []).find(
        (entry) => String(entry.condition) === String(condition.id)
      );
      return {
        id: String(condition.id),
        label: text(
          'Connector_Editor_ConditionLabel',
          condition.field,
          condition.operator,
          condition.value || ''
        ),
        path: value ? value.path : ''
      };
    });
  }

  get noSteps() {
    return !this.document.steps.length;
  }

  get problemTexts() {
    return problems(this.document).map((problem) => text(problem.key, ...problem.args));
  }

  get hasProblems() {
    return this.problemTexts.length > 0;
  }

  get problemSummary() {
    return this.problemTexts.join(' ');
  }

  get sampleInvalid() {
    return readSample(this.sampleText) === undefined;
  }

  get testRows() {
    return this.testRun ? stepRows(this.testRun.stepLogJson, this.testRun.resultsJson) : [];
  }

  get testStatus() {
    return this.testRun ? text(`Connector_Status_${this.testRun.status}`) : '';
  }

  get testTone() {
    return this.testRun ? statusVariant(this.testRun.status) : 'neutral';
  }

  // -------------------------------------------------------------------------------------------
  // Editing
  // -------------------------------------------------------------------------------------------

  addressOf(event) {
    return JSON.parse(event.target.dataset.address);
  }

  handleName(event) {
    this.name = event.target.value;
  }

  handleDescription(event) {
    this.description = event.target.value;
  }

  handleOwner(event) {
    this.ownerId = event.detail ? event.detail.recordId : undefined;
  }

  handleSample(event) {
    this.sampleText = event.target.value;
    const sample = readSample(this.sampleText);
    if (sample !== undefined) {
      this.document = { ...this.document, trigger: { ...this.document.trigger, sample } };
    }
  }

  handleTriggerKind(event) {
    this.document = setTrigger(this.document, event.detail.value);
  }

  /** A trigger field: data-field names it; the time arrives as HH:mm:ss.SSS. */
  handleTriggerField(event) {
    const field = event.target.dataset.field;
    let value = event.detail.value;
    if (field === 'at') {
      value = String(value || '').slice(0, 5);
    }
    if (field === 'limit') {
      value = value === '' || value === null || value === undefined ? undefined : Number(value);
    }
    this.document = updateTrigger(this.document, { [field]: value });
  }

  /** A Record Change trigger's saved Find query: its document is copied into the trigger. */
  handleTriggerQuery(event) {
    const chosen = ((this.page && this.page.queries) || []).find(
      (query) => query.value === event.detail.value
    );
    let query = null;
    try {
      query = chosen ? JSON.parse(chosen.document) : null;
    } catch {
      query = null;
    }
    this.document = updateTrigger(this.document, { savedQuery: event.detail.value, query });
  }

  handleSetting(event) {
    const field = event.target.dataset.field;
    this[field] =
      event.target.type === 'checkbox' || event.target.type === 'toggle'
        ? event.target.checked
        : event.detail.value;
  }

  handleAdd(event) {
    this.document = addStep(this.document, event.detail.value);
  }

  handleAddInside(event) {
    this.document = addStep(
      this.document,
      event.detail.value,
      this.addressOf(event),
      event.target.dataset.branch
    );
  }

  handleRemove(event) {
    this.document = removeStep(this.document, this.addressOf(event));
  }

  handleMove(event) {
    this.document = moveStep(
      this.document,
      this.addressOf(event),
      Number(event.target.dataset.delta)
    );
  }

  /** A plain field of a step: data-field names it; checkboxes give `checked`. */
  handleField(event) {
    const field = event.target.dataset.field;
    const value =
      event.target.type === 'checkbox' || event.target.type === 'toggle'
        ? event.target.checked
        : event.detail.value;
    const changes = { [field]: value };
    const address = this.addressOf(event);
    if (field === 'path') {
      const step = this.stepAt(address);
      changes.pathValues = syncSlots(value, step.pathValues);
    }
    if (field === 'success') {
      const codes = readCodes(value);
      changes.success = codes === undefined ? [value] : codes;
    }
    // An address from the data replaces the path, its values and its query (R-CR11).
    if (field === 'urlFrom' && value) {
      Object.assign(changes, { path: '', pathValues: [], query: [] });
    }
    this.document = updateStep(this.document, address, changes);
  }

  /** One Load Rows limit: data-limit names it; a blank keeps the default (R-CR9). */
  handleLimit(event) {
    const address = this.addressOf(event);
    const limits = { ...(this.stepAt(address).limits || {}) };
    const typed = event.detail.value;
    if (typed === '' || typed === null || typed === undefined) {
      delete limits[event.target.dataset.limit];
    } else {
      limits[event.target.dataset.limit] = Number(typed);
    }
    this.document = updateStep(this.document, address, { limits });
  }

  /** The Webhook card's Event Id and reply. */
  handleTriggerChange(event) {
    this.document = updateTrigger(this.document, event.detail);
  }

  /** A Find step's saved query: its document is copied into the step. */
  handleQuery(event) {
    const chosen = ((this.page && this.page.queries) || []).find(
      (query) => query.value === event.detail.value
    );
    let query = null;
    try {
      query = chosen ? JSON.parse(chosen.document) : null;
    } catch {
      query = null;
    }
    this.document = updateStep(this.document, this.addressOf(event), {
      savedQuery: event.detail.value,
      query,
      values: []
    });
  }

  handleConditionPath(event) {
    const address = this.addressOf(event);
    const step = this.stepAt(address);
    const condition = event.target.dataset.condition;
    const values = (step.values || []).filter((entry) => String(entry.condition) !== condition);
    if (event.detail.value) {
      values.push({ condition: Number(condition), path: event.detail.value });
    }
    this.document = updateStep(this.document, address, { values });
  }

  /** One entry of a list field (path values, query, headers, conditions). */
  handleEntry(event) {
    const { list, index, field } = event.target.dataset;
    if (!LIST_FIELDS.includes(list)) {
      return;
    }
    const address = this.addressOf(event);
    const entries = [...(this.stepAt(address)[list] || [])];
    const entry = { ...entries[Number(index)] };
    if (field === 'shown') {
      const typed = event.detail.value;
      delete entry.path;
      delete entry.value;
      if (isPill(typed)) {
        entry.path = typed;
      } else {
        entry.value = typed;
      }
    } else {
      entry[field] = event.detail.value;
    }
    entries[Number(index)] = entry;
    this.document = updateStep(this.document, address, { [list]: entries });
  }

  handleAddEntry(event) {
    const list = event.target.dataset.list;
    const address = this.addressOf(event);
    const entries = [...(this.stepAt(address)[list] || [])];
    entries.push(
      list === 'conditions'
        ? { path: 'trigger', operator: 'equals', value: '' }
        : { name: '', value: '' }
    );
    this.document = updateStep(this.document, address, { [list]: entries });
  }

  handleRemoveEntry(event) {
    const { list, index } = event.target.dataset;
    const address = this.addressOf(event);
    const entries = [...(this.stepAt(address)[list] || [])];
    entries.splice(Number(index), 1);
    this.document = updateStep(this.document, address, { [list]: entries });
  }

  stepAt(address) {
    let list = this.document.steps;
    let step;
    address.forEach(([index], position) => {
      step = list[index];
      if (position < address.length - 1) {
        list = step[address[position + 1][1]];
      }
    });
    return step;
  }

  handleTestRecord(event) {
    this.testRecordId = event.target.value;
  }

  handleSendForReal(event) {
    this.sendForReal = event.target.checked;
  }

  handleRunInput(event) {
    this.runInput = event.target.value;
  }

  // -------------------------------------------------------------------------------------------
  // Server calls
  // -------------------------------------------------------------------------------------------

  async save() {
    const saved = await saveDraft({
      recipeId: this.recipeId,
      name: this.name,
      description: this.description,
      draftJson: JSON.stringify(this.document),
      recordOwnerId: this.ownerId
    });
    this.recipeId = saved.id;
    this._recipe = saved;
    return saved;
  }

  handleSave() {
    return this.work(async () => {
      const saved = await this.save();
      this.changed(saved.id, text('Connector_Editor_Saved'));
    });
  }

  handlePublish() {
    return this.work(async () => {
      await this.save();
      const published = await publish({ recipeId: this.recipeId });
      this._recipe = published;
      this.changed(published.id, text('Connector_Editor_Published', published.version));
    });
  }

  async handleRunAs(event) {
    const chosen = event.detail.value;
    if (!this.recipeId || chosen === this.runAs) {
      return;
    }
    let confirmed = false;
    if (chosen === RUN_AS_SYSTEM) {
      confirmed = await BarnConfirmModal.open({
        size: 'small',
        label: text('Connector_RunAs_ConfirmTitle'),
        message: text('Connector_RunAs_ConfirmMessage', this.name),
        confirmLabel: text('Connector_RunAs_ConfirmButton'),
        confirmVariant: 'destructive',
        cancelLabel: text('Connector_Editor_Close')
      });
      if (!confirmed) {
        this.runAs = this._recipe ? this._recipe.runAs : RUN_AS_AUTOMATION;
        return;
      }
    }
    await this.work(async () => {
      const updated = await setRunAs({ recipeId: this.recipeId, runAs: chosen, confirmed });
      this._recipe = updated;
      this.runAs = updated.runAs;
      this.changed(updated.id, text('Connector_Editor_RunAsSaved'));
    });
  }

  handleSaveSettings() {
    return this.work(async () => {
      const updated = await saveRecipeSettings({
        recipeId: this.recipeId,
        retryAttempts: Number(this.retryAttempts),
        pauseAfterFailures: Number(this.pauseAfterFailures),
        keepRunsDays: Number(this.keepRunsDays),
        ignoreOwnChanges: this.ignoreOwnChanges !== false
      });
      this._recipe = updated;
      this.readSettings(updated);
      this.changed(updated.id, text('Connector_Editor_SettingsSaved'));
    });
  }

  handlePause() {
    return this.work(async () => {
      const updated = await pauseRecipe({ recipeId: this.recipeId });
      this._recipe = updated;
      this.changed(updated.id, text('Connector_Editor_Paused', this.name));
    });
  }

  handleResume() {
    return this.work(async () => {
      const updated = await resumeRecipe({ recipeId: this.recipeId });
      this._recipe = updated;
      this.changed(updated.id, text('Connector_Editor_Resumed', this.name));
    });
  }

  handleRetryAll() {
    return this.work(async () => {
      const count = await retryAllFailed({ recipeId: this.recipeId });
      this.message = text('Connector_Editor_RetriedAll', count);
    });
  }

  handleTest() {
    return this.work(async () => {
      await this.save();
      this.testRun = await testRecipe({
        recipeId: this.recipeId,
        sampleJson: this.sampleText,
        recordId: this.testRecordId,
        sendForReal: this.sendForReal
      });
      this.message = text('Connector_Editor_TestQueued');
    });
  }

  handleCheckResult() {
    return this.work(async () => {
      this.testRun = (await getRun({ runId: this.testRun.id })) || this.testRun;
    });
  }

  handleRunNow() {
    return this.work(async () => {
      const run = await runNow({ recipeId: this.recipeId, inputJson: this.runInput });
      this.message = text('Connector_Editor_RunQueued', run.name);
    });
  }

  async handleDelete() {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: text('Connector_Editor_DeleteTitle', this.name),
      message: text('Connector_Editor_DeleteMessage', this.name),
      confirmLabel: text('Connector_Editor_Delete'),
      confirmVariant: 'destructive',
      cancelLabel: text('Connector_Editor_Close')
    });
    if (confirmed) {
      await this.work(async () => {
        await deleteRecipe({ recipeId: this.recipeId });
        this.dispatchEvent(
          new CustomEvent('changed', {
            detail: { deleted: true, message: text('Connector_Editor_Deleted', this.name) }
          })
        );
      });
    }
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent('close'));
  }

  changed(recipeId, message) {
    this.message = message;
    this.dispatchEvent(new CustomEvent('changed', { detail: { recipeId, message } }));
  }

  async work(call) {
    this.message = undefined;
    this.error = undefined;
    this.working = true;
    try {
      await call();
    } catch (failure) {
      this.error =
        (failure && failure.body && failure.body.message) || text('Connector_Error_Unexpected');
    } finally {
      this.working = false;
    }
  }
}
