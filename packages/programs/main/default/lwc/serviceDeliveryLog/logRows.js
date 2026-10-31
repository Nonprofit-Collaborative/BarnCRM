/**
 * The Service Delivery Log panel's logic, framework free (plan Section 9.9): it merges the plain
 * log the server returns with the unsaved changes on screen, and works out what to save. No
 * Lightning or Salesforce import, so it runs and is tested anywhere.
 */

const PRESENT = 'Present';
const ABSENCES = ['Excused Absence', 'Unexcused Absence'];

/** Replaces {0}, {1} and so on in a label with the values given. */
export function format(template, ...values) {
  return values.reduce(
    (text, value, index) => text.split(`{${index}}`).join(value),
    template || ''
  );
}

/** Whether this attendance is an absence, which delivers nothing (R-SD2). */
export function isAbsence(attendance) {
  return ABSENCES.includes(attendance);
}

/** A person's values as they now stand: their unsaved change, else what is recorded. */
function current(row, drafts) {
  const draft = drafts && drafts[row.key];
  if (draft) {
    return draft;
  }
  return { attendance: row.attendance || '', quantity: row.quantity };
}

/**
 * The rows the panel shows. A person with a recorded delivery is offered the attendance values
 * only; one with none is offered Not Recorded first, so leaving them alone saves nothing.
 */
export function logRows(log, drafts, labels) {
  const attendance = (log && log.attendance ? log.attendance : []).map(({ label, value }) => ({
    label,
    value
  }));
  const notRecorded = [{ label: labels.notRecorded, value: '' }];
  return (log && log.rows ? log.rows : []).map((row) => {
    const now = current(row, drafts);
    const recorded = !!now.attendance;
    return {
      key: row.key,
      personName: row.personName,
      attendance: now.attendance,
      quantity: recorded ? (isAbsence(now.attendance) ? 0 : now.quantity) : null,
      options: row.deliveryId ? attendance : notRecorded.concat(attendance),
      quantityDisabled: !recorded || isAbsence(now.attendance),
      attendanceFor: format(labels.attendanceFor, row.personName),
      quantityFor: format(labels.quantityFor, row.personName),
      changed: !!(drafts && drafts[row.key])
    };
  });
}

/** The change a new attendance makes: an absence counts 0, a first Present counts 1. */
export function withAttendance(log, drafts, key, attendance) {
  const row = (log.rows || []).find((candidate) => candidate.key === key);
  const now = current(row, drafts);
  let quantity = now.quantity;
  if (isAbsence(attendance)) {
    quantity = 0;
  } else if (attendance && (quantity === null || quantity === undefined || quantity === 0)) {
    quantity = 1;
  }
  return { ...drafts, [key]: { attendance, quantity } };
}

/** The change a new quantity makes. */
export function withQuantity(log, drafts, key, quantity) {
  const row = (log.rows || []).find((candidate) => candidate.key === key);
  const now = current(row, drafts);
  const value = quantity === '' || quantity === null ? null : Number(quantity);
  return { ...drafts, [key]: { attendance: now.attendance, quantity: value } };
}

/** Everyone not yet recorded becomes Present with a quantity of 1; the rest are left alone. */
export function markAllPresent(log, drafts) {
  const next = { ...drafts };
  (log && log.rows ? log.rows : []).forEach((row) => {
    if (!current(row, drafts).attendance) {
      next[row.key] = { attendance: PRESENT, quantity: 1 };
    }
  });
  return next;
}

/** The entries to save: each changed person with an attendance, as the server takes them. */
export function entriesToSave(log, drafts) {
  return (log && log.rows ? log.rows : [])
    .filter((row) => drafts && drafts[row.key] && drafts[row.key].attendance)
    .filter((row) => {
      const draft = drafts[row.key];
      return draft.attendance !== row.attendance || Number(draft.quantity) !== Number(row.quantity);
    })
    .map((row) => {
      const draft = drafts[row.key];
      return {
        contactId: row.contactId || null,
        accountId: row.accountId || null,
        enrollmentId: row.enrollmentId || null,
        deliveryId: row.deliveryId || null,
        attendance: draft.attendance,
        quantity: isAbsence(draft.attendance) ? 0 : draft.quantity
      };
    });
}
