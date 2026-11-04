/**
 * The New Commitment screen's logic, free of any framework import so it ports to BarnCRM for
 * WordPress (plan 9.9). The server builds and checks the commitment; this only decides when to
 * ask it for a preview and reads the figures back out.
 */

export const PLEDGE = 'Pledge';
export const RECURRING = 'Recurring';
export const PERSON = 'person';
export const ORGANIZATION = 'organization';

const ID_PATTERN = /^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/;

function decodeBase64(text) {
  if (typeof atob === 'function') {
    return atob(text);
  }
  return '';
}

/**
 * The record a New page was opened from, read from its page state: a `c__recordId`, or the
 * `inContextOfRef` the platform adds when New is chosen in a related list ("1." then base64
 * JSON of the parent page reference). Undefined when there is none or it cannot be read.
 */
export function contextIdFrom(state) {
  if (!state) {
    return undefined;
  }
  if (state.c__recordId && ID_PATTERN.test(state.c__recordId)) {
    return state.c__recordId;
  }
  const ref = state.inContextOfRef;
  if (typeof ref !== 'string' || !ref) {
    return undefined;
  }
  try {
    const encoded = ref.startsWith('1.') ? ref.substring(2) : ref;
    const parent = JSON.parse(decodeBase64(encoded));
    const recordId = parent && parent.attributes && parent.attributes.recordId;
    return recordId && ID_PATTERN.test(recordId) ? recordId : undefined;
  } catch (unreadable) {
    return undefined;
  }
}

function positive(value) {
  const number = Number(value);
  return value !== null && value !== undefined && value !== '' && number > 0;
}

/**
 * True once the entries hold enough for the server to work out a schedule: a pledge needs a
 * total, how often, a first payment date and either the number of payments or the last
 * payment date; a recurring gift needs the amount each time, how often and a start date.
 */
export function isPreviewReady(entry) {
  if (!entry || !entry.frequency || !entry.startDate) {
    return false;
  }
  if (entry.kind === RECURRING) {
    return positive(entry.amount);
  }
  return positive(entry.total) && (positive(entry.payments) || Boolean(entry.lastPaymentDate));
}

/**
 * The input the server takes, from the screen's entries: only the fields of the chosen kind,
 * and the donor in the field its kind and the org's shape call for.
 */
export function toInput(entry, hasPersonAccounts) {
  const isRecurring = entry.kind === RECURRING;
  const donorIsContact = entry.donorKind === PERSON && !hasPersonAccounts;
  const payments = positive(entry.payments) ? Math.floor(Number(entry.payments)) : null;
  return {
    kind: isRecurring ? RECURRING : PLEDGE,
    donorContactId: donorIsContact ? entry.donorId || null : null,
    donorAccountId: donorIsContact ? null : entry.donorId || null,
    total: isRecurring || !positive(entry.total) ? null : Number(entry.total),
    payments: isRecurring ? null : payments,
    lastPaymentDate: isRecurring || payments ? null : entry.lastPaymentDate || null,
    amount: isRecurring && positive(entry.amount) ? Number(entry.amount) : null,
    frequency: entry.frequency || null,
    startDate: entry.startDate || null,
    fundId: entry.fundId || null,
    appealId: entry.appealId || null
  };
}

/**
 * The figures a preview sentence needs: how many payments, the usual amount, and the last
 * payment's amount and date. Null when the preview has no payments.
 */
export function previewFigures(preview) {
  const rows = preview && Array.isArray(preview.installments) ? preview.installments : [];
  if (!rows.length) {
    return null;
  }
  const first = rows[0];
  const last = rows[rows.length - 1];
  return {
    count: rows.length,
    each: first.expectedAmount,
    firstDate: first.dueDate,
    lastAmount: last.expectedAmount,
    lastDate: last.dueDate
  };
}
