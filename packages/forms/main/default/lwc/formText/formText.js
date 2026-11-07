/**
 * The Forms pages' words in one place (C-42a): short UI strings from custom labels, Forms' own
 * or Core's shared ones, and every message and problem from the Forms help catalog
 * (BarnHelp_Forms.json, ADR-0164 help-text-json). The framework-free modules return problems as
 * `{ code, args }`; this module words them.
 */
import TITLE from '@salesforce/label/c.Forms_Builder_Title';
import SAVE_DRAFT from '@salesforce/label/c.Forms_Builder_SaveDraft';
import PUBLISH from '@salesforce/label/c.Forms_Builder_Publish';
import ADD_QUESTION from '@salesforce/label/c.Forms_Builder_AddQuestion';
import STEP_TITLE from '@salesforce/label/c.Forms_Builder_StepTitle';
import QUESTION from '@salesforce/label/c.Forms_Builder_Question';
import KEY from '@salesforce/label/c.Forms_Builder_Key';
import LONG_TEXT from '@salesforce/label/c.Forms_Builder_LongText';
import CHOICES from '@salesforce/label/c.Forms_Builder_Choices';
import WRITE_TO from '@salesforce/label/c.Forms_Builder_WriteTo';
import SHOW_WHEN from '@salesforce/label/c.Forms_Builder_ShowWhen';
import ALWAYS from '@salesforce/label/c.Forms_Builder_Always';
import ALL_TRUE from '@salesforce/label/c.Forms_Builder_AllTrue';
import ANY_TRUE from '@salesforce/label/c.Forms_Builder_AnyTrue';
import ADD_CONDITION from '@salesforce/label/c.Core_Filter_AddCondition';
import OPERATOR from '@salesforce/label/c.Core_Filter_Operator';
import GREATER_THAN from '@salesforce/label/c.Forms_Builder_GreaterThan';
import LESS_THAN from '@salesforce/label/c.Forms_Builder_LessThan';
import RECORDS from '@salesforce/label/c.Forms_Builder_Records';
import ADD_RECORD from '@salesforce/label/c.Forms_Builder_AddRecord';
import RELATED from '@salesforce/label/c.Forms_Builder_Related';
import MATCH_BY from '@salesforce/label/c.Forms_Builder_MatchBy';
import WHEN_FOUND from '@salesforce/label/c.Forms_Builder_WhenFound';
import LINK_TO from '@salesforce/label/c.Forms_Builder_LinkTo';
import PROBLEMS from '@salesforce/label/c.Forms_Builder_Problems';
import ADD_STEP from '@salesforce/label/c.Core_Shared_AddStep';
import MOVE_UP from '@salesforce/label/c.Core_Shared_MoveUp';
import MOVE_DOWN from '@salesforce/label/c.Core_Shared_MoveDown';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import TYPE from '@salesforce/label/c.Core_DataDictionary_ColType';
import REQUIRED from '@salesforce/label/c.Core_DataDictionary_ColRequired';
import HELP_TEXT from '@salesforce/label/c.Core_DataDictionary_ColHelpText';
import FIELD from '@salesforce/label/c.Core_AccessExplorer_Field';
import OBJECT from '@salesforce/label/c.Core_MatchLogic_Object';
import VALUE from '@salesforce/label/c.Core_Filter_Value';
import EQUALS from '@salesforce/label/c.Core_Filter_OpEquals';
import NOT_EQUALS from '@salesforce/label/c.Core_Filter_OpNotEquals';
import CONTAINS from '@salesforce/label/c.Core_Filter_OpContains';
import IS_BLANK from '@salesforce/label/c.Core_Filter_OpIsNull';
import IS_NOT_BLANK from '@salesforce/label/c.Core_Filter_OpIsNotNull';
import TYPE_TEXT from '@salesforce/label/c.Core_ImportNewField_TypeText';
import TYPE_NUMBER from '@salesforce/label/c.Core_ImportNewField_TypeNumber';
import TYPE_DATE from '@salesforce/label/c.Core_ImportNewField_TypeDate';
import TYPE_CHECKBOX from '@salesforce/label/c.Core_ImportNewField_TypeCheckbox';
import TYPE_EMAIL from '@salesforce/label/c.Core_ImportNewField_TypeEmail';
import TYPE_PHONE from '@salesforce/label/c.Core_ImportNewField_TypePhone';
import TYPE_PICKLIST from '@salesforce/label/c.Core_ImportNewField_TypePicklist';
import PERSON from '@salesforce/label/c.Core_Section_Person';
import ORGANIZATION from '@salesforce/label/c.Core_Settings_NavGroup_Organization';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import STATUS from '@salesforce/label/c.Core_ImportRow_StatusLabel';
import { helpText } from 'c/barnHelpText';

export const HELP = ['Forms', 'Core'];

export const LABELS = Object.freeze({
  title: TITLE,
  saveDraft: SAVE_DRAFT,
  publish: PUBLISH,
  addStep: ADD_STEP,
  addQuestion: ADD_QUESTION,
  stepTitle: STEP_TITLE,
  question: QUESTION,
  key: KEY,
  type: TYPE,
  required: REQUIRED,
  helpText: HELP_TEXT,
  choices: CHOICES,
  writeTo: WRITE_TO,
  field: FIELD,
  object: OBJECT,
  value: VALUE,
  showWhen: SHOW_WHEN,
  addCondition: ADD_CONDITION,
  operator: OPERATOR,
  records: RECORDS,
  addRecord: ADD_RECORD,
  matchBy: MATCH_BY,
  whenFound: WHEN_FOUND,
  linkTo: LINK_TO,
  problems: PROBLEMS,
  moveUp: MOVE_UP,
  moveDown: MOVE_DOWN,
  remove: REMOVE,
  loading: LOADING,
  status: STATUS,
  get intro() {
    return helpText('Forms', 'Forms_Builder_Intro');
  },
  get recordsIntro() {
    return helpText('Forms', 'Forms_Builder_RecordsIntro');
  },
  get emptyStep() {
    return helpText('Forms', 'Forms_Builder_EmptyStep');
  },
  get choicesHint() {
    return helpText('Forms', 'Forms_Builder_ChoicesHint');
  },
  get readOnly() {
    return helpText('Forms', 'Forms_Builder_ReadOnly');
  },
  get saved() {
    return helpText('Forms', 'Forms_Builder_Saved');
  },
  get actionFailed() {
    return helpText('Forms', 'Forms_Builder_ActionFailed');
  }
});

export const TYPE_OPTIONS = Object.freeze([
  { value: 'text', label: TYPE_TEXT },
  { value: 'textarea', label: LONG_TEXT },
  { value: 'email', label: TYPE_EMAIL },
  { value: 'phone', label: TYPE_PHONE },
  { value: 'number', label: TYPE_NUMBER },
  { value: 'date', label: TYPE_DATE },
  { value: 'checkbox', label: TYPE_CHECKBOX },
  { value: 'picklist', label: TYPE_PICKLIST }
]);

export const OPERATOR_OPTIONS = Object.freeze([
  { value: 'equals', label: EQUALS },
  { value: 'notEquals', label: NOT_EQUALS },
  { value: 'contains', label: CONTAINS },
  { value: 'greaterThan', label: GREATER_THAN },
  { value: 'lessThan', label: LESS_THAN },
  { value: 'isBlank', label: IS_BLANK },
  { value: 'isNotBlank', label: IS_NOT_BLANK }
]);

export const MODE_OPTIONS = Object.freeze([
  { value: 'always', label: ALWAYS },
  { value: 'all', label: ALL_TRUE },
  { value: 'any', label: ANY_TRUE }
]);

export const KIND_LABELS = Object.freeze({
  person: PERSON,
  organization: ORGANIZATION,
  related: RELATED
});

/** The ways a person or organization is matched, worded from the help catalog. */
export function ruleOptions(kind) {
  return kind === 'person'
    ? [
        {
          value: 'emailThenNamePostal',
          label: helpText('Forms', 'Forms_Builder_RuleEmailThenNamePostal')
        },
        { value: 'email', label: helpText('Forms', 'Forms_Builder_RuleEmail') }
      ]
    : [{ value: 'name', label: helpText('Forms', 'Forms_Builder_RuleName') }];
}

export function onMatchOptions() {
  return [
    { value: 'fillBlanks', label: helpText('Forms', 'Forms_Builder_FillBlanks') },
    { value: 'overwrite', label: helpText('Forms', 'Forms_Builder_Overwrite') }
  ];
}

/** The choice for an answer written nowhere, and a link to the record filled from. */
export function notWrittenLabel() {
  return helpText('Forms', 'Forms_Builder_NotWritten');
}

export function contextLinkLabel() {
  return helpText('Forms', 'Forms_Builder_ContextLink');
}

export function nestedKept(count) {
  return helpText('Forms', 'Forms_Builder_NestedKept', count);
}

export function publishedVersion(version) {
  return helpText('Forms', 'Forms_Builder_PublishedVersion', version);
}

const DEFINITION_PROBLEMS = {
  notJson: (a) => helpText('Forms', 'Forms_Problem_notJson', ...a),
  schemaVersion: (a) => helpText('Forms', 'Forms_Problem_schemaVersion', ...a),
  noSteps: (a) => helpText('Forms', 'Forms_Problem_noSteps', ...a),
  tooManySteps: (a) => helpText('Forms', 'Forms_Problem_tooManySteps', ...a),
  tooManyRecords: (a) => helpText('Forms', 'Forms_Problem_tooManyRecords', ...a),
  tooManyFields: (a) => helpText('Forms', 'Forms_Problem_tooManyFields', ...a),
  badStepKey: (a) => helpText('Forms', 'Forms_Problem_badStepKey', ...a),
  emptyStep: (a) => helpText('Forms', 'Forms_Problem_emptyStep', ...a),
  badKey: (a) => helpText('Forms', 'Forms_Problem_badKey', ...a),
  duplicateKey: (a) => helpText('Forms', 'Forms_Problem_duplicateKey', ...a),
  noLabel: (a) => helpText('Forms', 'Forms_Problem_noLabel', ...a),
  badType: (a) => helpText('Forms', 'Forms_Problem_badType', ...a),
  noOptions: (a) => helpText('Forms', 'Forms_Problem_noOptions', ...a),
  tooManyOptions: (a) => helpText('Forms', 'Forms_Problem_tooManyOptions', ...a),
  badCondition: (a) => helpText('Forms', 'Forms_Problem_badCondition', ...a),
  conditionTooDeep: (a) => helpText('Forms', 'Forms_Problem_conditionTooDeep', ...a),
  conditionNotEarlier: (a) => helpText('Forms', 'Forms_Problem_conditionNotEarlier', ...a),
  conditionNeedsValue: (a) => helpText('Forms', 'Forms_Problem_conditionNeedsValue', ...a),
  unknownRecord: (a) => helpText('Forms', 'Forms_Problem_unknownRecord', ...a),
  noTargetField: (a) => helpText('Forms', 'Forms_Problem_noTargetField', ...a),
  badRecord: (a) => helpText('Forms', 'Forms_Problem_badRecord', ...a),
  duplicateRecord: (a) => helpText('Forms', 'Forms_Problem_duplicateRecord', ...a),
  twoPeople: (a) => helpText('Forms', 'Forms_Problem_twoPeople', ...a),
  twoOrganizations: (a) => helpText('Forms', 'Forms_Problem_twoOrganizations', ...a),
  relatedNeedsObject: (a) => helpText('Forms', 'Forms_Problem_relatedNeedsObject', ...a),
  badMatching: (a) => helpText('Forms', 'Forms_Problem_badMatching', ...a),
  badLink: (a) => helpText('Forms', 'Forms_Problem_badLink', ...a),
  badValue: (a) => helpText('Forms', 'Forms_Problem_badValue', ...a),
  personNeedsLastName: (a) => helpText('Forms', 'Forms_Problem_personNeedsLastName', ...a),
  personNeedsEmail: (a) => helpText('Forms', 'Forms_Problem_personNeedsEmail', ...a),
  organizationNeedsName: (a) => helpText('Forms', 'Forms_Problem_organizationNeedsName', ...a)
};

const ANSWER_PROBLEMS = {
  required: (a) => helpText('Forms', 'Forms_Answer_required', ...a),
  mustTick: (a) => helpText('Forms', 'Forms_Answer_mustTick', ...a),
  badEmail: (a) => helpText('Forms', 'Forms_Answer_badEmail', ...a),
  badPhone: (a) => helpText('Forms', 'Forms_Answer_badPhone', ...a),
  badNumber: (a) => helpText('Forms', 'Forms_Answer_badNumber', ...a),
  belowMin: (a) => helpText('Forms', 'Forms_Answer_belowMin', ...a),
  aboveMax: (a) => helpText('Forms', 'Forms_Answer_aboveMax', ...a),
  badDate: (a) => helpText('Forms', 'Forms_Answer_badDate', ...a),
  notAnOption: (a) => helpText('Forms', 'Forms_Answer_notAnOption', ...a),
  tooLong: (a) => helpText('Forms', 'Forms_Answer_tooLong', ...a)
};

function worded(table, problem) {
  const word = problem && table[problem.code];
  return word ? word(problem.args || []) : LABELS.actionFailed;
}

/** A problem with the definition (c/formDefinition checkDefinition), in words. */
export function problemText(problem) {
  return worded(DEFINITION_PROBLEMS, problem);
}

/** A problem with an answer (c/formRules checkAnswer), in words. */
export function answerText(problem) {
  return worded(ANSWER_PROBLEMS, problem);
}

/** The message of a failed server call, or the general one. */
export function messageFrom(error) {
  return error && error.body && error.body.message ? error.body.message : LABELS.actionFailed;
}
