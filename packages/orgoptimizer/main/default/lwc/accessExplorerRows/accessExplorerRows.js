/**
 * Access Explorer's row formatting (C-53), framework free: no lightning or @salesforce imports,
 * so it runs in any browser (plan Section 9.9). The words it writes come in from the caller.
 */

/**
 * A row with each permission as the "yes" word or blank, and its kind as words, as the table
 * and the CSV show it. A field nobody can be kept from reads the "always" word for Read.
 * A BarnCRM role or extra permission is named as the Access page names it (barnName).
 * @param {object} row a server row (Grant or Row shape)
 * @param {{yes: string, always: string, kinds: object, barnNames: object}} words the words to write
 * @returns {object} the row with key, kindLabel and the *Text columns added
 */
export function withFlags(row, words) {
  const yes = (value) => (value ? words.yes : '');
  return {
    ...row,
    key: row.id || row.name,
    label: barnName(row.label, row.barnKind, words.barnNames),
    kindLabel: words.kinds[row.kind] || '',
    readText: row.always ? words.always : yes(row.read),
    createText: yes(row.create),
    editText: yes(row.edit),
    delText: yes(row.del),
    viewAllText: yes(row.viewAll),
    modifyAllText: yes(row.modifyAll)
  };
}

/**
 * A name with its details in brackets, details left out when blank: "Pat (Standard User)".
 * @param {string} name the name
 * @param {string[]} details the details, blanks allowed
 * @returns {string} the text
 */
export function withDetails(name, details) {
  const shown = details.filter(Boolean);
  return shown.length ? `${name} (${shown.join(', ')})` : name;
}

/**
 * A role or extra permission's name in the Access page's words (admin-9): "Team Member (BarnCRM
 * role)". Any other name is returned as it is.
 * @param {string} name the label
 * @param {string} barnKind 'role', 'extraPermission' or blank (from the server)
 * @param {object} patterns the pattern per kind, with {0} for the name
 * @returns {string} the name to show
 */
export function barnName(name, barnKind, patterns) {
  const pattern = barnKind && patterns ? patterns[barnKind] : undefined;
  return pattern ? pattern.replace('{0}', name) : name;
}

/**
 * The columns to show: every column, or, while technical names are hidden (admin-24), all but
 * those marked technical. The mark itself is left off what the table gets.
 * @param {object[]} columns the columns, an API name column marked { technical: true }
 * @param {boolean} showTechnical whether API names are shown
 * @returns {object[]} the columns for the table
 */
export function shownColumns(columns, showTechnical) {
  return columns
    .filter((column) => showTechnical || !column.technical)
    .map(({ technical, ...column }) => column); // eslint-disable-line no-unused-vars
}

/**
 * Picker options for kinds of record or fields: the label with the API name in brackets when
 * technical names are shown; otherwise the label alone, unless two share it.
 * @param {{label: string, value: string}[]} options the options, label and API name
 * @param {boolean} showTechnical whether API names are shown
 * @returns {{label: string, value: string}[]} the options to offer
 */
export function nameOptions(options, showTechnical) {
  const counts = new Map();
  for (const option of options) {
    counts.set(option.label, (counts.get(option.label) || 0) + 1);
  }
  return options.map((option) => ({
    ...option,
    label:
      option.value && (showTechnical || counts.get(option.label) > 1)
        ? `${option.label} (${option.value})`
        : option.label
  }));
}
