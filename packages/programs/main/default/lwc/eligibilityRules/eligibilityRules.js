import { LightningElement, api } from 'lwc';
import getState from '@salesforce/apex/EligibilityController.getState';
import saveRules from '@salesforce/apex/EligibilityController.saveRules';
import screen from '@salesforce/apex/EligibilityController.screen';

import TITLE from '@salesforce/label/c.Programs_Elig_Title';
import NO_RULES from '@salesforce/label/c.Programs_Elig_NoRules';
import RULE from '@salesforce/label/c.Programs_Elig_Rule';
import FIELD from '@salesforce/label/c.Programs_Elig_Field';
import OPERATOR from '@salesforce/label/c.Programs_Elig_Operator';
import VALUE from '@salesforce/label/c.Core_Filter_Value';
import VALUE_LIST from '@salesforce/label/c.Programs_Elig_ValueList';
import ADD_CONDITION from '@salesforce/label/c.Programs_Elig_AddCondition';
import REMOVE_CONDITION from '@salesforce/label/c.Programs_Elig_RemoveCondition';
import RESULT from '@salesforce/label/c.Core_Find_Result';
import REASON from '@salesforce/label/c.Core_Import_ResultsReason';
import BASIS from '@salesforce/label/c.Programs_Elig_Basis';
import NO_BASIS from '@salesforce/label/c.Programs_Elig_NoBasis';
import ADD_RULE from '@salesforce/label/c.Core_Import_RowRulesAddRule';
import REMOVE_RULE from '@salesforce/label/c.Core_Import_RowRulesRemoveRule';
import MOVE_UP from '@salesforce/label/c.Core_Shared_MoveUp';
import MOVE_DOWN from '@salesforce/label/c.Core_Shared_MoveDown';
import WHEN_ALL from '@salesforce/label/c.Programs_Elig_WhenAll';
import DEFAULT_TITLE from '@salesforce/label/c.Programs_Elig_DefaultTitle';
import DEFAULT_RESULT from '@salesforce/label/c.Programs_Elig_DefaultResult';
import DEFAULT_REASON from '@salesforce/label/c.Programs_Elig_DefaultReason';
import SAVE from '@salesforce/label/c.Programs_Elig_Save';
import SAVED from '@salesforce/label/c.Programs_Elig_Saved';
import UNSAVED from '@salesforce/label/c.Core_Shared_UnsavedChanges';
import PREVIEW_TITLE from '@salesforce/label/c.Programs_Elig_PreviewTitle';
import PREVIEW_PERSON from '@salesforce/label/c.Programs_Elig_PreviewPerson';
import NO_PEOPLE from '@salesforce/label/c.Programs_Elig_NoPeople';
import PREVIEW_RESULT from '@salesforce/label/c.Programs_Elig_PreviewResult';
import APPLY_ONE from '@salesforce/label/c.Programs_Elig_ApplyOne';
import SCREEN_ALL from '@salesforce/label/c.Programs_Elig_ScreenAll';
import INCLUDE_DECIDED from '@salesforce/label/c.Programs_Elig_IncludeDecided';
import SCREENED from '@salesforce/label/c.Programs_Elig_Screened';
import SAVE_FIRST from '@salesforce/label/c.Programs_Elig_SaveFirst';
import NO_RULE_MATCHED from '@salesforce/label/c.Programs_Elig_NoRuleMatched';
import MORE_THAN_SHOWN from '@salesforce/label/c.Programs_Elig_MoreThanShown';
import READ_ONLY from '@salesforce/label/c.Programs_Elig_ReadOnly';
import OP_EQUALS from '@salesforce/label/c.Programs_Elig_OpEquals';
import OP_NOT_EQUALS from '@salesforce/label/c.Programs_Elig_OpNotEquals';
import OP_IN from '@salesforce/label/c.Programs_Elig_OpIn';
import OP_NOT_IN from '@salesforce/label/c.Programs_Elig_OpNotIn';
import OP_GREATER from '@salesforce/label/c.Programs_Elig_OpGreater';
import OP_GREATER_OR_EQUAL from '@salesforce/label/c.Programs_Elig_OpGreaterOrEqual';
import OP_LESS from '@salesforce/label/c.Programs_Elig_OpLess';
import OP_LESS_OR_EQUAL from '@salesforce/label/c.Programs_Elig_OpLessOrEqual';
import OP_BLANK from '@salesforce/label/c.Programs_Elig_OpBlank';
import OP_NOT_BLANK from '@salesforce/label/c.Programs_Elig_OpNotBlank';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import AVAILABLE_VALUES from '@salesforce/label/c.Core_Filter_AvailableValues';
import CHOSEN_VALUES from '@salesforce/label/c.Core_Filter_ChosenValues';

import {
  RESULTS,
  evaluateRules,
  format,
  isListOperator,
  moveRule,
  needsValue,
  newCondition,
  newRule,
  parseRules,
  serializeRules
} from './eligibilityEngine';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { createDragController, moveItem } from 'c/barnDrag';
import { dragInstructions, dragMessages } from 'c/barnDragText';

const HELP = ['Programs', 'Core'];

/** Comma text (how the panel holds a list value) as the list a dual listbox shows. */
function listOf(text) {
  return String(text || '')
    .split(',')
    .map((part) => part.trim())
    .filter((part) => part !== '');
}

const OPERATOR_LABELS = {
  equals: OP_EQUALS,
  notEquals: OP_NOT_EQUALS,
  in: OP_IN,
  notIn: OP_NOT_IN,
  greaterThan: OP_GREATER,
  greaterOrEqual: OP_GREATER_OR_EQUAL,
  lessThan: OP_LESS,
  lessOrEqual: OP_LESS_OR_EQUAL,
  isBlank: OP_BLANK,
  isNotBlank: OP_NOT_BLANK
};

/**
 * The Eligibility Rules panel on a program (P-14): an admin builds the screening rules, previews
 * what they would decide for an open enrollment (worked out in `eligibilityEngine`, the same rules
 * Apex applies on saving), and screens enrollments, which sets their Eligibility Status, Basis
 * and Reason.
 */
export default class EligibilityRules extends LightningElement {
  helpReady = isHelpLoaded(HELP);

  @api recordId;

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Programs', 'Programs_Elig_Intro');
    },
    noRules: NO_RULES,
    field: FIELD,
    operator: OPERATOR,
    addCondition: ADD_CONDITION,
    removeCondition: REMOVE_CONDITION,
    result: RESULT,
    reason: REASON,
    basis: BASIS,
    addRule: ADD_RULE,
    removeRule: REMOVE_RULE,
    moveUp: MOVE_UP,
    moveDown: MOVE_DOWN,
    whenAll: WHEN_ALL,
    defaultTitle: DEFAULT_TITLE,
    defaultResult: DEFAULT_RESULT,
    defaultReason: DEFAULT_REASON,
    save: SAVE,
    unsaved: UNSAVED,
    previewTitle: PREVIEW_TITLE,
    previewPerson: PREVIEW_PERSON,
    noPeople: NO_PEOPLE,
    applyOne: APPLY_ONE,
    screenAll: SCREEN_ALL,
    includeDecided: INCLUDE_DECIDED,
    moreThanShown: MORE_THAN_SHOWN,
    readOnly: READ_ONLY,
    loading: LOADING,
    value: VALUE,
    availableValues: AVAILABLE_VALUES,
    chosenValues: CHOSEN_VALUES
  };

  /** The last drag step, read out by the aria-live region. */
  announcement = '';
  /** c/barnDrag's state while a rule is dragged: which one, and where it would land. */
  dragState;
  drag;

  state;
  config = parseRules('');
  savedJson = '';
  problems = [];
  personId;
  includeDecided = false;
  loading = true;
  busy = false;
  errorMessage;
  resultMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP).then(() => {
        this.helpReady = true;
      });
    }
    // DnD-5: a rule is dragged by its handle (mouse, pen, or touch after a press and hold) or by
    // keyboard (Space, the arrow keys, Space again); Move Up and Move Down stay as the plain path.
    this.drag = createDragController({
      root: this.template,
      layout: 'list',
      messages: dragMessages(),
      announce: (text) => {
        this.announcement = text;
      },
      onChange: (state) => {
        this.dragState = state;
      },
      onDrop: ({ itemId, toIndex }) => {
        const from = this.config.rules.findIndex((rule) => rule.id === itemId);
        if (from < 0 || from === toIndex) {
          return false;
        }
        this.touch({ ...this.config, rules: moveItem(this.config.rules, from, toIndex) });
        return true;
      }
    });
    this.load();
  }

  disconnectedCallback() {
    if (this.drag) {
      this.drag.destroy();
    }
  }

  get dragHelp() {
    return dragInstructions();
  }

  /** Two or more rules can be put in order by dragging; a reader cannot. */
  get canDrag() {
    return this.canEdit && this.config.rules.length > 1;
  }

  handlePointerDown(event) {
    this.drag.pointerDown(event);
  }

  handleDragKey(event) {
    this.drag.keyDown(event);
  }

  load() {
    this.loading = true;
    return getState({ programId: this.recordId })
      .then((state) => {
        this.state = state;
        this.config = parseRules(state.rules);
        this.savedJson = serializeRules(this.config);
        if (!this.personId && state.people.length > 0) {
          this.personId = state.people[0].enrollmentId;
        }
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Elig'));
      })
      .finally(() => {
        this.loading = false;
      });
  }

  // ------------------------------------------------------------------------- what is shown

  get showSpinner() {
    return this.loading || this.busy;
  }

  get loaded() {
    return !!this.state;
  }

  get canEdit() {
    return !!(this.state && this.state.canEdit);
  }

  get readOnly() {
    return this.loaded && !this.canEdit;
  }

  get canScreen() {
    return !!(this.state && this.state.canScreen);
  }

  get dirty() {
    return serializeRules(this.config) !== this.savedJson;
  }

  get hasRules() {
    return this.config.rules.length > 0;
  }

  get noRules() {
    return this.loaded && !this.hasRules;
  }

  get hasProblems() {
    return this.problems.length > 0;
  }

  get problemItems() {
    return this.problems.map((text, index) => ({ key: String(index), text }));
  }

  get fieldOptions() {
    return ((this.state && this.state.fields) || []).map(({ label, apiName }) => ({
      label,
      value: apiName
    }));
  }

  get operatorOptions() {
    return Object.keys(OPERATOR_LABELS).map((value) => ({ label: OPERATOR_LABELS[value], value }));
  }

  get resultOptions() {
    return RESULTS.map((value) => ({ label: value, value }));
  }

  get basisOptions() {
    return [
      { label: NO_BASIS, value: '' },
      ...((this.state && this.state.bases) || []).map((value) => ({ label: value, value }))
    ];
  }

  /** A picklist field's choices by API name (modules-9: picked from a list, not typed). */
  get choicesByField() {
    const map = {};
    ((this.state && this.state.fields) || []).forEach((field) => {
      if (field.choices && field.choices.length) {
        map[field.apiName] = field.choices.map((value) => ({ label: value, value }));
      }
    });
    return map;
  }

  get ruleViews() {
    const rules = this.config.rules;
    const last = rules.length - 1;
    const choices = this.choicesByField;
    const drag = this.dragState && this.dragState.active ? this.dragState : null;
    // While dragging, the rule the dragged one would land before (or after, at the end).
    const others = drag ? rules.filter((rule) => rule.id !== drag.itemId) : [];
    const before = drag && drag.overIndex >= 0 ? others[drag.overIndex] : null;
    const after =
      drag && drag.overIndex === others.length && others.length ? others[others.length - 1] : null;
    return rules.map((rule, index) => ({
      key: rule.id,
      index,
      title: format(RULE, index + 1),
      boxClass: [
        'slds-box slds-var-m-bottom_small',
        drag && drag.itemId === rule.id ? 'rule-dragging' : '',
        before && before.id === rule.id ? 'rule-over-before' : '',
        after && after.id === rule.id ? 'rule-over-after' : ''
      ]
        .filter(Boolean)
        .join(' '),
      result: rule.result,
      reason: rule.reason,
      basis: rule.basis,
      moveUpDisabled: index === 0,
      moveDownDisabled: index === last,
      conditions: rule.all.map((condition, position) => {
        const options = choices[condition.field];
        const showChoices = !!options && isListOperator(condition.operator);
        return {
          key: `${rule.id}-${position}`,
          index: position,
          field: condition.field,
          operator: condition.operator,
          value: condition.value,
          showChoices,
          choiceOptions: options || [],
          chosen: showChoices ? listOf(condition.value) : [],
          showValue: needsValue(condition.operator) && !showChoices,
          valueLabel: isListOperator(condition.operator) ? `${VALUE} (${VALUE_LIST})` : VALUE,
          canRemove: rule.all.length > 1
        };
      })
    }));
  }

  get defaultResult() {
    return this.config.defaultResult;
  }

  get defaultReason() {
    return this.config.defaultReason;
  }

  get peopleOptions() {
    return ((this.state && this.state.people) || []).map((person) => ({
      label: `${person.name || ''}${person.status ? ` (${person.status})` : ''}`,
      value: person.enrollmentId
    }));
  }

  get hasPeople() {
    return this.peopleOptions.length > 0;
  }

  get noPeople() {
    return this.loaded && !this.hasPeople;
  }

  get moreThanShown() {
    return !!(this.state && this.state.moreThanShown);
  }

  get previewText() {
    const person = ((this.state && this.state.people) || []).find(
      (item) => item.enrollmentId === this.personId
    );
    if (!person) {
      return '';
    }
    const decision = evaluateRules(this.config, person.values, NO_RULE_MATCHED);
    return decision ? format(PREVIEW_RESULT, decision.status, decision.reason) : '';
  }

  get controlsDisabled() {
    return this.busy || this.loading;
  }

  get screenDisabled() {
    return this.controlsDisabled || !this.canScreen || !this.hasRules;
  }

  get applyOneDisabled() {
    return this.screenDisabled || !this.personId;
  }

  get saveDisabled() {
    return this.controlsDisabled || !this.dirty;
  }

  // ------------------------------------------------------------------------- editing

  touch(config) {
    this.config = config;
    this.problems = [];
    this.resultMessage = undefined;
  }

  ruleOf(event) {
    return Number(event.target.dataset.rule);
  }

  changeRule(index, change) {
    this.touch({
      ...this.config,
      rules: this.config.rules.map((rule, i) => (i === index ? { ...rule, ...change } : rule))
    });
  }

  changeCondition(event, change) {
    const ruleIndex = this.ruleOf(event);
    const conditionIndex = Number(event.target.dataset.condition);
    const rule = this.config.rules[ruleIndex];
    this.changeRule(ruleIndex, {
      all: rule.all.map((condition, i) => {
        return i === conditionIndex ? { ...condition, ...change } : condition;
      })
    });
  }

  handleAddRule() {
    const firstField = this.fieldOptions.length > 0 ? this.fieldOptions[0].value : '';
    this.touch({
      ...this.config,
      rules: [...this.config.rules, newRule(this.config, firstField)]
    });
  }

  handleRemoveRule(event) {
    const index = this.ruleOf(event);
    this.touch({ ...this.config, rules: this.config.rules.filter((rule, i) => i !== index) });
  }

  handleMove(event) {
    this.touch({
      ...this.config,
      rules: moveRule(this.config.rules, this.ruleOf(event), Number(event.target.dataset.step))
    });
  }

  handleAddCondition(event) {
    const index = this.ruleOf(event);
    const firstField = this.fieldOptions.length > 0 ? this.fieldOptions[0].value : '';
    this.changeRule(index, { all: [...this.config.rules[index].all, newCondition(firstField)] });
  }

  handleRemoveCondition(event) {
    const index = this.ruleOf(event);
    const position = Number(event.target.dataset.condition);
    this.changeRule(index, { all: this.config.rules[index].all.filter((c, i) => i !== position) });
  }

  handleFieldChange(event) {
    this.changeCondition(event, { field: event.detail.value });
  }

  handleOperatorChange(event) {
    this.changeCondition(event, { operator: event.detail.value });
  }

  handleValueChange(event) {
    this.changeCondition(event, { value: event.target.value });
  }

  handleChoicesChange(event) {
    this.changeCondition(event, { value: (event.detail.value || []).join(', ') });
  }

  handleResultChange(event) {
    this.changeRule(this.ruleOf(event), { result: event.detail.value });
  }

  handleReasonChange(event) {
    this.changeRule(this.ruleOf(event), { reason: event.target.value });
  }

  handleBasisChange(event) {
    this.changeRule(this.ruleOf(event), { basis: event.detail.value });
  }

  handleDefaultResultChange(event) {
    this.touch({ ...this.config, defaultResult: event.detail.value });
  }

  handleDefaultReasonChange(event) {
    this.touch({ ...this.config, defaultReason: event.target.value });
  }

  handlePersonChange(event) {
    this.personId = event.detail.value;
  }

  handleIncludeDecided(event) {
    this.includeDecided = event.target.checked;
  }

  // ------------------------------------------------------------------------- saving and screening

  handleSave() {
    this.busy = true;
    this.errorMessage = undefined;
    this.resultMessage = undefined;
    return saveRules({ programId: this.recordId, rules: serializeRules(this.config) })
      .then((problems) => {
        this.problems = problems || [];
        if (this.problems.length === 0) {
          this.savedJson = serializeRules(this.config);
          this.resultMessage = SAVED;
        }
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Elig'));
      })
      .finally(() => {
        this.busy = false;
      });
  }

  run(enrollmentId) {
    if (this.dirty) {
      this.errorMessage = SAVE_FIRST;
      return Promise.resolve();
    }
    this.busy = true;
    this.errorMessage = undefined;
    this.resultMessage = undefined;
    return screen({
      programId: this.recordId,
      enrollmentId,
      includeDecided: this.includeDecided
    })
      .then((summary) => {
        this.resultMessage = summary.noRules
          ? NO_RULES
          : format(
              SCREENED,
              summary.eligible,
              summary.notEligible,
              summary.review,
              summary.skipped
            );
        return this.load();
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Elig'));
      })
      .finally(() => {
        this.busy = false;
      });
  }

  handleApplyOne() {
    return this.run(this.personId);
  }

  handleScreenAll() {
    return this.run(null);
  }
}
