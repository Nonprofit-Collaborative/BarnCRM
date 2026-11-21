import { helpText } from 'c/barnHelpText';

/**
 * BarnCRM Connector's page text by help key (ADR-0164). c/connectorRules returns keys, not text,
 * so it stays framework free; this table turns a key into its words, each read with a literal
 * helpText call so scripts/ci/check-help-text.py can find it. `say(key, ...values)` fills `{0}`,
 * `{1}` in order.
 */
const TEXTS = {
  get Connector_Page_Title() {
    return helpText('Connector', 'Connector_Page_Title');
  },
  get Connector_Page_Intro() {
    return helpText('Connector', 'Connector_Page_Intro');
  },
  get Connector_Page_Connections() {
    return helpText('Connector', 'Connector_Page_Connections');
  },
  get Connector_Page_New() {
    return helpText('Connector', 'Connector_Page_New');
  },
  get Connector_Page_Empty() {
    return helpText('Connector', 'Connector_Page_Empty');
  },
  get Connector_Page_NoWrite() {
    return helpText('Connector', 'Connector_Page_NoWrite');
  },
  get Connector_Page_ViewerNotice() {
    return helpText('Connector', 'Connector_Page_ViewerNotice');
  },
  get Connector_Page_ReplaceKey() {
    return helpText('Connector', 'Connector_Page_ReplaceKey');
  },
  get Connector_Page_Disconnect() {
    return helpText('Connector', 'Connector_Page_Disconnect');
  },
  get Connector_Page_Delete() {
    return helpText('Connector', 'Connector_Page_Delete');
  },
  get Connector_Page_RecipesTab() {
    return helpText('Connector', 'Connector_Page_RecipesTab');
  },
  get Connector_Page_RunsTab() {
    return helpText('Connector', 'Connector_Page_RunsTab');
  },
  get Connector_Page_TemplatesTab() {
    return helpText('Connector', 'Connector_Page_TemplatesTab');
  },
  get Connector_Page_Check() {
    return helpText('Connector', 'Connector_Page_Check');
  },
  get Connector_Page_CheckAgain() {
    return helpText('Connector', 'Connector_Page_CheckAgain');
  },
  get Connector_Row_SecretHost() {
    return helpText('Connector', 'Connector_Row_SecretHost');
  },
  get Connector_Row_Detail() {
    return helpText('Connector', 'Connector_Row_Detail');
  },
  get Connector_Row_CalloutSteps() {
    return helpText('Connector', 'Connector_Row_CalloutSteps');
  },
  get Connector_Row_AccessSteps() {
    return helpText('Connector', 'Connector_Row_AccessSteps');
  },
  get Connector_Status_CalloutsOff() {
    return helpText('Connector', 'Connector_Status_CalloutsOff');
  },
  get Connector_Status_AccessMissing() {
    return helpText('Connector', 'Connector_Status_AccessMissing');
  },
  get Connector_Status_Disconnected() {
    return helpText('Connector', 'Connector_Status_Disconnected');
  },
  get Connector_Status_Ready() {
    return helpText('Connector', 'Connector_Status_Ready');
  },
  get Connector_Kind_ApiKeyHeader() {
    return helpText('Connector', 'Connector_Kind_ApiKeyHeader');
  },
  get Connector_Kind_BearerToken() {
    return helpText('Connector', 'Connector_Kind_BearerToken');
  },
  get Connector_Kind_BasicAuth() {
    return helpText('Connector', 'Connector_Kind_BasicAuth');
  },
  get Connector_Kind_SecretUrl() {
    return helpText('Connector', 'Connector_Kind_SecretUrl');
  },
  get Connector_Outcome_Connected() {
    return helpText('Connector', 'Connector_Outcome_Connected');
  },
  get Connector_Outcome_ConnectedAs() {
    return helpText('Connector', 'Connector_Outcome_ConnectedAs');
  },
  get Connector_Outcome_KeyRefused() {
    return helpText('Connector', 'Connector_Outcome_KeyRefused');
  },
  get Connector_Outcome_Answered() {
    return helpText('Connector', 'Connector_Outcome_Answered');
  },
  get Connector_Outcome_Created() {
    return helpText('Connector', 'Connector_Outcome_Created');
  },
  get Connector_Outcome_CreatedAccessMissing() {
    return helpText('Connector', 'Connector_Outcome_CreatedAccessMissing');
  },
  get Connector_Outcome_Replaced() {
    return helpText('Connector', 'Connector_Outcome_Replaced');
  },
  get Connector_Outcome_Disconnected() {
    return helpText('Connector', 'Connector_Outcome_Disconnected');
  },
  get Connector_Outcome_Deleted() {
    return helpText('Connector', 'Connector_Outcome_Deleted');
  },
  get Connector_Outcome_CalloutsOff() {
    return helpText('Connector', 'Connector_Outcome_CalloutsOff');
  },
  get Connector_Outcome_AccessAdded() {
    return helpText('Connector', 'Connector_Outcome_AccessAdded');
  },
  get Connector_Outcome_AccessMissing() {
    return helpText('Connector', 'Connector_Outcome_AccessMissing');
  },
  get Connector_Outcome_Unreachable() {
    return helpText('Connector', 'Connector_Outcome_Unreachable');
  },
  get Connector_Error_Label() {
    return helpText('Connector', 'Connector_Error_Label');
  },
  get Connector_Error_Kind() {
    return helpText('Connector', 'Connector_Error_Kind');
  },
  get Connector_Error_Url() {
    return helpText('Connector', 'Connector_Error_Url');
  },
  get Connector_Error_HeaderName() {
    return helpText('Connector', 'Connector_Error_HeaderName');
  },
  get Connector_Error_UserRequired() {
    return helpText('Connector', 'Connector_Error_UserRequired');
  },
  get Connector_Error_KeyRequired() {
    return helpText('Connector', 'Connector_Error_KeyRequired');
  },
  get Connector_Error_Unexpected() {
    return helpText('Connector', 'Connector_Error_Unexpected');
  },
  get Connector_Confirm_DisconnectTitle() {
    return helpText('Connector', 'Connector_Confirm_DisconnectTitle');
  },
  get Connector_Confirm_Disconnect() {
    return helpText('Connector', 'Connector_Confirm_Disconnect');
  },
  get Connector_Confirm_DeleteTitle() {
    return helpText('Connector', 'Connector_Confirm_DeleteTitle');
  },
  get Connector_Confirm_Delete() {
    return helpText('Connector', 'Connector_Confirm_Delete');
  },
  get Connector_Form_Name() {
    return helpText('Connector', 'Connector_Form_Name');
  },
  get Connector_Form_Kind() {
    return helpText('Connector', 'Connector_Form_Kind');
  },
  get Connector_Form_BaseUrl() {
    return helpText('Connector', 'Connector_Form_BaseUrl');
  },
  get Connector_Form_BaseUrlHelp() {
    return helpText('Connector', 'Connector_Form_BaseUrlHelp');
  },
  get Connector_Form_HeaderName() {
    return helpText('Connector', 'Connector_Form_HeaderName');
  },
  get Connector_Form_UserName() {
    return helpText('Connector', 'Connector_Form_UserName');
  },
  get Connector_Form_Cancel() {
    return helpText('Connector', 'Connector_Form_Cancel');
  },
  get Connector_Form_SecretUrlNotice() {
    return helpText('Connector', 'Connector_Form_SecretUrlNotice');
  },
  get Connector_Form_DebugNotice() {
    return helpText('Connector', 'Connector_Form_DebugNotice');
  },
  get Connector_Form_ErrorLockedUrl() {
    return helpText('Connector', 'Connector_Form_ErrorLockedUrl');
  },
  get Connector_Form_UrlPartFromKey() {
    return helpText('Connector', 'Connector_Form_UrlPartFromKey');
  },
  get Connector_Form_NewTitle() {
    return helpText('Connector', 'Connector_Form_NewTitle');
  },
  get Connector_Form_ReplaceTitle() {
    return helpText('Connector', 'Connector_Form_ReplaceTitle');
  },
  get Connector_Form_SecretUrl() {
    return helpText('Connector', 'Connector_Form_SecretUrl');
  },
  get Connector_Form_Key() {
    return helpText('Connector', 'Connector_Form_Key');
  },
  get Connector_Form_Create() {
    return helpText('Connector', 'Connector_Form_Create');
  },
  get Connector_Form_Replace() {
    return helpText('Connector', 'Connector_Form_Replace');
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
