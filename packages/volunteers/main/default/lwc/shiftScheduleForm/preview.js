/**
 * The shift schedule form's preview (modules-24), with no framework imports so it runs in any
 * browser (plan 9.9): how many shift days a pattern has from today to the horizon, by the same
 * rule the server uses (canonical model R-SSC1 and R-SSC2). Dates are ISO strings read and
 * written in UTC, so no time zone moves a day.
 */
import { utcIsoDate } from 'c/barnFormat';

const DAY_MS = 24 * 60 * 60 * 1000;
/** The multi-select's values, Monday first, as R-SSC1 counts them. */
const DAY_NAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

function parse(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value || ''));
  return match ? Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) : null;
}

/** 0 for Monday to 6 for Sunday. */
function weekdayIndex(time) {
  return (new Date(time).getUTCDay() + 6) % 7;
}

function mondayOf(time) {
  return time - weekdayIndex(time) * DAY_MS;
}

/** The chosen weekday indexes, from the multi-select's value ("Monday;Friday") or a list. */
function chosenDays(weekdays) {
  const names = Array.isArray(weekdays) ? weekdays : String(weekdays || '').split(';');
  return new Set(names.map((name) => DAY_NAMES.indexOf(String(name).trim())).filter((i) => i >= 0));
}

/** "HH:mm" from a time value ("16:00:00.000Z" or "16:00"), or null. */
function hoursAndMinutes(value) {
  const match = /^(\d{2}):(\d{2})/.exec(String(value || ''));
  return match ? `${match[1]}:${match[2]}` : null;
}

/**
 * How many shifts the pattern creates from `today` through the horizon (`horizonWeeks` ahead)
 * or the end date, whichever is first. As Create Shifts Now, a shift today whose start time is
 * before `nowTime` (the org's local "HH:mm") is not counted: it has already started.
 *
 * @returns {{count: number, through: string|null, problem: string|null}} problem is 'weekdays'
 *   when no day is chosen, 'dates' when the start date is missing or the end is before it.
 */
export function shiftPreview(pattern, today, horizonWeeks, nowTime) {
  const start = parse(pattern.startDate);
  const end = parse(pattern.endDate);
  const now = parse(today);
  const startTime = hoursAndMinutes(pattern.startTime);
  const clock = hoursAndMinutes(nowTime);
  const todayStarted = startTime !== null && clock !== null && startTime < clock;
  const chosen = chosenDays(pattern.weekdays);
  if (chosen.size === 0) {
    return { count: 0, through: null, problem: 'weekdays' };
  }
  if (start === null || now === null || (end !== null && end < start)) {
    return { count: 0, through: null, problem: 'dates' };
  }
  const every = Math.max(1, Math.floor(Number(pattern.everyNWeeks) || 1));
  const horizon = now + Number(horizonWeeks || 0) * 7 * DAY_MS;
  const through = end !== null && end < horizon ? end : horizon;
  const firstMonday = mondayOf(start);
  let count = 0;
  for (let time = Math.max(start, now); time <= through; time += DAY_MS) {
    const weeks = Math.round((mondayOf(time) - firstMonday) / (7 * DAY_MS));
    const started = time === now && todayStarted;
    if (chosen.has(weekdayIndex(time)) && weeks % every === 0 && !started) {
      count++;
    }
  }
  return { count, through: utcIsoDate(through), problem: null };
}
