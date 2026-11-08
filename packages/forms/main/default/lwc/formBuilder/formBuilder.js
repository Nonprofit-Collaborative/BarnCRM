import { LightningElement, api } from 'lwc';
import getBuilder from '@salesforce/apex/FormBuilderController.getBuilder';
import getObjects from '@salesforce/apex/FormBuilderController.getObjects';
import getFields from '@salesforce/apex/FormBuilderController.getFields';
import saveDraft from '@salesforce/apex/FormBuilderController.saveDraft';
import publish from '@salesforce/apex/FormBuilderController.publish';
import {
  CONTEXT_LINK,
  PUBLIC_DEFAULTS,
  checkDefinition,
  parseDefinition,
  serializeDefinition
} from 'c/formDefinition';
import {
  addField,
  addRecord,
  addStep,
  conditionFrom,
  conditionParts,
  earlierFields,
  moveField,
  moveStep,
  optionsFromText,
  optionsToText,
  recordObject,
  removeField,
  removeRecord,
  removeStep,
  setCondition,
  setLink,
  updateField,
  updateRecord,
  updateStep
} from 'c/formBuilderModel';
import {
  HELP,
  KIND_LABELS,
  LABELS,
  MODE_OPTIONS,
  OPERATOR_OPTIONS,
  PUBLIC_SETTING_TEXT,
  TYPE_OPTIONS,
  contextLinkLabel,
  messageFrom,
  nestedKept,
  notWrittenLabel,
  onMatchOptions,
  problemText,
  publishedVersion,
  ruleOptions
} from 'c/formText';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';

const NEEDS_NO_VALUE = new Set(['isBlank', 'isNotBlank']);
const NONE = '';

/**
 * The Form Builder panel on a form (C-42a; ADR-0175 `0175-forms-module.md`, decision 12): the
 * steps and their questions, the records the answers are written to, and when a step or a
 * question shows. Every change goes through `c/formBuilderModel` and is checked with
 * `c/formDefinition` as it is made; Save Draft stores it, Publish makes it the version people
 * fill in, once nothing is left to fix.
 */
export default class FormBuilder extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP);
  labels = LABELS;
  form;
  definition;
  objects = [];
  fieldsByObject = {};
  selection = { step: 0, field: null, record: null };
  loading = true;
  busy = false;
  dirty = false;
  previewing = false;
  errorMessage;
  resultMessage;

  /** The draft as the Form Runner previews it; it follows every change. */
  get previewJson() {
    return serializeDefinition(this.definition);
  }

  handlePreview() {
    this.previewing = !this.previewing;
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      const [form, objects] = await Promise.all([
        getBuilder({ formId: this.recordId }),
        getObjects()
      ]);
      this.objects = objects || [];
      this.show(form);
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
    this.loading = false;
  }

  show(form) {
    this.form = form;
    const parsed = parseDefinition(form.definition);
    this.definition = parsed.definition || parseDefinition('').definition;
    this.dirty = false;
    this.loadRecordFields();
  }

  /** The fields of every object a record writes, fetched once each. */
  loadRecordFields() {
    this.definition.records.map(recordObject).forEach((objectName) => this.fieldsFor(objectName));
  }

  async fieldsFor(objectName) {
    if (!objectName || this.fieldsByObject[objectName]) {
      return;
    }
    this.fieldsByObject = { ...this.fieldsByObject, [objectName]: [] };
    try {
      const fields = await getFields({ objectName });
      this.fieldsByObject = { ...this.fieldsByObject, [objectName]: fields || [] };
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  change(definition) {
    this.definition = definition;
    this.dirty = true;
    this.resultMessage = '';
    this.loadRecordFields();
  }

  // ---- what the page shows ----

  get loaded() {
    return !this.loading && Boolean(this.definition);
  }

  get canEdit() {
    return Boolean(this.form && this.form.canEdit);
  }

  get readOnly() {
    return !this.canEdit;
  }

  get statusLine() {
    if (!this.form) {
      return '';
    }
    return this.form.publishedVersion
      ? `${this.form.status}. ${publishedVersion(this.form.publishedVersion)}`
      : this.form.status;
  }

  get problems() {
    return checkDefinition(this.definition).map((problem, index) => ({
      id: `${problem.code}-${index}`,
      text: problemText(problem)
    }));
  }

  get hasProblems() {
    return this.problems.length > 0;
  }

  get saveDisabled() {
    return this.busy || !this.dirty;
  }

  get publishDisabled() {
    return this.busy || this.hasProblems;
  }

  // ---- public form settings (C-42b) ----

  get publicText() {
    return PUBLIC_SETTING_TEXT;
  }

  /** The `public` block with its defaults shown, so no setting is blank. */
  get publicSettings() {
    const settings = this.definition.public || {};
    return {
      enabled: settings.enabled === true,
      minSeconds: settings.minSeconds ?? PUBLIC_DEFAULTS.minSeconds,
      hourlyLimit: settings.hourlyLimit ?? PUBLIC_DEFAULTS.hourlyLimit,
      confirmation: settings.confirmation || '',
      saveForLater: settings.saveForLater === true,
      resumeDays: settings.resumeDays ?? PUBLIC_DEFAULTS.resumeDays
    };
  }

  handlePublicChange(event) {
    const setting = event.target.dataset.setting;
    const settings = { ...(this.definition.public || {}) };
    if (setting === 'enabled' || setting === 'saveForLater') {
      settings[setting] = event.detail.checked;
    } else if (setting === 'confirmation') {
      settings.confirmation = event.detail.value;
    } else {
      const text = String(event.detail.value ?? '').trim();
      settings[setting] = text === '' ? undefined : Number(text);
    }
    Object.keys(settings).forEach((key) => {
      if (settings[key] === undefined || settings[key] === '') {
        delete settings[key];
      }
    });
    this.change({ ...this.definition, public: settings });
  }

  get isPublishedPublic() {
    return Boolean(this.form && this.form.isPublic);
  }

  get publicLinks() {
    return (this.form && this.form.publicLinks) || [];
  }

  get noSite() {
    return this.publicLinks.length === 0;
  }

  get steps() {
    const { step: selectedStep, field: selectedField, record: selectedRecord } = this.selection;
    return this.definition.steps.map((step, stepIndex) => ({
      key: step.key,
      index: stepIndex,
      title: step.title || step.key,
      selected: selectedRecord === null && selectedField === null && selectedStep === stepIndex,
      className: this.itemClass(
        selectedRecord === null && selectedField === null && selectedStep === stepIndex
      ),
      empty: step.fields.length === 0,
      fields: step.fields.map((field, fieldIndex) => {
        const selected =
          selectedRecord === null && selectedStep === stepIndex && selectedField === fieldIndex;
        return {
          key: field.key,
          stepIndex,
          index: fieldIndex,
          label: field.label || field.key,
          selected,
          className: this.itemClass(selected)
        };
      })
    }));
  }

  get records() {
    return this.definition.records.map((record, index) => {
      const selected = this.selection.record === index;
      return {
        key: record.key,
        index,
        label: `${record.key} (${KIND_LABELS[record.kind] || record.kind})`,
        className: this.itemClass(selected)
      };
    });
  }

  itemClass(selected) {
    return selected
      ? 'slds-button slds-button_brand slds-button_stretch slds-var-m-bottom_xx-small'
      : 'slds-button slds-button_neutral slds-button_stretch slds-var-m-bottom_xx-small';
  }

  get addRecordItems() {
    const kinds = new Set(this.definition.records.map((record) => record.kind));
    return ['person', 'organization', 'related']
      .filter((kind) => kind === 'related' || !kinds.has(kind))
      .map((kind) => ({ value: kind, label: KIND_LABELS[kind] }));
  }

  get editingStep() {
    return this.selection.record === null && this.selection.field === null && Boolean(this.step);
  }

  get editingField() {
    return this.selection.record === null && Boolean(this.field);
  }

  get editingRecord() {
    return Boolean(this.record);
  }

  get step() {
    return this.definition.steps[this.selection.step];
  }

  get field() {
    return this.selection.field === null || !this.step
      ? null
      : this.step.fields[this.selection.field];
  }

  get record() {
    return this.selection.record === null ? null : this.definition.records[this.selection.record];
  }

  get typeOptions() {
    return TYPE_OPTIONS;
  }

  get isPicklist() {
    return Boolean(this.field && this.field.type === 'picklist');
  }

  get choicesText() {
    return optionsToText(this.field && this.field.options);
  }

  get targetRecordOptions() {
    return [
      { value: NONE, label: notWrittenLabel() },
      ...this.definition.records.map((record) => ({
        value: record.key,
        label: `${record.key} (${KIND_LABELS[record.kind] || record.kind})`
      }))
    ];
  }

  get targetRecord() {
    return (this.field && this.field.target && this.field.target.record) || NONE;
  }

  get targetField() {
    return (this.field && this.field.target && this.field.target.field) || NONE;
  }

  get hasTargetRecord() {
    return this.targetRecord !== NONE;
  }

  get targetFieldOptions() {
    const record = this.definition.records.find((each) => each.key === this.targetRecord);
    return this.writableFields(recordObject(record)).filter((field) => field.type !== 'reference');
  }

  writableFields(objectName) {
    return (this.fieldsByObject[objectName] || []).map((field) => ({
      value: field.value,
      label: `${field.label} (${field.value})`,
      type: field.type
    }));
  }

  // ---- conditions ----

  get conditionOwner() {
    if (this.editingField) {
      return this.field;
    }
    return this.editingStep ? this.step : null;
  }

  get condition() {
    return conditionParts(this.conditionOwner && this.conditionOwner.showWhen);
  }

  get modeOptions() {
    return MODE_OPTIONS;
  }

  get operatorOptions() {
    return OPERATOR_OPTIONS;
  }

  get conditionFieldOptions() {
    return earlierFields(
      this.definition,
      this.selection.step,
      this.editingField ? this.selection.field : null
    ).map((field) => ({ value: field.key, label: field.label || field.key }));
  }

  get canAddCondition() {
    return this.canEdit && this.conditionFieldOptions.length > 0;
  }

  get clauses() {
    return this.condition.clauses.map((clause, index) => ({
      id: `clause-${index}`,
      index,
      field: clause.field,
      op: clause.op,
      value: clause.value === undefined || clause.value === null ? '' : String(clause.value),
      needsValue: !NEEDS_NO_VALUE.has(clause.op)
    }));
  }

  get showClauses() {
    return this.condition.mode !== 'always';
  }

  get nestedNote() {
    return this.condition.nested.length ? nestedKept(this.condition.nested.length) : '';
  }

  setConditionParts(parts) {
    const fieldIndex = this.editingField ? this.selection.field : null;
    this.change(
      setCondition(this.definition, this.selection.step, fieldIndex, conditionFrom(parts))
    );
  }

  handleModeChange(event) {
    const parts = this.condition;
    const mode = event.detail.value;
    if (mode !== 'always' && parts.clauses.length === 0 && this.conditionFieldOptions.length) {
      parts.clauses = [{ field: this.conditionFieldOptions[0].value, op: 'isNotBlank' }];
    }
    this.setConditionParts({ ...parts, mode });
  }

  handleAddClause() {
    const parts = this.condition;
    const mode = parts.mode === 'always' ? 'all' : parts.mode;
    const clauses = [
      ...parts.clauses,
      { field: this.conditionFieldOptions[0].value, op: 'isNotBlank' }
    ];
    this.setConditionParts({ ...parts, mode, clauses });
  }

  handleClauseChange(event) {
    const index = Number(event.target.dataset.index);
    const name = event.target.dataset.name;
    const parts = this.condition;
    const clause = { ...parts.clauses[index], [name]: event.detail.value };
    if (NEEDS_NO_VALUE.has(clause.op)) {
      delete clause.value;
    }
    parts.clauses = parts.clauses.map((each, at) => (at === index ? clause : each));
    this.setConditionParts(parts);
  }

  handleRemoveClause(event) {
    const index = Number(event.target.dataset.index);
    const parts = this.condition;
    parts.clauses = parts.clauses.filter((each, at) => at !== index);
    this.setConditionParts(parts);
  }

  // ---- records ----

  get recordKindLabel() {
    return this.record ? KIND_LABELS[this.record.kind] || this.record.kind : '';
  }

  get recordIsRelated() {
    return Boolean(this.record && this.record.kind === 'related');
  }

  get recordIsMatched() {
    return Boolean(this.record && this.record.kind !== 'related');
  }

  get objectOptions() {
    return this.objects.map((object) => ({
      value: object.value,
      label: `${object.label} (${object.value})`
    }));
  }

  get ruleOptions() {
    return this.record ? ruleOptions(this.record.kind) : [];
  }

  get onMatchOptions() {
    return onMatchOptions();
  }

  get recordRule() {
    return this.record && this.record.matching ? this.record.matching.rule : NONE;
  }

  get recordOnMatch() {
    return this.record && this.record.matching ? this.record.matching.onMatch : NONE;
  }

  /** The lookup fields of a related record, each with the record it links to. */
  get links() {
    if (!this.recordIsRelated) {
      return [];
    }
    const links = this.record.links || {};
    const options = [
      { value: NONE, label: notWrittenLabel() },
      { value: CONTEXT_LINK, label: contextLinkLabel() },
      ...this.definition.records
        .filter((record) => record.key !== this.record.key)
        .map((record) => ({ value: record.key, label: record.key }))
    ];
    return this.writableFields(this.record.object)
      .filter((field) => field.type === 'reference')
      .map((field) => ({ ...field, to: links[field.value] || NONE, options }));
  }

  handleRecordChange(event) {
    const name = event.target.dataset.name;
    const value = event.detail.value;
    const index = this.selection.record;
    if (name === 'object') {
      this.change(updateRecord(this.definition, index, { object: value, links: {} }));
    } else if (name === 'rule' || name === 'onMatch') {
      const matching = { ...this.record.matching, [name]: value };
      this.change(updateRecord(this.definition, index, { matching }));
    }
  }

  handleLinkChange(event) {
    this.change(
      setLink(
        this.definition,
        this.selection.record,
        event.target.dataset.field,
        event.detail.value
      )
    );
  }

  handleAddRecord(event) {
    const next = addRecord(this.definition, event.detail.value);
    this.change(next);
    this.selection = { step: this.selection.step, field: null, record: next.records.length - 1 };
  }

  handleRemoveRecord() {
    this.change(removeRecord(this.definition, this.selection.record));
    this.selection = { step: 0, field: null, record: null };
  }

  // ---- steps and questions ----

  handleSelect(event) {
    const { step, field, record } = event.currentTarget.dataset;
    this.selection = {
      step: step === undefined ? this.selection.step : Number(step),
      field: field === undefined ? null : Number(field),
      record: record === undefined ? null : Number(record)
    };
  }

  handleAddStep() {
    const next = addStep(this.definition);
    this.change(next);
    this.selection = { step: next.steps.length - 1, field: null, record: null };
  }

  handleAddQuestion(event) {
    const stepIndex = Number(event.currentTarget.dataset.step);
    const next = addField(this.definition, stepIndex);
    this.change(next);
    this.selection = {
      step: stepIndex,
      field: next.steps[stepIndex].fields.length - 1,
      record: null
    };
  }

  handleStepChange(event) {
    this.change(updateStep(this.definition, this.selection.step, { title: event.detail.value }));
  }

  handleFieldChange(event) {
    const name = event.target.dataset.name;
    let value = name === 'required' ? event.detail.checked : event.detail.value;
    if (name === 'options') {
      value = optionsFromText(value);
    }
    this.change(
      updateField(this.definition, this.selection.step, this.selection.field, { [name]: value })
    );
  }

  handleTargetChange(event) {
    const name = event.target.dataset.name;
    const value = event.detail.value;
    let target = null;
    if (name === 'record' && value !== NONE) {
      target = { record: value, field: '' };
    } else if (name === 'field') {
      target = { record: this.targetRecord, field: value };
    }
    this.change(
      updateField(this.definition, this.selection.step, this.selection.field, { target })
    );
  }

  handleMove(event) {
    const delta = Number(event.currentTarget.dataset.delta);
    const { step, field } = this.selection;
    if (this.editingField) {
      this.change(moveField(this.definition, step, field, delta));
      this.selection = { ...this.selection, field: field + delta };
    } else {
      this.change(moveStep(this.definition, step, delta));
      this.selection = { ...this.selection, step: step + delta };
    }
    this.clampSelection();
  }

  handleRemove() {
    const { step, field } = this.selection;
    if (this.editingField) {
      this.change(removeField(this.definition, step, field));
    } else {
      this.change(removeStep(this.definition, step));
    }
    this.selection = {
      step: Math.max(0, this.editingField ? step : step - 1),
      field: null,
      record: null
    };
    this.clampSelection();
  }

  clampSelection() {
    const steps = this.definition.steps;
    const step = Math.min(Math.max(0, this.selection.step), Math.max(0, steps.length - 1));
    let field = this.selection.field;
    if (field !== null) {
      const count = steps[step] ? steps[step].fields.length : 0;
      field = count === 0 ? null : Math.min(Math.max(0, field), count - 1);
    }
    this.selection = { ...this.selection, step, field };
  }

  // ---- saving ----

  async handleSave() {
    await this.send(saveDraft, LABELS.saved);
  }

  async handlePublish() {
    await this.send(publish, null);
  }

  async send(action, doneMessage) {
    this.busy = true;
    this.errorMessage = '';
    try {
      const form = await action({
        formId: this.recordId,
        definitionJson: serializeDefinition(this.definition)
      });
      this.show(form);
      this.resultMessage = doneMessage || publishedVersion(form.publishedVersion);
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
    this.busy = false;
  }
}
