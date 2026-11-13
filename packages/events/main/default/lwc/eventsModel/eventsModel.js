/**
 * Event Management's shared arithmetic, with no framework in it (EV-01, canonical model 29EV1,
 * plan Section 9.9): the dates of a repeating series (R-EV4), an event's date range in words, and
 * the status badge word for an event's status.
 *
 * Plain JavaScript in and out, so a WordPress block or Node can use the same module. Dates arrive
 * as ISO date-time strings, the shape the server sends, and series dates go back the same way.
 */
import { badgeWord } from 'c/barnFormat';

/** The most occurrences one Repeat Event makes (EventsHomeController.MAX_OCCURRENCES). */
export const MAX_OCCURRENCES = 52;

/** How a series repeats. */
export const FREQUENCIES = Object.freeze(['weekly', 'biweekly', 'monthly']);

const STEP_DAYS = Object.freeze({ weekly: 7, biweekly: 14 });

/** An event status's word in the status vocabulary (c/barnStatus), for its badge. */
const STATUS_WORDS = Object.freeze({
  Draft: 'draft',
  Open: 'active',
  Closed: 'closed',
  Completed: 'completed',
  Cancelled: 'inactive'
});

function lastDayOf(year, month) {
  return new Date(year, month + 1, 0).getDate();
}

function fill(template, a, b) {
  return String(template).replace('{0}', a).replace('{1}', b);
}

/**
 * When each later occurrence of a series starts (R-EV4): every week, every two weeks or every
 * month after `start`, at the same time of day. A monthly occurrence keeps the day of the month,
 * or the month's last day when the month is shorter, and never drifts: the 31st of January gives
 * the 28th or 29th of February, then the 31st of March.
 *
 * @param {string|Date} start when the event starts
 * @param {string} frequency `weekly`, `biweekly` or `monthly`
 * @param {number} count how many occurrences, at most MAX_OCCURRENCES
 * @returns {Date[]} the starts, in order; empty when the input cannot be read
 */
export function seriesStarts(start, frequency, count) {
  const first = new Date(start);
  if (Number.isNaN(first.getTime()) || !FREQUENCIES.includes(frequency)) {
    return [];
  }
  const total = Math.max(0, Math.min(MAX_OCCURRENCES, Math.floor(Number(count) || 0)));
  const starts = [];
  for (let i = 1; i <= total; i++) {
    let next;
    if (frequency === 'monthly') {
      const month = new Date(first.getFullYear(), first.getMonth() + i, 1);
      const day = Math.min(first.getDate(), lastDayOf(month.getFullYear(), month.getMonth()));
      next = new Date(month.getFullYear(), month.getMonth(), day);
    } else {
      next = new Date(
        first.getFullYear(),
        first.getMonth(),
        first.getDate() + STEP_DAYS[frequency] * i
      );
    }
    next.setHours(first.getHours(), first.getMinutes(), first.getSeconds(), 0);
    starts.push(next);
  }
  return starts;
}

/**
 * An event's dates in words: "Sat, Mar 7, 2026, 6:00 PM to 8:00 PM" for one day, and "Sat, Mar
 * 7, 2026 to Mon, Mar 9, 2026" for a multi-day event.
 *
 * @param {string|Date} start when it starts
 * @param {string|Date} end when it ends, or empty
 * @param {{locale?: string, timeZone?: string, range?: string}} options the user's locale and
 *   time zone, and the range template with {0} and {1} (a label)
 * @returns {string} the words, or '' when the start cannot be read
 */
export function whenText(start, end, options = {}) {
  const from = new Date(start);
  if (!start || Number.isNaN(from.getTime())) {
    return '';
  }
  const { locale, timeZone, range = '{0} to {1}' } = options;
  const zone = timeZone ? { timeZone } : {};
  const day = new Intl.DateTimeFormat(locale, {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    ...zone
  });
  const time = new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit', ...zone });
  const to = end ? new Date(end) : null;
  if (!to || Number.isNaN(to.getTime())) {
    return `${day.format(from)}, ${time.format(from)}`;
  }
  if (isMultiDay(from, to, timeZone)) {
    return fill(range, day.format(from), day.format(to));
  }
  return `${day.format(from)}, ${fill(range, time.format(from), time.format(to))}`;
}

/** True when the start and end fall on different calendar days in the time zone. */
export function isMultiDay(start, end, timeZone) {
  const key = new Intl.DateTimeFormat('en-CA', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    ...(timeZone ? { timeZone } : {})
  });
  const from = new Date(start);
  const to = new Date(end);
  if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime())) {
    return false;
  }
  return key.format(from) !== key.format(to);
}

/** The status vocabulary word for an event status; unknown statuses are neutral. */
export function statusWord(status) {
  return badgeWord(STATUS_WORDS, status);
}
