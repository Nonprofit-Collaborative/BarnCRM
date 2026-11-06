/**
 * The Schedule Sessions panel's logic (P-11, R-SE4), with no framework imports so it runs in any
 * browser (plan 9.9): the dates of a weekly pattern between two days, the weekday choices and the
 * panel's sentences. Dates are ISO strings ("2027-03-01") read and written in UTC, so no time
 * zone moves a day.
 */

/** The most sessions created in one action; the server checks it again. */
export const MAX_SESSIONS = 200;

/** Weekday values as JavaScript numbers them: 0 is Sunday. */
export const WEEKDAY_VALUES = ['1', '2', '3', '4', '5', '6', '0'];

const DAY_MS = 24 * 60 * 60 * 1000;
// 7 January 2024 was a Sunday; the week from it names each weekday.
const A_SUNDAY = Date.UTC(2024, 0, 7);

/** "{0} of {1}" with the values put in. */
export function format(template, ...values) {
  return String(template || '').replace(/\{(\d+)\}/g, (match, index) => {
    return values[index] === undefined ? match : String(values[index]);
  });
}

/** An ISO date as a UTC timestamp, or null when it is not one. */
export function parseIsoDate(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value || ''));
  if (!match) {
    return null;
  }
  const time = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  return Number.isNaN(time) ? null : time;
}

/** A UTC timestamp as an ISO date. */
export function toIsoDate(time) {
  return new Date(time).toISOString().slice(0, 10);
}

/** The weekday choices, Monday first, named in this locale. */
export function weekdayOptions(locale) {
  let formatter;
  try {
    formatter = new Intl.DateTimeFormat(locale || undefined, { weekday: 'long', timeZone: 'UTC' });
  } catch {
    formatter = new Intl.DateTimeFormat(undefined, { weekday: 'long', timeZone: 'UTC' });
  }
  return WEEKDAY_VALUES.map((value) => ({
    label: formatter.format(new Date(A_SUNDAY + Number(value) * DAY_MS)),
    value
  }));
}

/**
 * The dates from `from` to `to`, both included, that fall on one of `weekdays`. Stops one past
 * `max`, so the caller can tell there are too many without walking years of days.
 *
 * @returns {{dates: string[], tooMany: boolean, problem: string|null}} problem is 'dates' when a
 *   date is missing or the end is before the start, 'weekdays' when none is chosen.
 */
export function sessionDates(from, to, weekdays, max = MAX_SESSIONS) {
  const start = parseIsoDate(from);
  const end = parseIsoDate(to);
  if (start === null || end === null || end < start) {
    return { dates: [], tooMany: false, problem: 'dates' };
  }
  const chosen = new Set((weekdays || []).map(String));
  if (chosen.size === 0) {
    return { dates: [], tooMany: false, problem: 'weekdays' };
  }
  const dates = [];
  for (let time = start; time <= end && dates.length <= max; time += DAY_MS) {
    if (chosen.has(String(new Date(time).getUTCDay()))) {
      dates.push(toIsoDate(time));
    }
  }
  const tooMany = dates.length > max;
  return { dates: tooMany ? dates.slice(0, max) : dates, tooMany, problem: null };
}

/**
 * How many of the planned dates get a new session and how many are skipped because they already
 * have one (`taken`, ISO dates the server listed); the server skips the same days again.
 */
export function newAndSkipped(dates, taken) {
  const busy = new Set(taken || []);
  const skipped = (dates || []).filter((date) => busy.has(date)).length;
  return { toCreate: (dates || []).length - skipped, skipped };
}

/**
 * False only when both times are set and the end is not after the start (R-SE6). Times are
 * "HH:mm" with optional seconds, so they compare as text once both have hours and minutes.
 */
export function timesInOrder(start, end) {
  if (!start || !end) {
    return true;
  }
  return String(end).slice(0, 5) > String(start).slice(0, 5);
}

/** "N sessions scheduled." or "N sessions will be scheduled.", then the skipped days if any. */
export function countMessage(count, skipped, labels) {
  const main = count === 1 ? labels.one : format(labels.many, count);
  return skipped > 0 ? `${main} ${format(labels.skipped, skipped)}` : main;
}

/** The line under the form: how many sessions, or what is missing. */
export function previewMessage(result, labels, taken) {
  if (result.problem === 'dates') {
    return labels.chooseDates;
  }
  if (result.problem === 'weekdays') {
    return labels.chooseWeekdays;
  }
  if (result.tooMany) {
    return format(labels.tooMany, MAX_SESSIONS);
  }
  if (result.dates.length === 0) {
    return labels.none;
  }
  const { toCreate, skipped } = newAndSkipped(result.dates, taken);
  return countMessage(toCreate, skipped, labels);
}
