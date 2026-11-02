/**
 * The Cohort Members panel's logic (P-11, R-CO3), with no framework imports so it runs in any
 * browser (plan 9.9): the list of people picked to add, the ticked enrollments, what is sent, and
 * the panel's sentences.
 */

/** "{0} of {1}" with the values put in. */
export function format(template, ...values) {
  return String(template || '').replace(/\{(\d+)\}/g, (match, index) => {
    return values[index] === undefined ? match : String(values[index]);
  });
}

/** The picked people with this one added at the end, once. */
export function withPerson(picked, person) {
  if (!person || !person.id || picked.some((one) => one.id === person.id)) {
    return picked;
  }
  return [...picked, { id: person.id, name: person.name || person.id }];
}

/** The picked people without this one. */
export function withoutPerson(picked, personId) {
  return picked.filter((one) => one.id !== personId);
}

/** The ticked enrollment Ids with this one ticked or not. */
export function withTicked(ticked, enrollmentId, checked) {
  const rest = ticked.filter((id) => id !== enrollmentId);
  return checked ? [...rest, enrollmentId] : rest;
}

/** Every candidate ticked, or none when all already are. */
export function allTicked(candidates, ticked) {
  const ids = (candidates || []).map((one) => one.enrollmentId);
  return ids.length > 0 && ids.every((id) => ticked.includes(id)) ? [] : ids;
}

/** The candidates with whether each is ticked, ready for the template. */
export function candidateRows(candidates, ticked, labels) {
  return (candidates || []).map((one) => ({
    ...one,
    key: one.enrollmentId,
    checked: ticked.includes(one.enrollmentId),
    tickLabel: format(labels.tickFor, one.personName),
    detail: one.stage
  }));
}

/** The members, ready for the template. */
export function memberRows(members, labels) {
  return (members || []).map((one) => ({
    ...one,
    key: one.enrollmentId,
    removeLabel: format(labels.removeFor, one.personName)
  }));
}

/** What the add sends, only the ticked enrollments still offered. */
export function addPayload(candidates, ticked, picked) {
  const offered = new Set((candidates || []).map((one) => one.enrollmentId));
  return {
    enrollmentIds: ticked.filter((id) => offered.has(id)),
    personIds: picked.map((one) => one.id)
  };
}

/** How many people the add would send. */
export function chosenCount(candidates, ticked, picked) {
  const payload = addPayload(candidates, ticked, picked);
  return payload.enrollmentIds.length + payload.personIds.length;
}

/** The sentence after an add. */
export function addedMessage(result, labels) {
  const added = result && result.added ? result.added : 0;
  const failed = result && result.failures ? result.failures.length : 0;
  const addedText = added === 1 ? labels.addedOne : format(labels.addedMany, added);
  return failed > 0 ? `${addedText} ${format(labels.someFailed, failed)}` : addedText;
}
