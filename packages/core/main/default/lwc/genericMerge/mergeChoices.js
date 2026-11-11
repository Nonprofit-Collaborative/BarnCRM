/**
 * Framework-free logic of Merge Records (C-62): which value each field keeps and what the
 * merge sends to the server. No Salesforce imports, so it ports as is (plan 9.9).
 */

/** The starting choice per field: the merge rules' (takeSecond), else the first record's. */
export function initialChoices(fields) {
  const choices = {};
  (fields || []).forEach((field) => {
    choices[field.name] = field.takeSecond ? 'second' : 'first';
  });
  return choices;
}

/**
 * The fields whose value comes from the record merged away: chosen from the side not kept,
 * and different from the kept record's value.
 */
export function fromOther(fields, choices, keep) {
  return (fields || [])
    .filter((field) => field.differs && choices[field.name] && choices[field.name] !== keep)
    .map((field) => field.name);
}

/** The rows to show, each with which side is chosen, optionally only those that differ. */
export function visibleRows(fields, choices, onlyDifferences) {
  return (fields || [])
    .filter((field) => !onlyDifferences || field.differs)
    .map((field) => ({
      ...field,
      firstChosen: choices[field.name] === 'first',
      secondChosen: choices[field.name] === 'second'
    }));
}
