/**
 * Requests and issues (D-201): the views of the Requests tab, the triage choices, and which panel
 * fields changed. Plain JavaScript with no Salesforce imports (plan Section 9.9), so a WordPress
 * build can reuse it.
 */

/** The Requests tab's views, in button order; each key is a help text suffix. */
export const VIEWS = ['mine', 'open', 'unassigned', 'overdue', 'closed'];

export const STATUSES = [
  'New',
  'In Progress',
  'Waiting on Requester',
  'Resolved',
  'Closed',
  'Cancelled'
];

export const PRIORITIES = ['Low', 'Medium', 'High', 'Urgent'];

/** The request fields the panel may change, by the detail property that holds each. */
export const EDITABLE = {
  status: 'Status__c',
  priority: 'Priority__c',
  ownerId: 'OwnerId',
  dueDate: 'Due_Date__c',
  resolution: 'Resolution__c',
  projectId: 'Project__c'
};

/** Picklist options for a lightning-combobox. */
export function options(values) {
  return values.map((value) => ({ label: value, value }));
}

/** A view key, or the first view when it is not one. */
export function viewOrDefault(view) {
  return VIEWS.includes(view) ? view : VIEWS[0];
}

/**
 * The fields to save: each editable field whose draft differs from the loaded request, by API
 * name; blank text saves as null.
 */
export function changesBetween(loaded, draft) {
  const changes = {};
  Object.entries(EDITABLE).forEach(([property, field]) => {
    if (!(property in (draft || {}))) {
      return;
    }
    const before = loaded?.[property] ?? null;
    const after = draft[property] === '' ? null : (draft[property] ?? null);
    if (before !== after) {
      changes[field] = after;
    }
  });
  return changes;
}

/** Rows as the list shows them: an overdue row's due date in the error color. */
export function decorate(rows) {
  return (rows || []).map((row) => ({
    ...row,
    rowClass: row.overdue ? 'slds-text-color_error' : ''
  }));
}
