/**
 * Picklist Value Usage's Last Used logic (C-57, canonical model Section 29F, R-FU12), framework
 * free: no lightning or @salesforce imports, so it runs in any browser (plan Section 9.9).
 *
 * On a large kind of record the newest date per value is read a chunk of records at a time, each
 * chunk returning plain rows ({ fieldName, value, lastUsed }) for the records it read. These
 * functions split the fields into groups, keep the newest date per value across chunks, measure
 * progress and write the dates onto the table rows. They write nothing to the server.
 */

/** Splits a list into groups of at most size items, in order. */
export function groupsOf(items, size) {
  const list = items || [];
  const step = size > 0 ? size : 1;
  const groups = [];
  for (let start = 0; start < list.length; start += step) {
    groups.push(list.slice(start, start + step));
  }
  return groups;
}

function time(value) {
  const parsed = value ? Date.parse(value) : NaN;
  return Number.isNaN(parsed) ? null : parsed;
}

/**
 * Returns a new { fieldName: { value: lastUsed } } map holding, per field and value, the newer
 * of the date already kept and the dates of one chunk. A value seen with no date is kept as null
 * until a dated record holds it.
 */
export function mergeDates(newest, dates) {
  const merged = {};
  Object.keys(newest || {}).forEach((fieldName) => {
    merged[fieldName] = { ...newest[fieldName] };
  });
  (dates || []).forEach((found) => {
    const values = merged[found.fieldName] || (merged[found.fieldName] = {});
    const value = found.value === null || found.value === undefined ? '' : found.value;
    const candidate = time(found.lastUsed);
    if (!(value in values)) {
      values[value] = candidate === null ? null : found.lastUsed;
      return;
    }
    const kept = time(values[value]);
    if (candidate !== null && (kept === null || candidate > kept)) {
      values[value] = found.lastUsed;
    }
  });
  return merged;
}

/**
 * Returns the rows with Last Used set from the kept dates for the given fields: a value with no
 * kept date gets none, and every value of a field in blankFields gets none. Rows of other fields
 * are returned as they were.
 */
export function applyDates(rows, newest, fieldNames, blankFields) {
  const fields = new Set(fieldNames || []);
  const blank = new Set(blankFields || []);
  return (rows || []).map((row) => {
    if (!fields.has(row.fieldName)) {
      return row;
    }
    const values = (newest || {})[row.fieldName] || {};
    const lastUsed = blank.has(row.fieldName) ? null : values[row.value] || null;
    return { ...row, lastUsed };
  });
}

/**
 * Progress across every group of fields: each group reads the records once, so the whole job is
 * groups times total records. Returns { read, of, percent }, read never above of.
 */
export function scanProgress(group, groups, readInGroup, total) {
  const perGroup = Math.max(total || 0, 0);
  const of = perGroup * Math.max(groups || 0, 0);
  const read = Math.min(
    of,
    perGroup * Math.max(group || 0, 0) + Math.min(readInGroup || 0, perGroup)
  );
  return { read, of, percent: of ? Math.round((read / of) * 100) : 0 };
}
