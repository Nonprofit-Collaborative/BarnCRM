import { helpText } from 'c/barnHelpText';

/**
 * Recipe and Run History text by help key (CN-02, ADR-0164). c/connectorRecipeRules returns keys, not
 * text, so it stays framework free; each key is read with a literal helpText call so
 * scripts/ci/check-help-text.py can find it. `say(key, ...values)` fills `{0}`, `{1}` in order.
 */
const TEXTS = {
  get Connector_Access_Heading() {
    return helpText('Connector', 'Connector_Access_Heading');
  },
  get Connector_Access_Intro() {
    return helpText('Connector', 'Connector_Access_Intro');
  },
  get Connector_Access_NotReady() {
    return helpText('Connector', 'Connector_Access_NotReady');
  },
  get Connector_Access_NotSaved() {
    return helpText('Connector', 'Connector_Access_NotSaved');
  },
  get Connector_Access_Save() {
    return helpText('Connector', 'Connector_Access_Save');
  },
  get Connector_Access_Saved() {
    return helpText('Connector', 'Connector_Access_Saved');
  },
  get Connector_Access_Sets() {
    return helpText('Connector', 'Connector_Access_Sets');
  },
  get Connector_Editor_AddEntry() {
    return helpText('Connector', 'Connector_Editor_AddEntry');
  },
  get Connector_Editor_AddOtherwise() {
    return helpText('Connector', 'Connector_Editor_AddOtherwise');
  },
  get Connector_Editor_AddStep() {
    return helpText('Connector', 'Connector_Editor_AddStep');
  },
  get Connector_Editor_AddThen() {
    return helpText('Connector', 'Connector_Editor_AddThen');
  },
  get Connector_Editor_BodyInput() {
    return helpText('Connector', 'Connector_Editor_BodyInput');
  },
  get Connector_Editor_BodyMap() {
    return helpText('Connector', 'Connector_Editor_BodyMap');
  },
  get Connector_Editor_CheckResult() {
    return helpText('Connector', 'Connector_Editor_CheckResult');
  },
  get Connector_Editor_Close() {
    return helpText('Connector', 'Connector_Editor_Close');
  },
  get Connector_Editor_ConditionLabel() {
    return helpText('Connector', 'Connector_Editor_ConditionLabel');
  },
  get Connector_Editor_ConditionPath() {
    return helpText('Connector', 'Connector_Editor_ConditionPath');
  },
  get Connector_Editor_ConditionValue() {
    return helpText('Connector', 'Connector_Editor_ConditionValue');
  },
  get Connector_Editor_Conditions() {
    return helpText('Connector', 'Connector_Editor_Conditions');
  },
  get Connector_Editor_Connection() {
    return helpText('Connector', 'Connector_Editor_Connection');
  },
  get Connector_Editor_Delete() {
    return helpText('Connector', 'Connector_Editor_Delete');
  },
  get Connector_Editor_DeleteMessage() {
    return helpText('Connector', 'Connector_Editor_DeleteMessage');
  },
  get Connector_Editor_DeleteTitle() {
    return helpText('Connector', 'Connector_Editor_DeleteTitle');
  },
  get Connector_Editor_Deleted() {
    return helpText('Connector', 'Connector_Editor_Deleted');
  },
  get Connector_Editor_Description() {
    return helpText('Connector', 'Connector_Editor_Description');
  },
  get Connector_Editor_Details() {
    return helpText('Connector', 'Connector_Editor_Details');
  },
  get Connector_Editor_EntryName() {
    return helpText('Connector', 'Connector_Editor_EntryName');
  },
  get Connector_Editor_EntryValue() {
    return helpText('Connector', 'Connector_Editor_EntryValue');
  },
  get Connector_Editor_Headers() {
    return helpText('Connector', 'Connector_Editor_Headers');
  },
  get Connector_Editor_InOtherwise() {
    return helpText('Connector', 'Connector_Editor_InOtherwise');
  },
  get Connector_Editor_InThen() {
    return helpText('Connector', 'Connector_Editor_InThen');
  },
  get Connector_Editor_Input() {
    return helpText('Connector', 'Connector_Editor_Input');
  },
  get Connector_Editor_Map() {
    return helpText('Connector', 'Connector_Editor_Map');
  },
  get Connector_Editor_Match() {
    return helpText('Connector', 'Connector_Editor_Match');
  },
  get Connector_Editor_MatchAll() {
    return helpText('Connector', 'Connector_Editor_MatchAll');
  },
  get Connector_Editor_MatchAny() {
    return helpText('Connector', 'Connector_Editor_MatchAny');
  },
  get Connector_Editor_Method() {
    return helpText('Connector', 'Connector_Editor_Method');
  },
  get Connector_Editor_MoveDown() {
    return helpText('Connector', 'Connector_Editor_MoveDown');
  },
  get Connector_Editor_MoveUp() {
    return helpText('Connector', 'Connector_Editor_MoveUp');
  },
  get Connector_Editor_Name() {
    return helpText('Connector', 'Connector_Editor_Name');
  },
  get Connector_Editor_NewTitle() {
    return helpText('Connector', 'Connector_Editor_NewTitle');
  },
  get Connector_Editor_NoSteps() {
    return helpText('Connector', 'Connector_Editor_NoSteps');
  },
  get Connector_Editor_NotFoundOk() {
    return helpText('Connector', 'Connector_Editor_NotFoundOk');
  },
  get Connector_Editor_Operator() {
    return helpText('Connector', 'Connector_Editor_Operator');
  },
  get Connector_Editor_Outcome() {
    return helpText('Connector', 'Connector_Editor_Outcome');
  },
  get Connector_Editor_Owner() {
    return helpText('Connector', 'Connector_Editor_Owner');
  },
  get Connector_Editor_OwnerHelp() {
    return helpText('Connector', 'Connector_Editor_OwnerHelp');
  },
  get Connector_Editor_Path() {
    return helpText('Connector', 'Connector_Editor_Path');
  },
  get Connector_Editor_PathHelp() {
    return helpText('Connector', 'Connector_Editor_PathHelp');
  },
  get Connector_Editor_PathsHint() {
    return helpText('Connector', 'Connector_Editor_PathsHint');
  },
  get Connector_Editor_Problems() {
    return helpText('Connector', 'Connector_Editor_Problems');
  },
  get Connector_Editor_Publish() {
    return helpText('Connector', 'Connector_Editor_Publish');
  },
  get Connector_Editor_Published() {
    return helpText('Connector', 'Connector_Editor_Published');
  },
  get Connector_Editor_QueryParams() {
    return helpText('Connector', 'Connector_Editor_QueryParams');
  },
  get Connector_Editor_RecordId() {
    return helpText('Connector', 'Connector_Editor_RecordId');
  },
  get Connector_Editor_Remove() {
    return helpText('Connector', 'Connector_Editor_Remove');
  },
  get Connector_Editor_RunAs() {
    return helpText('Connector', 'Connector_Editor_RunAs');
  },
  get Connector_Editor_RunAsChosen() {
    return helpText('Connector', 'Connector_Editor_RunAsChosen');
  },
  get Connector_Editor_RunAsSaved() {
    return helpText('Connector', 'Connector_Editor_RunAsSaved');
  },
  get Connector_Editor_RunData() {
    return helpText('Connector', 'Connector_Editor_RunData');
  },
  get Connector_Editor_RunHeading() {
    return helpText('Connector', 'Connector_Editor_RunHeading');
  },
  get Connector_Editor_RunNow() {
    return helpText('Connector', 'Connector_Editor_RunNow');
  },
  get Connector_Editor_RunQueued() {
    return helpText('Connector', 'Connector_Editor_RunQueued');
  },
  get Connector_Editor_Sample() {
    return helpText('Connector', 'Connector_Editor_Sample');
  },
  get Connector_Editor_SampleHelp() {
    return helpText('Connector', 'Connector_Editor_SampleHelp');
  },
  get Connector_Editor_Save() {
    return helpText('Connector', 'Connector_Editor_Save');
  },
  get Connector_Editor_SaveFirst() {
    return helpText('Connector', 'Connector_Editor_SaveFirst');
  },
  get Connector_Editor_Saved() {
    return helpText('Connector', 'Connector_Editor_Saved');
  },
  get Connector_Editor_SavedQuery() {
    return helpText('Connector', 'Connector_Editor_SavedQuery');
  },
  get Connector_Editor_SendForReal() {
    return helpText('Connector', 'Connector_Editor_SendForReal');
  },
  get Connector_Editor_Settings() {
    return helpText('Connector', 'Connector_Editor_Settings');
  },
  get Connector_Editor_SlotValue() {
    return helpText('Connector', 'Connector_Editor_SlotValue');
  },
  get Connector_Editor_StepHeading() {
    return helpText('Connector', 'Connector_Editor_StepHeading');
  },
  get Connector_Editor_StepName() {
    return helpText('Connector', 'Connector_Editor_StepName');
  },
  get Connector_Editor_StopIfNone() {
    return helpText('Connector', 'Connector_Editor_StopIfNone');
  },
  get Connector_Editor_StopMessage() {
    return helpText('Connector', 'Connector_Editor_StopMessage');
  },
  get Connector_Editor_Success() {
    return helpText('Connector', 'Connector_Editor_Success');
  },
  get Connector_Editor_SuccessHelp() {
    return helpText('Connector', 'Connector_Editor_SuccessHelp');
  },
  get Connector_Editor_Test() {
    return helpText('Connector', 'Connector_Editor_Test');
  },
  get Connector_Editor_TestHeading() {
    return helpText('Connector', 'Connector_Editor_TestHeading');
  },
  get Connector_Editor_TestIntro() {
    return helpText('Connector', 'Connector_Editor_TestIntro');
  },
  get Connector_Editor_TestQueued() {
    return helpText('Connector', 'Connector_Editor_TestQueued');
  },
  get Connector_Editor_TestRecord() {
    return helpText('Connector', 'Connector_Editor_TestRecord');
  },
  get Connector_Editor_Then() {
    return helpText('Connector', 'Connector_Editor_Then');
  },
  get Connector_Editor_Value() {
    return helpText('Connector', 'Connector_Editor_Value');
  },
  get Connector_Editor_ValueHelp() {
    return helpText('Connector', 'Connector_Editor_ValueHelp');
  },
  get Connector_Editor_When() {
    return helpText('Connector', 'Connector_Editor_When');
  },
  get Connector_Editor_WhenManual() {
    return helpText('Connector', 'Connector_Editor_WhenManual');
  },
  get Connector_Editor_Working() {
    return helpText('Connector', 'Connector_Editor_Working');
  },
  get Connector_Error_Unexpected() {
    return helpText('Connector', 'Connector_Error_Unexpected');
  },
  get Connector_Operator_contains() {
    return helpText('Connector', 'Connector_Operator_contains');
  },
  get Connector_Operator_does_not_contain() {
    return helpText('Connector', 'Connector_Operator_does_not_contain');
  },
  get Connector_Operator_equals() {
    return helpText('Connector', 'Connector_Operator_equals');
  },
  get Connector_Operator_greater_than() {
    return helpText('Connector', 'Connector_Operator_greater_than');
  },
  get Connector_Operator_is_not_null() {
    return helpText('Connector', 'Connector_Operator_is_not_null');
  },
  get Connector_Operator_is_null() {
    return helpText('Connector', 'Connector_Operator_is_null');
  },
  get Connector_Operator_less_than() {
    return helpText('Connector', 'Connector_Operator_less_than');
  },
  get Connector_Operator_not_equals() {
    return helpText('Connector', 'Connector_Operator_not_equals');
  },
  get Connector_Operator_starts_with() {
    return helpText('Connector', 'Connector_Operator_starts_with');
  },
  get Connector_Recipe_ErrorCodes() {
    return helpText('Connector', 'Connector_Recipe_ErrorCodes');
  },
  get Connector_Recipe_ErrorCondition() {
    return helpText('Connector', 'Connector_Recipe_ErrorCondition');
  },
  get Connector_Recipe_ErrorConnection() {
    return helpText('Connector', 'Connector_Recipe_ErrorConnection');
  },
  get Connector_Recipe_ErrorFind() {
    return helpText('Connector', 'Connector_Recipe_ErrorFind');
  },
  get Connector_Recipe_ErrorHeader() {
    return helpText('Connector', 'Connector_Recipe_ErrorHeader');
  },
  get Connector_Recipe_ErrorMap() {
    return helpText('Connector', 'Connector_Recipe_ErrorMap');
  },
  get Connector_Recipe_ErrorMergeField() {
    return helpText('Connector', 'Connector_Recipe_ErrorMergeField');
  },
  get Connector_Recipe_ErrorMethod() {
    return helpText('Connector', 'Connector_Recipe_ErrorMethod');
  },
  get Connector_Recipe_ErrorNesting() {
    return helpText('Connector', 'Connector_Recipe_ErrorNesting');
  },
  get Connector_Recipe_ErrorNoSteps() {
    return helpText('Connector', 'Connector_Recipe_ErrorNoSteps');
  },
  get Connector_Recipe_ErrorPath() {
    return helpText('Connector', 'Connector_Recipe_ErrorPath');
  },
  get Connector_Recipe_ErrorQuery() {
    return helpText('Connector', 'Connector_Recipe_ErrorQuery');
  },
  get Connector_Recipe_ErrorRecordId() {
    return helpText('Connector', 'Connector_Recipe_ErrorRecordId');
  },
  get Connector_Recipe_ErrorRequestPath() {
    return helpText('Connector', 'Connector_Recipe_ErrorRequestPath');
  },
  get Connector_Recipe_ErrorSlot() {
    return helpText('Connector', 'Connector_Recipe_ErrorSlot');
  },
  get Connector_Recipe_ErrorStepId() {
    return helpText('Connector', 'Connector_Recipe_ErrorStepId');
  },
  get Connector_Recipe_ErrorStepKind() {
    return helpText('Connector', 'Connector_Recipe_ErrorStepKind');
  },
  get Connector_Recipe_ErrorStop() {
    return helpText('Connector', 'Connector_Recipe_ErrorStop');
  },
  get Connector_Recipe_ErrorTooManySteps() {
    return helpText('Connector', 'Connector_Recipe_ErrorTooManySteps');
  },
  get Connector_Recipes_Detail() {
    return helpText('Connector', 'Connector_Recipes_Detail');
  },
  get Connector_Recipes_Empty() {
    return helpText('Connector', 'Connector_Recipes_Empty');
  },
  get Connector_Recipes_Heading() {
    return helpText('Connector', 'Connector_Recipes_Heading');
  },
  get Connector_Recipes_Intro() {
    return helpText('Connector', 'Connector_Recipes_Intro');
  },
  get Connector_Recipes_New() {
    return helpText('Connector', 'Connector_Recipes_New');
  },
  get Connector_Recipes_Open() {
    return helpText('Connector', 'Connector_Recipes_Open');
  },
  get Connector_Recipes_OpenNamed() {
    return helpText('Connector', 'Connector_Recipes_OpenNamed');
  },
  get Connector_Recipes_Unpublished() {
    return helpText('Connector', 'Connector_Recipes_Unpublished');
  },
  get Connector_RunAs_Automation() {
    return helpText('Connector', 'Connector_RunAs_Automation');
  },
  get Connector_RunAs_ConfirmButton() {
    return helpText('Connector', 'Connector_RunAs_ConfirmButton');
  },
  get Connector_RunAs_ConfirmMessage() {
    return helpText('Connector', 'Connector_RunAs_ConfirmMessage');
  },
  get Connector_RunAs_ConfirmTitle() {
    return helpText('Connector', 'Connector_RunAs_ConfirmTitle');
  },
  get Connector_RunAs_ErrorChoice() {
    return helpText('Connector', 'Connector_RunAs_ErrorChoice');
  },
  get Connector_RunAs_ErrorConfirm() {
    return helpText('Connector', 'Connector_RunAs_ErrorConfirm');
  },
  get Connector_RunAs_System() {
    return helpText('Connector', 'Connector_RunAs_System');
  },
  get Connector_Runs_Back() {
    return helpText('Connector', 'Connector_Runs_Back');
  },
  get Connector_Runs_Detail() {
    return helpText('Connector', 'Connector_Runs_Detail');
  },
  get Connector_Runs_Empty() {
    return helpText('Connector', 'Connector_Runs_Empty');
  },
  get Connector_Runs_Failure() {
    return helpText('Connector', 'Connector_Runs_Failure');
  },
  get Connector_Runs_Heading() {
    return helpText('Connector', 'Connector_Runs_Heading');
  },
  get Connector_Runs_Intro() {
    return helpText('Connector', 'Connector_Runs_Intro');
  },
  get Connector_Runs_Open() {
    return helpText('Connector', 'Connector_Runs_Open');
  },
  get Connector_Runs_Refresh() {
    return helpText('Connector', 'Connector_Runs_Refresh');
  },
  get Connector_Runs_Response() {
    return helpText('Connector', 'Connector_Runs_Response');
  },
  get Connector_Runs_Retried() {
    return helpText('Connector', 'Connector_Runs_Retried');
  },
  get Connector_Runs_Retry() {
    return helpText('Connector', 'Connector_Runs_Retry');
  },
  get Connector_Runs_Steps() {
    return helpText('Connector', 'Connector_Runs_Steps');
  },
  get Connector_Runs_WouldDo() {
    return helpText('Connector', 'Connector_Runs_WouldDo');
  },
  get Connector_StartedBy_AppPoll() {
    return helpText('Connector', 'Connector_StartedBy_AppPoll');
  },
  get Connector_StartedBy_Flow() {
    return helpText('Connector', 'Connector_StartedBy_Flow');
  },
  get Connector_StartedBy_Manual() {
    return helpText('Connector', 'Connector_StartedBy_Manual');
  },
  get Connector_StartedBy_RecordChange() {
    return helpText('Connector', 'Connector_StartedBy_RecordChange');
  },
  get Connector_StartedBy_Schedule() {
    return helpText('Connector', 'Connector_StartedBy_Schedule');
  },
  get Connector_StartedBy_Test() {
    return helpText('Connector', 'Connector_StartedBy_Test');
  },
  get Connector_StartedBy_Webhook() {
    return helpText('Connector', 'Connector_StartedBy_Webhook');
  },
  get Connector_Status_AccessMissing() {
    return helpText('Connector', 'Connector_Status_AccessMissing');
  },
  get Connector_Status_Active() {
    return helpText('Connector', 'Connector_Status_Active');
  },
  get Connector_Status_CalloutsOff() {
    return helpText('Connector', 'Connector_Status_CalloutsOff');
  },
  get Connector_Status_Disconnected() {
    return helpText('Connector', 'Connector_Status_Disconnected');
  },
  get Connector_Status_Draft() {
    return helpText('Connector', 'Connector_Status_Draft');
  },
  get Connector_Status_Failed() {
    return helpText('Connector', 'Connector_Status_Failed');
  },
  get Connector_Status_Paused() {
    return helpText('Connector', 'Connector_Status_Paused');
  },
  get Connector_Status_PausedByFailures() {
    return helpText('Connector', 'Connector_Status_PausedByFailures');
  },
  get Connector_Status_Queued() {
    return helpText('Connector', 'Connector_Status_Queued');
  },
  get Connector_Status_Received() {
    return helpText('Connector', 'Connector_Status_Received');
  },
  get Connector_Status_Rejected() {
    return helpText('Connector', 'Connector_Status_Rejected');
  },
  get Connector_Status_Running() {
    return helpText('Connector', 'Connector_Status_Running');
  },
  get Connector_Status_Skipped() {
    return helpText('Connector', 'Connector_Status_Skipped');
  },
  get Connector_Status_Succeeded() {
    return helpText('Connector', 'Connector_Status_Succeeded');
  },
  get Connector_Status_Waiting() {
    return helpText('Connector', 'Connector_Status_Waiting');
  },
  get Connector_Step_CallApp() {
    return helpText('Connector', 'Connector_Step_CallApp');
  },
  get Connector_Step_Create() {
    return helpText('Connector', 'Connector_Step_Create');
  },
  get Connector_Step_Find() {
    return helpText('Connector', 'Connector_Step_Find');
  },
  get Connector_Step_If() {
    return helpText('Connector', 'Connector_Step_If');
  },
  get Connector_Step_Stop() {
    return helpText('Connector', 'Connector_Step_Stop');
  },
  get Connector_Step_Update() {
    return helpText('Connector', 'Connector_Step_Update');
  },
  get Connector_Step_Upsert() {
    return helpText('Connector', 'Connector_Step_Upsert');
  }
};

/** The words for a help key, with `{0}`, `{1}` ... filled in order; blank for an unknown key. */
export function say(key, ...values) {
  const template = Object.prototype.hasOwnProperty.call(TEXTS, key) ? TEXTS[key] : '';
  let result = template;
  values.forEach((value, index) => {
    if (value !== undefined) {
      result = result.split(`{${index}}`).join(String(value));
    }
  });
  return result;
}
