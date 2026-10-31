/**
 * Access Explorer's comparison logic (C-53b), framework free: no lightning or @salesforce
 * imports, so it runs in any browser (plan Section 9.9). It compares two lists of server rows
 * (the Row shape of AccessExplorerController: name, label, always and one boolean per
 * permission) and writes nothing to the server. The words it writes come in from the caller.
 */

/** The permissions compared per kind of record, in the order the page shows them. */
export const OBJECT_FLAGS = ['read', 'create', 'edit', 'del', 'viewAll', 'modifyAll'];

/** The permissions compared per field. */
export const FIELD_FLAGS = ['read', 'edit'];

/** Replaces {0}, {1}, ... in a template. */
function fill(template, values) {
  return template.replace(/\{(\d+)\}/g, (match, index) => {
    const value = values[Number(index)];
    return value === undefined ? match : value;
  });
}

/** The permissions a row gives; a field nobody can be kept from always gives Read. */
function held(row, flags) {
  if (!row) {
    return [];
  }
  return flags.filter((flag) => row[flag] || (flag === 'read' && row.always));
}

/**
 * Compares two lists of rows by name, one result row per name found on either side.
 * @param {object[]} rowsA the first side's rows
 * @param {object[]} rowsB the second side's rows
 * @param {string[]} flags the permissions to compare (OBJECT_FLAGS or FIELD_FLAGS)
 * @param {{flags: object, onlyIn: string, nameA: string, nameB: string, none: string}} words
 *   the permission words by flag, the "Only {0}: {1}." template, both sides' names, and the
 *   word for no access
 * @returns {object[]} rows with key, name, label, aText, bText, difference and differs, by label
 */
export function diffRows(rowsA, rowsB, flags, words) {
  const byName = new Map();
  for (const row of rowsA) {
    byName.set(row.name, { name: row.name, label: row.label, a: row });
  }
  for (const row of rowsB) {
    const entry = byName.get(row.name) || { name: row.name, label: row.label };
    entry.b = row;
    byName.set(row.name, entry);
  }
  const wordsOf = (list) => list.map((flag) => words.flags[flag]).join(', ');
  const rows = [...byName.values()].map((entry) => {
    const a = held(entry.a, flags);
    const b = held(entry.b, flags);
    const onlyA = a.filter((flag) => !b.includes(flag));
    const onlyB = b.filter((flag) => !a.includes(flag));
    const parts = [];
    if (onlyA.length) {
      parts.push(fill(words.onlyIn, [words.nameA, wordsOf(onlyA)]));
    }
    if (onlyB.length) {
      parts.push(fill(words.onlyIn, [words.nameB, wordsOf(onlyB)]));
    }
    return {
      key: entry.name,
      name: entry.name,
      label: entry.label,
      aText: a.length ? wordsOf(a) : words.none,
      bText: b.length ? wordsOf(b) : words.none,
      difference: parts.join(' '),
      differs: parts.length > 0
    };
  });
  return rows.sort((x, y) => x.label.localeCompare(y.label) || x.name.localeCompare(y.name));
}

/**
 * How alike two sides are: permissions both give, out of permissions either gives, across every
 * name on either side, as a whole percentage (100 when neither gives anything).
 * @param {object[]} rowsA the first side's rows
 * @param {object[]} rowsB the second side's rows
 * @param {string[]} flags the permissions to count
 * @returns {number} 0 to 100
 */
export function similarity(rowsA, rowsB, flags) {
  const grants = (rows) => {
    const set = new Set();
    for (const row of rows) {
      held(row, flags).forEach((flag) => set.add(`${row.name}\u0000${flag}`));
    }
    return set;
  };
  const a = grants(rowsA);
  const b = grants(rowsB);
  const union = new Set([...a, ...b]);
  if (union.size === 0) {
    return 100;
  }
  const shared = [...a].filter((grant) => b.has(grant)).length;
  return Math.round((shared / union.size) * 100);
}

/**
 * The rows to show.
 * @param {object[]} rows diffRows output
 * @param {boolean} differencesOnly true to keep only rows where the sides differ
 * @returns {object[]} the rows
 */
export function visibleRows(rows, differencesOnly) {
  return differencesOnly ? rows.filter((row) => row.differs) : rows;
}

/**
 * How many rows differ.
 * @param {object[]} rows diffRows output
 * @returns {number} the count
 */
export function countDifferences(rows) {
  return rows.filter((row) => row.differs).length;
}
