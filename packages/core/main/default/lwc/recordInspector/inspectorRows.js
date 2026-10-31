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
