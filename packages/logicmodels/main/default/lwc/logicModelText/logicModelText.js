/**
 * The Logic Model Builder's words, in one place for its three panels: every label comes from
 * the LogicModels custom labels, so the text exports as translatable strings (plan 9.9).
 */
import TITLE from '@salesforce/label/c.LogicModels_Builder_Title';
import FOR_LABEL from '@salesforce/label/c.LogicModels_Builder_For';
import WHOLE_ORGANIZATION from '@salesforce/label/c.LogicModels_Builder_WholeOrganization';
import PROGRAM_MISSING from '@salesforce/label/c.LogicModels_Builder_ProgramMissing';
import CHANGE from '@salesforce/label/c.LogicModels_Builder_Change';
import SAVE from '@salesforce/label/c.LogicModels_Builder_Save';
import CANCEL from '@salesforce/label/c.LogicModels_Builder_Cancel';
import ADD_TO from '@salesforce/label/c.LogicModels_Builder_AddTo';
import ADD from '@salesforce/label/c.LogicModels_Builder_Add';
import EDIT from '@salesforce/label/c.LogicModels_Builder_Edit';
import DELETE from '@salesforce/label/c.LogicModels_Builder_Delete';
import REMOVE from '@salesforce/label/c.LogicModels_Builder_Remove';
import NAME from '@salesforce/label/c.LogicModels_Builder_Name';
import DESCRIPTION from '@salesforce/label/c.LogicModels_Builder_Description';
import COLUMN from '@salesforce/label/c.LogicModels_Builder_Column';
import EMPTY_COLUMN from '@salesforce/label/c.LogicModels_Builder_EmptyColumn';
import SELECT_HINT from '@salesforce/label/c.LogicModels_Builder_SelectHint';
import LOOK_AT from '@salesforce/label/c.LogicModels_Builder_LookAt';
import LOOK_AT_NONE from '@salesforce/label/c.LogicModels_Builder_LookAtNone';
import FINDING_EMPTY from '@salesforce/label/c.LogicModels_Builder_FindingEmptyStage';
import FINDING_NO_IN from '@salesforce/label/c.LogicModels_Builder_FindingNoArrowIn';
import FINDING_NO_OUT from '@salesforce/label/c.LogicModels_Builder_FindingNoArrowOut';
import FINDING_NO_INDICATOR from '@salesforce/label/c.LogicModels_Builder_FindingNoIndicator';
import OUTCOMES from '@salesforce/label/c.LogicModels_Builder_Outcomes';
import SAVED from '@salesforce/label/c.LogicModels_Builder_Saved';
import DELETED from '@salesforce/label/c.LogicModels_Builder_Deleted';
import ACTION_FAILED from '@salesforce/label/c.LogicModels_Builder_ActionFailed';
import LOADING from '@salesforce/label/c.LogicModels_Builder_Loading';
import STAGE_INPUT from '@salesforce/label/c.LogicModels_Stage_Input';
import STAGE_ACTIVITY from '@salesforce/label/c.LogicModels_Stage_Activity';
import STAGE_OUTPUT from '@salesforce/label/c.LogicModels_Stage_Output';
import STAGE_SHORT from '@salesforce/label/c.LogicModels_Stage_OutcomeShort';
import STAGE_INTERMEDIATE from '@salesforce/label/c.LogicModels_Stage_OutcomeIntermediate';
import STAGE_LONG from '@salesforce/label/c.LogicModels_Stage_OutcomeLong';
import STAGE_IMPACT from '@salesforce/label/c.LogicModels_Stage_Impact';
import SELECTED_PART from '@salesforce/label/c.LogicModels_Part_Title';
import MOVE_UP from '@salesforce/label/c.LogicModels_Part_MoveUp';
import MOVE_DOWN from '@salesforce/label/c.LogicModels_Part_MoveDown';
import DELETE_PART_CONFIRM from '@salesforce/label/c.LogicModels_Part_DeleteConfirm';
import LEADS_TO from '@salesforce/label/c.LogicModels_Part_LeadsTo';
import COMES_FROM from '@salesforce/label/c.LogicModels_Part_ComesFrom';
import ADD_ARROW from '@salesforce/label/c.LogicModels_Part_AddArrow';
import ARROW_TARGET from '@salesforce/label/c.LogicModels_Part_ArrowTarget';
import ASSUMPTION from '@salesforce/label/c.LogicModels_Part_Assumption';
import NO_ARROWS from '@salesforce/label/c.LogicModels_Part_NoArrows';
import NO_TARGETS from '@salesforce/label/c.LogicModels_Part_NoTargets';
import NO_ASSUMPTION from '@salesforce/label/c.LogicModels_Part_NoAssumption';
import INDICATORS from '@salesforce/label/c.LogicModels_Indicator_Title';
import ADD_INDICATOR from '@salesforce/label/c.LogicModels_Indicator_Add';
import INDICATOR_NAME from '@salesforce/label/c.LogicModels_Indicator_Name';
import UNIT from '@salesforce/label/c.LogicModels_Indicator_Unit';
import BETTER_WHEN from '@salesforce/label/c.LogicModels_Indicator_BetterWhen';
import HIGHER from '@salesforce/label/c.LogicModels_Indicator_Higher';
import LOWER from '@salesforce/label/c.LogicModels_Indicator_Lower';
import BASELINE from '@salesforce/label/c.LogicModels_Indicator_Baseline';
import BASELINE_DATE from '@salesforce/label/c.LogicModels_Indicator_BaselineDate';
import NO_INDICATORS from '@salesforce/label/c.LogicModels_Indicator_None';
import DELETE_INDICATOR_CONFIRM from '@salesforce/label/c.LogicModels_Indicator_DeleteConfirm';
import UNIT_IS from '@salesforce/label/c.LogicModels_Indicator_UnitIs';
import BETTER_WHEN_IS from '@salesforce/label/c.LogicModels_Indicator_BetterWhenIs';
import BASELINE_IS from '@salesforce/label/c.LogicModels_Indicator_BaselineIs';
import BASELINE_ON from '@salesforce/label/c.LogicModels_Indicator_BaselineOn';
import ADD_PERIOD from '@salesforce/label/c.LogicModels_Period_Add';
import PERIOD from '@salesforce/label/c.LogicModels_Period_Name';
import START_DATE from '@salesforce/label/c.LogicModels_Period_StartDate';
import END_DATE from '@salesforce/label/c.LogicModels_Period_EndDate';
import TARGET from '@salesforce/label/c.LogicModels_Period_Target';
import RESULT from '@salesforce/label/c.LogicModels_Period_Result';
import NOTES from '@salesforce/label/c.LogicModels_Period_Notes';
import PROGRESS from '@salesforce/label/c.LogicModels_Period_Progress';
import MET from '@salesforce/label/c.LogicModels_Period_Met';
import PERCENT from '@salesforce/label/c.LogicModels_Period_Percent';
import NO_PERIODS from '@salesforce/label/c.LogicModels_Period_None';
import ACTIONS from '@salesforce/label/c.LogicModels_Period_Actions';

export const LABELS = Object.freeze({
  title: TITLE,
  forLabel: FOR_LABEL,
  wholeOrganization: WHOLE_ORGANIZATION,
  programMissing: PROGRAM_MISSING,
  change: CHANGE,
  save: SAVE,
  cancel: CANCEL,
  add: ADD,
  addTo: ADD_TO,
  edit: EDIT,
  delete: DELETE,
  remove: REMOVE,
  name: NAME,
  description: DESCRIPTION,
  column: COLUMN,
  emptyColumn: EMPTY_COLUMN,
  selectHint: SELECT_HINT,
  lookAt: LOOK_AT,
  lookAtNone: LOOK_AT_NONE,
  findingEmpty: FINDING_EMPTY,
  findingNoIn: FINDING_NO_IN,
  findingNoOut: FINDING_NO_OUT,
  findingNoIndicator: FINDING_NO_INDICATOR,
  outcomes: OUTCOMES,
  saved: SAVED,
  deleted: DELETED,
  actionFailed: ACTION_FAILED,
  loading: LOADING,
  selectedPart: SELECTED_PART,
  moveUp: MOVE_UP,
  moveDown: MOVE_DOWN,
  deletePartConfirm: DELETE_PART_CONFIRM,
  leadsTo: LEADS_TO,
  comesFrom: COMES_FROM,
  addArrow: ADD_ARROW,
  arrowTarget: ARROW_TARGET,
  assumption: ASSUMPTION,
  noArrows: NO_ARROWS,
  noTargets: NO_TARGETS,
  noAssumption: NO_ASSUMPTION,
  indicators: INDICATORS,
  addIndicator: ADD_INDICATOR,
  indicatorName: INDICATOR_NAME,
  unit: UNIT,
  betterWhen: BETTER_WHEN,
  higher: HIGHER,
  lower: LOWER,
  baseline: BASELINE,
  baselineDate: BASELINE_DATE,
  noIndicators: NO_INDICATORS,
  deleteIndicatorConfirm: DELETE_INDICATOR_CONFIRM,
  unitIs: UNIT_IS,
  betterWhenIs: BETTER_WHEN_IS,
  baselineIs: BASELINE_IS,
  baselineOn: BASELINE_ON,
  addPeriod: ADD_PERIOD,
  period: PERIOD,
  startDate: START_DATE,
  endDate: END_DATE,
  target: TARGET,
  result: RESULT,
  notes: NOTES,
  progress: PROGRESS,
  met: MET,
  percent: PERCENT,
  noPeriods: NO_PERIODS,
  actions: ACTIONS
});

const STAGE_LABELS = Object.freeze({
  Input: STAGE_INPUT,
  Activity: STAGE_ACTIVITY,
  Output: STAGE_OUTPUT,
  Outcome_Short: STAGE_SHORT,
  Outcome_Intermediate: STAGE_INTERMEDIATE,
  Outcome_Long: STAGE_LONG,
  Impact: STAGE_IMPACT
});

/** The column's name, for a stage key of logicModelRules. */
export function stageLabel(key) {
  return STAGE_LABELS[key] || key;
}

/** A label with {0}, {1} filled in. */
export function format(template, ...values) {
  return String(template || '').replace(/\{(\d+)\}/g, (match, index) => {
    const value = values[Number(index)];
    return value === undefined || value === null ? '' : String(value);
  });
}

/** The message of a refused or failed call. */
export function messageFrom(error) {
  if (error && error.body && error.body.message) {
    return error.body.message;
  }
  return ACTION_FAILED;
}
