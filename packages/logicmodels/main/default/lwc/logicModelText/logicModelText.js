/**
 * The Logic Model Builder's words, in one place for its three panels: every label comes from
 * the LogicModels custom labels, so the text exports as translatable strings (plan 9.9).
 */
import TITLE from '@salesforce/label/c.LogicModels_Builder_Title';
import FOR_LABEL from '@salesforce/label/c.LogicModels_Builder_For';
import WHOLE_ORGANIZATION from '@salesforce/label/c.LogicModels_Builder_WholeOrganization';
import PROGRAM_MISSING from '@salesforce/label/c.LogicModels_Builder_ProgramMissing';
import CHANGE from '@salesforce/label/c.LogicModels_Builder_Change';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import ADD_TO from '@salesforce/label/c.LogicModels_Builder_AddTo';
import ADD from '@salesforce/label/c.Core_CmdtManager_AddButton';
import EDIT from '@salesforce/label/c.Core_CmdtManager_EditAction';
import DELETE from '@salesforce/label/c.Core_Find_Delete';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import NAME from '@salesforce/label/c.Core_CmdtManager_NameField';
import DESCRIPTION from '@salesforce/label/c.Core_Shared_Description';
import COLUMN from '@salesforce/label/c.Core_ImportRow_ColumnHeader';
import EMPTY_COLUMN from '@salesforce/label/c.LogicModels_Builder_EmptyColumn';
import LOOK_AT from '@salesforce/label/c.LogicModels_Builder_LookAt';
import FINDING_EMPTY from '@salesforce/label/c.LogicModels_Builder_FindingEmptyStage';
import FINDING_NO_IN from '@salesforce/label/c.LogicModels_Builder_FindingNoArrowIn';
import FINDING_NO_OUT from '@salesforce/label/c.LogicModels_Builder_FindingNoArrowOut';
import FINDING_NO_INDICATOR from '@salesforce/label/c.LogicModels_Builder_FindingNoIndicator';
import OUTCOMES from '@salesforce/label/c.LogicModels_Builder_Outcomes';
import SAVED from '@salesforce/label/c.Core_Shared_Saved';
import DELETED from '@salesforce/label/c.LogicModels_Builder_Deleted';
import ARROW_PAIR from '@salesforce/label/c.Core_Address_DateRange';
import BACKWARD_ARROWS from '@salesforce/label/c.LogicModels_Builder_BackwardArrows';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import STAGE_INPUT from '@salesforce/label/c.LogicModels_Stage_Input';
import STAGE_ACTIVITY from '@salesforce/label/c.LogicModels_Stage_Activity';
import STAGE_OUTPUT from '@salesforce/label/c.LogicModels_Stage_Output';
import STAGE_SHORT from '@salesforce/label/c.LogicModels_Stage_OutcomeShort';
import STAGE_INTERMEDIATE from '@salesforce/label/c.LogicModels_Stage_OutcomeIntermediate';
import STAGE_LONG from '@salesforce/label/c.LogicModels_Stage_OutcomeLong';
import STAGE_IMPACT from '@salesforce/label/c.LogicModels_Stage_Impact';
import SELECTED_PART from '@salesforce/label/c.LogicModels_Part_Title';
import MOVE_UP from '@salesforce/label/c.Core_Shared_MoveUp';
import MOVE_DOWN from '@salesforce/label/c.Core_Shared_MoveDown';
import DELETE_PART_CONFIRM from '@salesforce/label/c.LogicModels_Part_DeleteConfirm';
import LEADS_TO from '@salesforce/label/c.LogicModels_Part_LeadsTo';
import COMES_FROM from '@salesforce/label/c.LogicModels_Part_ComesFrom';
import ADD_ARROW from '@salesforce/label/c.LogicModels_Part_AddArrow';
import ARROW_TARGET from '@salesforce/label/c.LogicModels_Part_ArrowTarget';
import ASSUMPTION from '@salesforce/label/c.LogicModels_Part_Assumption';
import NO_ARROWS from '@salesforce/label/c.LogicModels_Part_NoArrows';
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
import PERIOD from '@salesforce/label/c.Core_Shared_Period';
import START_DATE from '@salesforce/label/c.Core_Shared_StartDate';
import END_DATE from '@salesforce/label/c.Core_Shared_EndDate';
import TARGET from '@salesforce/label/c.LogicModels_Period_Target';
import RESULT from '@salesforce/label/c.Core_Find_Result';
import NOTES from '@salesforce/label/c.LogicModels_Period_Notes';
import PROGRESS from '@salesforce/label/c.LogicModels_Period_Progress';
import MET from '@salesforce/label/c.LogicModels_Period_Met';
import PERCENT from '@salesforce/label/c.LogicModels_Period_Percent';
import NO_PERIODS from '@salesforce/label/c.LogicModels_Period_None';
import ACTIONS from '@salesforce/label/c.Core_Shared_Actions';
import SOURCE from '@salesforce/label/c.LogicModels_Source_Title';
import SOURCE_MANUAL from '@salesforce/label/c.LogicModels_Source_Manual';
import SOURCE_IMPORT from '@salesforce/label/c.LogicModels_Source_Import';
import SOURCE_COMPUTED from '@salesforce/label/c.LogicModels_Source_Computed';
import RESULTS_ARE from '@salesforce/label/c.LogicModels_Source_ResultsAre';
import COMPUTED_FROM from '@salesforce/label/c.LogicModels_Source_ComputedFrom';
import SOME_QUERY from '@salesforce/label/c.LogicModels_Source_SomeQuery';
import LAST_RUN from '@salesforce/label/c.LogicModels_Source_LastRun';
import NOT_RUN_YET from '@salesforce/label/c.LogicModels_Source_NotRunYet';
import SAVED_QUERY from '@salesforce/label/c.LogicModels_Source_Query';
import NO_QUERIES from '@salesforce/label/c.LogicModels_Source_NoQueries';
import DATE_FIELD from '@salesforce/label/c.LogicModels_Source_DateFieldLabel';
import WORK_OUT from '@salesforce/label/c.LogicModels_Source_Function';
import COUNT from '@salesforce/label/c.LogicModels_Source_Count';
import SUM from '@salesforce/label/c.LogicModels_Source_Sum';
import UNIQUE from '@salesforce/label/c.LogicModels_Source_Unique';
import FIELD from '@salesforce/label/c.Core_AccessExplorer_Field';
import REFRESH from '@salesforce/label/c.LogicModels_Source_Refresh';
import RESULT_COMPUTED from '@salesforce/label/c.LogicModels_Source_ResultComputed';
import COUNT_OF from '@salesforce/label/c.LogicModels_Source_CountOf';
import SUM_OF from '@salesforce/label/c.LogicModels_Source_SumOf';
import UNIQUE_OF from '@salesforce/label/c.LogicModels_Source_UniqueOf';
import DOWNLOAD_RESULTS from '@salesforce/label/c.LogicModels_Results_Download';
import NO_RESULT_ROWS from '@salesforce/label/c.LogicModels_Results_None';
import REPORT_TITLE from '@salesforce/label/c.LogicModels_Report_Title';
import REPORT_PERIODS from '@salesforce/label/c.LogicModels_Report_Periods';
import REPORT_CHOOSE_ONE from '@salesforce/label/c.LogicModels_Report_ChooseOne';
import REPORT_DOWNLOAD_CSV from '@salesforce/label/c.Core_AccessExplorer_Download';
import REPORT_PRINTABLE from '@salesforce/label/c.LogicModels_Report_Printable';
import REPORT_PART from '@salesforce/label/c.LogicModels_Report_Part';
import REPORT_INDICATOR from '@salesforce/label/c.LogicModels_Report_Indicator';
import REPORT_META from '@salesforce/label/c.LogicModels_Report_Meta';
import REPORT_PERIOD_DATES from '@salesforce/label/c.Core_Address_DateRange';
import REPORT_DOWNLOADED from '@salesforce/label/c.Core_Shared_ReportDownloaded';
import BACK_TO_MODEL from '@salesforce/label/c.LogicModels_Builder_BackToModel';
import CHECK_AGAIN from '@salesforce/label/c.Core_SuiteChoice_CheckAgain';
import PERIODS_TITLE from '@salesforce/label/c.LogicModels_Periods_Title';
import ADD_TO_EVERY from '@salesforce/label/c.LogicModels_Periods_AddToEvery';
import USE_MODEL_PERIODS from '@salesforce/label/c.LogicModels_Periods_UseModel';
import TEMPLATE from '@salesforce/label/c.Core_Import_StepTemplate';
import ALL from '@salesforce/label/c.Core_DataJobs_ShowAll';
import STARTER_PEOPLE_SERVED from '@salesforce/label/c.LogicModels_Starter_PeopleServed';
import STARTER_SERVICES_DELIVERED from '@salesforce/label/c.LogicModels_Starter_ServicesDelivered';
import STARTER_VOLUNTEER_HOURS from '@salesforce/label/c.LogicModels_Starter_VolunteerHours';
import STARTER_GRANTS_AWARDED from '@salesforce/label/c.LogicModels_Starter_GrantsAwarded';
import { helpText } from 'c/barnHelpText';

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
  get selectHint() {
    return helpText('LogicModels', 'LogicModels_Builder_SelectHint');
  },
  lookAt: LOOK_AT,
  get lookAtNone() {
    return helpText('LogicModels', 'LogicModels_Builder_LookAtNone');
  },
  findingEmpty: FINDING_EMPTY,
  findingNoIn: FINDING_NO_IN,
  findingNoOut: FINDING_NO_OUT,
  findingNoIndicator: FINDING_NO_INDICATOR,
  outcomes: OUTCOMES,
  saved: SAVED,
  deleted: DELETED,
  get actionFailed() {
    return helpText('LogicModels', 'LogicModels_Builder_ActionFailed');
  },
  backToModel: BACK_TO_MODEL,
  checkAgain: CHECK_AGAIN,
  get deletePeriodConfirm() {
    return helpText('LogicModels', 'LogicModels_Period_DeleteConfirm');
  },
  get removeArrowConfirm() {
    return helpText('LogicModels', 'LogicModels_Part_RemoveArrowConfirm');
  },
  get resultsWorkedOut() {
    return helpText('LogicModels', 'LogicModels_Source_WorkedOut');
  },
  get stillWorking() {
    return helpText('LogicModels', 'LogicModels_Source_StillWorking');
  },
  arrowPair: ARROW_PAIR,
  backwardArrows: BACKWARD_ARROWS,
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
  get noTargets() {
    return helpText('LogicModels', 'LogicModels_Part_NoTargets');
  },
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
  actions: ACTIONS,
  source: SOURCE,
  sourceManual: SOURCE_MANUAL,
  sourceImport: SOURCE_IMPORT,
  sourceComputed: SOURCE_COMPUTED,
  resultsAre: RESULTS_ARE,
  computedFrom: COMPUTED_FROM,
  someQuery: SOME_QUERY,
  lastRun: LAST_RUN,
  notRunYet: NOT_RUN_YET,
  savedQuery: SAVED_QUERY,
  get savedQueryHelp() {
    return helpText('LogicModels', 'LogicModels_Source_QueryHelp');
  },
  noQueries: NO_QUERIES,
  dateField: DATE_FIELD,
  workOut: WORK_OUT,
  count: COUNT,
  sum: SUM,
  unique: UNIQUE,
  field: FIELD,
  refresh: REFRESH,
  get refreshing() {
    return helpText('LogicModels', 'LogicModels_Source_Working');
  },
  resultComputed: RESULT_COMPUTED,
  countOf: COUNT_OF,
  sumOf: SUM_OF,
  uniqueOf: UNIQUE_OF,
  downloadResults: DOWNLOAD_RESULTS,
  noResultRows: NO_RESULT_ROWS,
  reportTitle: REPORT_TITLE,
  reportPeriods: REPORT_PERIODS,
  get reportNoPeriods() {
    return helpText('LogicModels', 'LogicModels_Report_NoPeriods');
  },
  get reportNoIndicators() {
    return helpText('LogicModels', 'LogicModels_Report_NoIndicators');
  },
  reportChooseOne: REPORT_CHOOSE_ONE,
  reportDownloadCsv: REPORT_DOWNLOAD_CSV,
  reportPrintable: REPORT_PRINTABLE,
  get reportPrintHelp() {
    return helpText('LogicModels', 'LogicModels_Report_PrintHelp');
  },
  reportPart: REPORT_PART,
  reportIndicator: REPORT_INDICATOR,
  reportMeta: REPORT_META,
  reportPeriodDates: REPORT_PERIOD_DATES,
  reportDownloaded: REPORT_DOWNLOADED,
  periodsTitle: PERIODS_TITLE,
  addToEvery: ADD_TO_EVERY,
  useModelPeriods: USE_MODEL_PERIODS,
  get periodsIntro() {
    return helpText('LogicModels', 'LogicModels_Periods_Intro');
  },
  get periodsAdded() {
    return helpText('LogicModels', 'LogicModels_Periods_Added');
  },
  get periodsUsedAdded() {
    return helpText('LogicModels', 'LogicModels_Periods_UsedAdded');
  },
  get periodsDeleteConfirm() {
    return helpText('LogicModels', 'LogicModels_Periods_DeleteConfirm');
  },
  template: TEMPLATE,
  all: ALL,
  get starterHelp() {
    return helpText('LogicModels', 'LogicModels_Starter_Help');
  }
});

/** A computed indicator starter's name, by its key (R-IN8). */
const STARTER_LABELS = Object.freeze({
  peopleServed: STARTER_PEOPLE_SERVED,
  servicesDelivered: STARTER_SERVICES_DELIVERED,
  volunteerHours: STARTER_VOLUNTEER_HOURS,
  grantsAwarded: STARTER_GRANTS_AWARDED
});

export function starterLabel(key) {
  return STARTER_LABELS[key] || key;
}

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
  return LABELS.actionFailed;
}
