/**
 * Access Explorer's row formatting (C-53), framework free: no lightning or @salesforce imports,
 * so it runs in any browser (plan Section 9.9). The words it writes come in from the caller.
 */

/**
 * A row with each permission as the "yes" word or blank, and its kind as words, as the table
 * and the CSV show it. A field nobody can be kept from reads the "always" word for Read.
 * @param {object} row a server row (Grant or Row shape)
 * @param {{yes: string, always: string, kinds: object}} words the words to write
 * @returns {object} the row with key, kindLabel and the *Text columns added
 */
export function withFlags(row, words) {
  const yes = (value) => (value ? words.yes : '');
  return {
    ...row,
    key: row.id || row.name,
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
