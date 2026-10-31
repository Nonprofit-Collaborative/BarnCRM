/**
 * The sheets of a file, read and combined for one load (C-49a). Each sheet is
 * `{ name, headers, records }` as `toRecords` gives it; a text file is one sheet with no name.
 * Pure functions, so the wizard only wires them to the screen.
 */

/** How many example values each column shows, and how long each may be. */
export const EXAMPLE_COUNT = 3;
export const EXAMPLE_LENGTH = 40;

/** The sheets chosen when a file is read: every sheet with rows, or the one sheet there is. */
export function defaultSheets(sheets) {
  const filled = sheets.filter((sheet) => sheet.records.length > 0);
  return (filled.length > 0 ? filled : sheets.slice(0, 1)).map((sheet) => sheet.name);
}

/** The headings of the sheets, each once, in the order they first appear. */
export function distinctHeaders(sheets) {
  return [...new Set(sheets.flatMap((sheet) => sheet.headers))];
}

/**
 * The chosen sheets as one set of columns and rows. A heading mapped to the same field as an
 * earlier sheet's heading joins that column ("First Name" on one sheet, "Contact.First Name"
 * on the next); any other heading is its own column, and the same heading on two sheets is one
 * column. A sheet without a column leaves it blank in its rows.
 *
 * Each column also gets its first few values as examples, from the sheets that have it, a
 * blank cell shown as `blank`, a long value cut short.
 *
 * @param {object[]} sheets the chosen sheets, in order
 * @param {object[]} [targetsBySheet] for each sheet, its headings' suggested targets by
 *   heading (not mapped: missing or the ignore value); left out, nothing is joined
 * @param {string} [ignore] the target that means Do not load
 * @param {string} [blank] the text for a blank example
 */
export function combineSheets(sheets, targetsBySheet = [], ignore = '', blank = '') {
  const columnOf = new Map();
  const columnByTarget = new Map();
  const headers = [];
  sheets.forEach((sheet, index) => {
    const targets = targetsBySheet[index] || {};
    sheet.headers.forEach((heading) => {
      if (columnOf.has(heading)) {
        return;
      }
      const target = targets[heading];
      const mapped = Boolean(target) && target !== ignore;
      if (mapped && columnByTarget.has(target)) {
        columnOf.set(heading, columnByTarget.get(target));
        return;
      }
      columnOf.set(heading, heading);
      headers.push(heading);
      if (mapped) {
        columnByTarget.set(target, heading);
      }
    });
  });

  const examples = Object.fromEntries(headers.map((heading) => [heading, []]));
  const records = [];
  sheets.forEach((sheet) => {
    sheet.records.forEach((source) => {
      const record = Object.fromEntries(headers.map((heading) => [heading, '']));
      const seen = new Set();
      sheet.headers.forEach((heading) => {
        const column = columnOf.get(heading);
        const value = source[heading] === undefined ? '' : source[heading];
        if (!seen.has(column)) {
          seen.add(column);
          record[column] = value;
          if (examples[column].length < EXAMPLE_COUNT) {
            examples[column].push(exampleText(value, blank));
          }
        } else if (record[column] === '') {
          record[column] = value;
        }
      });
      records.push(record);
    });
  });
  return { headers, records, examples };
}

/** A value as an example: `blank` for an empty one, cut to EXAMPLE_LENGTH characters. */
export function exampleText(value, blank = '') {
  const text = String(value === undefined || value === null ? '' : value);
  if (text.length === 0) {
    return blank;
  }
  return text.length > EXAMPLE_LENGTH ? `${text.slice(0, EXAMPLE_LENGTH - 1)}…` : text;
}

/**
 * The chosen sheets that point at an object, when they do not all point at the one loaded:
 * empty when one sheet is chosen, when no chosen sheet names an object, or when every named
 * object is the one loaded (or, with none loaded yet, the same one).
 *
 * @param {string[]} chosen the chosen sheet names
 * @param {object[]} sheetObjects `{ sheetName, objectName, objectLabel }` for each sheet
 * @param {string} [loadedObject] the API name of the object the template loads
 */
export function sheetConflicts(chosen, sheetObjects, loadedObject) {
  if (chosen.length < 2) {
    return [];
  }
  const named = (sheetObjects || []).filter(
    (sheet) => chosen.includes(sheet.sheetName) && sheet.objectName
  );
  const objects = new Set(named.map((sheet) => sheet.objectName.toLowerCase()));
  if (loadedObject) {
    objects.add(loadedObject.toLowerCase());
  }
  return objects.size > 1 ? named : [];
}
