/**
 * Volunteer section rules for Event Management (EV-08), framework free so they port to BarnCRM
 * for WordPress (plan 9.9). No Salesforce imports.
 *
 * A job is `{ id, name, shifts }` and a shift `{ id, startTime, endTime, needed, filled }`, with
 * ISO dates, as Core's event volunteer seam reports them.
 */

const HOUR_MS = 60 * 60 * 1000;

/** A new shift's starting values: the event's first hour (or none), two volunteers. */
export function shiftDefaults(eventStart, eventEnd) {
  const start = eventStart ? new Date(eventStart) : null;
  if (!start || Number.isNaN(start.getTime())) {
    return { startTime: '', endTime: '', needed: 2 };
  }
  let end = new Date(start.getTime() + HOUR_MS);
  const limit = eventEnd ? new Date(eventEnd) : null;
  if (limit && end > limit) {
    end = limit;
  }
  return { startTime: start.toISOString(), endTime: end.toISOString(), needed: 2 };
}

/**
 * What is wrong with a shift before it is sent: 'times' (missing, or the end is not after the
 * start), 'needed' (not a whole number of at least one) or 'outside' (not inside the event), or
 * null when it is fine.
 */
export function shiftProblem({ startTime, endTime, needed }, eventStart, eventEnd) {
  const start = startTime ? new Date(startTime) : null;
  const end = endTime ? new Date(endTime) : null;
  if (
    !start ||
    !end ||
    Number.isNaN(start.getTime()) ||
    Number.isNaN(end.getTime()) ||
    end <= start
  ) {
    return 'times';
  }
  const count = Number(needed);
  if (!Number.isInteger(count) || count < 1) {
    return 'needed';
  }
  if ((eventStart && start < new Date(eventStart)) || (eventEnd && end > new Date(eventEnd))) {
    return 'outside';
  }
  return null;
}

/** 'full', 'partial' or 'empty' for how many of the volunteers a shift wants have signed up. */
export function fillState(filled, needed) {
  const have = filled || 0;
  if (needed && have >= needed) {
    return 'full';
  }
  return have > 0 ? 'partial' : 'empty';
}

/** The badge word for a fill state. */
export function fillWord(state) {
  return { full: 'active', partial: 'pending', empty: 'warning' }[state] || 'neutral';
}

/** Totals over the jobs: how many jobs and shifts, and volunteers wanted and signed up. */
export function totals(jobs) {
  const sum = { jobs: 0, shifts: 0, needed: 0, filled: 0 };
  for (const job of jobs || []) {
    sum.jobs += 1;
    for (const shift of job.shifts || []) {
      sum.shifts += 1;
      sum.needed += shift.needed || 0;
      sum.filled += Math.min(shift.filled || 0, shift.needed || shift.filled || 0);
    }
  }
  return sum;
}
