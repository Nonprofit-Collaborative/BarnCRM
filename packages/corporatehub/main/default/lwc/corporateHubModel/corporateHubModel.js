/**
 * Framework-free logic for the Corporate Hub page and panels (ADR-NEXT
 * `NEXT-corporate-hub-module.md` decision 11; plan Section 9.9): how far off a date is and the
 * help key that says so, and the outcomes a completed cycle can have. No Salesforce imports, so
 * a browser page outside Salesforce can use it as it is.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

/** The outcomes of a Compliance Cycle (canonical model 29CH4), in the order they are offered. */
export const OUTCOMES = ['Done', 'Done Late', 'Not Required'];

/** A yyyy-mm-dd string as a UTC day number, or null. */
function dayNumber(value) {
  if (!value || typeof value !== 'string') {
    return null;
  }
  const parts = value.substring(0, 10).split('-').map(Number);
  if (parts.length !== 3 || parts.some((part) => Number.isNaN(part))) {
    return null;
  }
  return Math.round(Date.UTC(parts[0], parts[1] - 1, parts[2]) / DAY_MS);
}

/** Today as yyyy-mm-dd in the person's own day, not UTC's. */
export function todayIso(now = new Date()) {
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${now.getFullYear()}-${month}-${day}`;
}

/** Days from today to the date: negative when it has passed, null when there is no date. */
export function daysUntil(dateIso, today) {
  const target = dayNumber(dateIso);
  const from = dayNumber(today);
  return target === null || from === null ? null : target - from;
}

export const DUE_NONE = 'none';
export const DUE_OVERDUE = 'overdue';
export const DUE_TODAY = 'today';
export const DUE_LATER = 'later';

/**
 * When something is due, as a state and a number of days (days late when overdue). The page
 * turns the state into words.
 */
export function dueState(dateIso, today) {
  const days = daysUntil(dateIso, today);
  if (days === null) {
    return { state: DUE_NONE, count: 0 };
  }
  if (days < 0) {
    return { state: DUE_OVERDUE, count: -days };
  }
  return { state: days === 0 ? DUE_TODAY : DUE_LATER, count: days };
}

/** A public group's developer name as typed, or '' for everyone with a BarnCRM role. */
export function groupName(value) {
  return String(value || '')
    .trim()
    .replace(/\s+/g, '_');
}
