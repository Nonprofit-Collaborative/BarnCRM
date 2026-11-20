import { LightningElement, api } from 'lwc';
import saveDraft from '@salesforce/apex/ConnectorRecipesController.saveDraft';
import publish from '@salesforce/apex/ConnectorRecipesController.publish';
import setRunAs from '@salesforce/apex/ConnectorRecipesController.setRunAs';
import deleteRecipe from '@salesforce/apex/ConnectorRecipesController.deleteRecipe';
import runNow from '@salesforce/apex/ConnectorRecipesController.runNow';
import testRecipe from '@salesforce/apex/ConnectorRecipesController.testRecipe';
import getRun from '@salesforce/apex/ConnectorRecipesController.getRun';
import BarnConfirmModal from 'c/barnConfirmModal';
import {
  STEP_KINDS,
  RECORD_KINDS,
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
  statusVariant
} from 'c/connectorRecipeRules';
import { say as text } from 'c/connectorRecipeText';

const LIST_FIELDS = ['values', 'pathValues', 'query', 'headers', 'conditions'];

/**
 * The recipe editor of Super Connector (CN-02; canonical model R-CR1 to R-CR5; design Sections
 * 3.3, 3.4, 3.8 and 3.10). When (Run Now or a flow, with sample data), Then (the steps, nested
 * If steps shown in one list by c/connectorRecipeRules), Settings (Run As, with System behind a
 * confirmation), Test, Publish, Run Now and Delete. Every rule is checked here as you type and
 * again on the server; a value that holds a merge field is refused (F1).
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

  get runAsOptions() {
    return [
      { label: text('Connector_RunAs_Automation'), value: RUN_AS_AUTOMATION },
      { label: text('Connector_RunAs_System'), value: RUN_AS_SYSTEM }
    ];
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
        isCall: step.kind === 'callApp',
        isIf: step.kind === 'if',
        isStop: step.kind === 'stop',
        canNest: step.kind === 'if' && row.depth < 1,
        maps: step.kind === 'callApp' ? jsonMaps : recordMaps,
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
    this.document = updateStep(this.document, address, changes);
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
