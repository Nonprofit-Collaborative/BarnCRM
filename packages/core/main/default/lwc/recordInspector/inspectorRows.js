/**
 * The Record Inspector's browser-side logic (C-55), kept free of framework imports so that any
 * front end can reuse it (plan Section 9.9): the Apex controller decides which fields a person
 * may read and returns plain rows; this only searches them.
 */

/** Lower-cases and trims what a person typed. */
export function normalize(term) {
  return (term || '').toString().trim().toLowerCase();
}

/**
 * The rows whose label, API name, type or value contains the term, ignoring case. An empty term
 * keeps every row. Order is kept.
 */
export function filterRows(rows, term) {
  const needle = normalize(term);
  const all = rows || [];
  if (!needle) {
    return all;
  }
  return all.filter((row) =>
    [row.label, row.apiName, row.type, row.value].some(
      (text) => text != null && String(text).toLowerCase().includes(needle)
    )
  );
}

/** A 15 or 18 character record ID with at least one digit, as every key prefix has. */
const ID = /^(?=[a-zA-Z0-9]*\d)(?:[a-zA-Z0-9]{18}|[a-zA-Z0-9]{15})$/;

/**
 * The record ID in what a person pasted: an ID on its own, or a link to a record page in either
 * Lightning (`/lightning/r/Contact/<id>/view`) or Salesforce Classic (`/<id>`), or a link to
 * this page that names one (`?c__recordId=<id>`). Undefined when there is none.
 */
export function parseRecordId(text) {
  const value = (text || '').toString().trim();
  if (ID.test(value)) {
    return value;
  }
  const [path, query = ''] = value.split('#')[0].split('?');
  const segments = path.split('/').reverse();
  const values = query.split('&').map((pair) => pair.split('=')[1]);
  return [...segments, ...values].find((part) => part && ID.test(part));
}
