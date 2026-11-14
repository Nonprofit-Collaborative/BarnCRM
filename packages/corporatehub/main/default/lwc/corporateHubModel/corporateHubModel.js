/**
 * Framework-free logic for the Corporate Hub page and panels (ADR-0196
 * `0196-corporate-hub-module.md` decision 11; plan Section 9.9): how far off a date is and the
 * help key that says so, and the outcomes a completed cycle can have. No Salesforce imports, so
 * a browser page outside Salesforce can use it as it is.
 */
export { percent } from 'c/barnFormat';

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

// ---- Board governance (CH-09 to CH-20; ADR-0199 `0199-corporate-hub-board-governance.md`)

/** Meeting Attendee Attendance values (canonical model 29CH10), in the order offered. */
export const ATTENDANCE = ['Invited', 'Present', 'Absent', 'Excused'];
export const MINUTES_SUBMITTED = 'Submitted for Approval';
export const MINUTES_APPROVED = 'Approved';
export const VOTING_OPEN = 'Voting Open';

/**
 * The skills matrix (CH-15): how many current seats hold each skill the board wants or any seat
 * holds, wanted skills first, and the wanted skills nobody holds.
 *
 * @param {string[]} needed the board's Skills Wanted
 * @param {{values: string[]}[]} seats current seats, each with its skills in `values`
 */
export function skillGaps(needed, seats) {
  const counts = new Map();
  (needed || []).forEach((skill) => counts.set(skill, 0));
  (seats || []).forEach((seat) => {
    (seat.values || []).forEach((skill) => counts.set(skill, (counts.get(skill) || 0) + 1));
  });
  return {
    counts: [...counts.entries()].map(([skill, count]) => ({ skill, count })),
    gaps: (needed || []).filter((skill) => counts.get(skill) === 0)
  };
}

/** Seats whose term ends within `days` of today, overdue included (R-BM2). */
export function expiringSeats(seats, today, days) {
  return (seats || []).filter((seat) => {
    const left = daysUntil(seat.due, today);
    return left !== null && left <= (Number(days) || 0);
  });
}
