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

  return { headers, ...rowsOf(sheets, headers, () => columnOf, blank) };
}

/**
 * The rows of the sheets under the joined columns, with each column's first values as examples.
 * `columnsOf(index)` gives a sheet's column for each of its headings.
 */
function rowsOf(sheets, headers, columnsOf, blank) {
  const examples = Object.fromEntries(headers.map((heading) => [heading, []]));
  const records = [];
  sheets.forEach((sheet, index) => {
    const columnOf = columnsOf(index);
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
  return { records, examples };
}

/**
 * The chosen sheets of an upload of several objects (R-IT20) as one set of columns and rows,
 * each sheet loading its own object. A heading mapped to the same target as an earlier sheet's
 * heading joins that column, as in `combineSheets`; the same heading on sheets of different
 * objects is two columns, the later one named with its sheet, `Name (Contacts)`, so each keeps
 * its own field.
 *
 * @param {object[]} sheets the chosen sheets, in the order they load
 * @param {object[]} targetsBySheet for each sheet, its headings' suggested targets by heading
 * @param {string[]} objectBySheet for each sheet, the API name of the object it loads
 * @param {string} [ignore] the target that means Do not load
 * @param {string} [blank] the text for a blank example
 * @returns {object} `{ headers, records, examples, targets }`, targets being each column's
 *   suggested target
 */
export function combineObjectSheets(
  sheets,
  targetsBySheet = [],
  objectBySheet = [],
  ignore = '',
  blank = ''
) {
  const headers = [];
  const targets = {};
  const objectOfColumn = new Map();
  const columnByTarget = new Map();
  const columnsBySheet = sheets.map((sheet, index) => {
    const own = targetsBySheet[index] || {};
    const object = objectBySheet[index] || '';
    const columnOf = new Map();
    sheet.headers.forEach((heading) => {
      if (columnOf.has(heading)) {
        return;
      }
      const target = own[heading];
      const mapped = Boolean(target) && target !== ignore;
      if (mapped && columnByTarget.has(target)) {
        columnOf.set(heading, columnByTarget.get(target));
        return;
      }
      const taken = objectOfColumn.has(heading) && objectOfColumn.get(heading) !== object;
      const column = taken ? `${heading} (${sheet.name})` : heading;
      if (!objectOfColumn.has(column)) {
        objectOfColumn.set(column, object);
        headers.push(column);
        targets[column] = mapped ? target : ignore;
      }
      columnOf.set(heading, column);
      if (mapped && !columnByTarget.has(target)) {
        columnByTarget.set(target, column);
      }
    });
    return columnOf;
  });
  return {
    headers,
    targets,
    ...rowsOf(sheets, headers, (index) => columnsBySheet[index], blank)
  };
}

/**
 * The chosen sheets in the order their objects load (R-IT20), parents first, keeping the
 * file's order among sheets of one object. A sheet whose object is not listed goes last.
 *
 * @param {object[]} sheets the chosen sheets
 * @param {object} objectOfSheet each sheet's object API name, by sheet name
 * @param {string[]} loadOrder the objects' API names in load order
 */
export function sheetsInLoadOrder(sheets, objectOfSheet, loadOrder) {
  const rank = (sheet) => {
    const found = loadOrder.indexOf(objectOfSheet[sheet.name]);
    return found < 0 ? loadOrder.length : found;
  };
  return sheets
    .map((sheet, index) => ({ sheet, index }))
    .sort((a, b) => rank(a.sheet) - rank(b.sheet) || a.index - b.index)
    .map((each) => each.sheet);
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
