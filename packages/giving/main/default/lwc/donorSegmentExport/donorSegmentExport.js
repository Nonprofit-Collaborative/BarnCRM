/**
 * Lays out a donor segment export for an email tool (feature G-28, canonical model R-DS5).
 *
 * Framework free on purpose (plan Section 9.9): no Lightning or Salesforce imports, so the same
 * layouts can serve another edition of BarnCRM. The server reads the rows, in the person's own
 * access, and has already left out anyone with no email, Email Opt Out ticked or marked deceased;
 * this module arranges the columns per tool, writes each address once, and tags the rows.
 *
 * The header names are each tool's own field names, so they are not translated: Mailchimp and
 * Constant Contact match on them when the file is imported.
 */

export const MAILCHIMP = 'mailchimp';
export const CONSTANT_CONTACT = 'constantContact';
export const ALL_COLUMNS = 'all';

/** The path of the column that carries the segment name. */
export const TAG_PATH = '__segmentTag';

const LAYOUT_COLUMNS = Object.freeze({
  [MAILCHIMP]: [
    { label: 'Email Address', path: 'Email' },
    { label: 'First Name', path: 'FirstName' },
    { label: 'Last Name', path: 'LastName' },
    { label: 'Tags', path: TAG_PATH }
  ],
  [CONSTANT_CONTACT]: [
    { label: 'Email address', path: 'Email' },
    { label: 'First name', path: 'FirstName' },
    { label: 'Last name', path: 'LastName' },
    { label: 'Street address line 1', path: 'MailingStreet' },
    { label: 'City', path: 'MailingCity' },
    { label: 'State/Province', path: 'MailingState' },
    { label: 'Zip/Postal code', path: 'MailingPostalCode' },
    { label: 'Country', path: 'MailingCountry' }
  ]
});

/** Whether a layout is one of the email tool layouts, which need people with an email. */
export function isEmailLayout(layout) {
  return Object.prototype.hasOwnProperty.call(LAYOUT_COLUMNS, layout);
}

/**
 * The columns of the file: the tool's for an email layout, or the segment's own (as the server
 * labelled them) for All Columns.
 */
export function columnsFor(layout, segmentColumns) {
  if (isEmailLayout(layout)) {
    return LAYOUT_COLUMNS[layout].map((column) => ({ ...column }));
  }
  return (segmentColumns || []).map((column) => ({ label: column.label, path: column.path }));
}

/** An email address as compared: trimmed and lower case; empty when there is none. */
export function emailKey(value) {
  return value === undefined || value === null ? '' : String(value).trim().toLowerCase();
}

/**
 * Starts a collector for one export. `add` takes one page of server rows and returns the rows
 * to write; across pages it keeps the first row of each address and counts the rest. For All
 * Columns rows pass through untouched.
 */
export function createCollector(layout, segmentName) {
  const seen = new Set();
  const state = { duplicates: 0 };
  const email = isEmailLayout(layout);
  return {
    add(rows) {
      if (!email) {
        return rows || [];
      }
      const kept = [];
      for (const row of rows || []) {
        const key = emailKey(row.Email);
        if (!key) {
          continue;
        }
        if (seen.has(key)) {
          state.duplicates += 1;
          continue;
        }
        seen.add(key);
        kept.push(emailRow(row, segmentName));
      }
      return kept;
    },
    get duplicates() {
      return state.duplicates;
    }
  };
}

/** A row ready for an email tool: the address trimmed, the street on one line, the tag set. */
function emailRow(row, segmentName) {
  const street = row.MailingStreet ? String(row.MailingStreet).split(/\r?\n/).join(', ') : '';
  return {
    ...row,
    Email: String(row.Email).trim(),
    MailingStreet: street,
    [TAG_PATH]: segmentName || ''
  };
}
