import { publish, subscribe, unsubscribe } from 'lightning/messageService';
import RECORD_CHANGED from '@salesforce/messageChannel/BarnCRM_Record_Changed__c';

/**
 * One Lightning Message Service channel for BarnCRM panels on the same page that refresh each
 * other (PF-04). A panel that changes a record's rows publishes the record id and its own name;
 * a panel showing that record's rows subscribes and reloads. Messages carry ids only, so the
 * subscriber reads again as its own user and never trusts data from another panel.
 *
 * Each panel gets a MessageContext with `@wire(MessageContext) messageContext;`.
 */

/** Tells the page that `recordId`'s rows changed. `source` is the publishing component's name. */
export function publishRecordChanged(messageContext, recordId, source) {
  if (!recordId) {
    return;
  }
  publish(messageContext, RECORD_CHANGED, { recordId, source });
}

/**
 * Calls `onChange()` when another panel says the record `getRecordId()` returns changed.
 * Messages from `source` itself and for other records are ignored. Call it from
 * connectedCallback (the wired MessageContext is set by then); `stopRecordChanged` ends it.
 */
export function subscribeRecordChanged(messageContext, getRecordId, source, onChange) {
  return subscribe(messageContext, RECORD_CHANGED, (message) => {
    if (message && message.source !== source && message.recordId === getRecordId()) {
      onChange();
    }
  });
}

/** Ends a subscription from `subscribeRecordChanged`; safe with null. */
export function stopRecordChanged(subscription) {
  if (subscription) {
    unsubscribe(subscription);
  }
}
