/**
 * The one-step status changes offered as quick actions on Giving record pages
 * (people-giving-19). Each changes one field to one value, after a one-line confirm, and only
 * from the values where the change makes sense; anywhere else the window says why and offers
 * only Close. The rules on each object (the gift's Pending-only cancel, the ask rules' Closed
 * Date, the plan's Completed Date) still run on the save, so nothing here re-implements them.
 *
 * Plain data and functions, so the same table serves any front end (plan 9.9). The wording
 * comes from the Giving help catalog, named by literal keys so the catalog check can see them.
 */
import GIFT_STATUS from '@salesforce/schema/Gift__c.Status__c';
import ACKNOWLEDGMENT_STATUS from '@salesforce/schema/Gift__c.Acknowledgment_Status__c';
import ASK_OUTCOME from '@salesforce/schema/Ask__c.Outcome__c';
import PLAN_STATUS from '@salesforce/schema/Stewardship_Plan__c.Status__c';
import { helpText } from 'c/barnHelpText';

const TO_ACKNOWLEDGE = 'To acknowledge';

export const QUICK_STATUS = Object.freeze({
  cancelPendingGift: {
    field: GIFT_STATUS,
    value: 'Cancelled',
    appliesFrom: (current) => current === 'Pending',
    destructive: true,
    confirm: () => helpText('Giving', 'Giving_QuickStatus_CancelPendingGift_Confirm'),
    notApplicable: () => helpText('Giving', 'Giving_QuickStatus_CancelPendingGift_NotApplicable'),
    done: () => helpText('Giving', 'Giving_QuickStatus_CancelPendingGift_Done')
  },
  thankAgain: {
    field: ACKNOWLEDGMENT_STATUS,
    value: TO_ACKNOWLEDGE,
    appliesFrom: (current) => current !== TO_ACKNOWLEDGE,
    destructive: false,
    confirm: () => helpText('Giving', 'Giving_QuickStatus_ThankAgain_Confirm'),
    notApplicable: () => helpText('Giving', 'Giving_QuickStatus_ThankAgain_NotApplicable'),
    done: () => helpText('Giving', 'Giving_QuickStatus_ThankAgain_Done')
  },
  doNotThank: {
    field: ACKNOWLEDGMENT_STATUS,
    value: 'Do not acknowledge',
    appliesFrom: (current) => current === TO_ACKNOWLEDGE,
    destructive: false,
    confirm: () => helpText('Giving', 'Giving_QuickStatus_DoNotThank_Confirm'),
    notApplicable: () => helpText('Giving', 'Giving_QuickStatus_DoNotThank_NotApplicable'),
    done: () => helpText('Giving', 'Giving_QuickStatus_DoNotThank_Done')
  },
  reopenAsk: {
    field: ASK_OUTCOME,
    value: 'Open',
    appliesFrom: (current) => Boolean(current) && current !== 'Open',
    destructive: false,
    confirm: () => helpText('Giving', 'Giving_QuickStatus_ReopenAsk_Confirm'),
    notApplicable: () => helpText('Giving', 'Giving_QuickStatus_ReopenAsk_NotApplicable'),
    done: () => helpText('Giving', 'Giving_QuickStatus_ReopenAsk_Done')
  },
  markPlanComplete: {
    field: PLAN_STATUS,
    value: 'Complete',
    appliesFrom: (current) => current === 'Running',
    destructive: false,
    confirm: () => helpText('Giving', 'Giving_QuickStatus_MarkPlanComplete_Confirm'),
    notApplicable: () => helpText('Giving', 'Giving_QuickStatus_MarkPlanComplete_NotApplicable'),
    done: () => helpText('Giving', 'Giving_QuickStatus_MarkPlanComplete_Done')
  }
});

/** The definition for an action name, or undefined for a name this table does not hold. */
export function quickStatus(name) {
  return Object.prototype.hasOwnProperty.call(QUICK_STATUS, name) ? QUICK_STATUS[name] : undefined;
}

/** The getRecord field id ("Object.Field") an action reads. */
export function fieldId(definition) {
  return definition.field.objectApiName + '.' + definition.field.fieldApiName;
}

/** The updateRecord input that makes the change on one record. */
export function updateInput(definition, recordId) {
  return { fields: { Id: recordId, [definition.field.fieldApiName]: definition.value } };
}
