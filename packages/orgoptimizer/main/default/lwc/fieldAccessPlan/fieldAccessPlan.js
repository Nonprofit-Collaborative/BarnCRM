/**
 * The Field Access Manager's change logic (C-65, ADR-0156, canonical model R-FA3), framework
 * free: no lightning or @salesforce imports, so a WordPress block or Node can reuse it (plan
 * Section 9.9). It builds the change document the server checks and previews, and turns the
 * server's rows into text. It decides nothing the server does not check again: the server works
 * out every row, its dependencies and the count. The words it writes come in from the caller.
 */

export const READ = 'read';
export const EDIT = 'edit';
export const NONE = 'none';
export const DOCUMENT_VERSION = 1;

const keyOf = (objectName, fieldName) => `${objectName}.${fieldName || ''}`;

/**
 * Adds or replaces the asked access for one kind of record, or for some of its fields.
 * A field that can only be read is asked Read when Read and Edit was chosen.
 * @param {object[]} items the current change list
 * @param {{name: string, label: string}} object the kind of record
 * @param {{name: string, label: string, readOnly: boolean}[]} fields the fields, or an empty
 *   list for the kind of record itself
 * @param {string} access READ, EDIT or NONE
 * @returns {object[]} a new list: key, object, objectLabel, field, fieldLabel, access
 */
export function withItems(items, object, fields, access) {
  const added = (fields.length ? fields : [null]).map((field) => ({
    key: keyOf(object.name, field && field.name),
    object: object.name,
    objectLabel: object.label,
    field: field ? field.name : null,
    fieldLabel: field ? field.label : null,
    access: field && field.readOnly && access === EDIT ? READ : access
  }));
  const replaced = new Set(added.map((item) => item.key));
  return [...items.filter((item) => !replaced.has(item.key)), ...added];
}

/** The list without one item. */
export function withoutItem(items, key) {
  return items.filter((item) => item.key !== key);
}

/**
 * The labels of the kinds of record set to No Access while some of their fields are given
 * access: the server refuses such a change, so the page says so before asking.
 */
export function conflicts(items) {
  const removed = new Map(
    items
      .filter((item) => !item.field && item.access === NONE)
      .map((item) => [item.object, item.objectLabel])
  );
  const labels = new Set(
    items
      .filter((item) => item.field && item.access !== NONE && removed.has(item.object))
      .map((item) => removed.get(item.object))
  );
  return [...labels];
}

/**
 * The change document (R-FA3).
 * @param {string[]} setIds the chosen permission sets
 * @param {object[]} items the change list
 */
export function buildChange(setIds, items) {
  return {
    version: DOCUMENT_VERSION,
    setIds: [...setIds],
    items: items.map((item) => ({
      object: item.object,
      field: item.field ? `${item.object}.${item.field}` : null,
      access: item.access
    }))
  };
}

/** The word for an access level, from Read and Edit flags. */
export function accessWord(read, edit, words) {
  if (read && edit) {
    return words.edit;
  }
  return read ? words.read : words.none;
}

/** The word for an asked access value (READ, EDIT or NONE). */
export function askedWord(access, words) {
  return accessWord(access !== NONE, access === EDIT, words);
}

/**
 * The server's preview rows with their words.
 * @param {object[]} rows PreviewRow shapes from the server
 * @param {{read: string, edit: string, none: string, wholeRecord: string, reasons: object}} words
 */
export function previewRows(rows, words) {
  return rows.map((row, index) => ({
    ...row,
    key: `${row.setId}.${row.objectName}.${row.fieldName || ''}.${index}`,
    fieldText: row.fieldLabel || row.fieldName || words.wholeRecord,
    nowText: accessWord(row.nowRead, row.nowEdit, words),
    afterText: accessWord(row.afterRead, row.afterEdit, words),
    whyText: words.reasons[row.reason] || row.reason
  }));
}

/** Fields whose label or API name contains the term, ignoring case. */
export function filterFields(fields, term) {
  const wanted = (term || '').trim().toLowerCase();
  if (!wanted) {
    return fields;
  }
  return fields.filter(
    (field) =>
      field.label.toLowerCase().includes(wanted) || field.name.toLowerCase().includes(wanted)
  );
}
