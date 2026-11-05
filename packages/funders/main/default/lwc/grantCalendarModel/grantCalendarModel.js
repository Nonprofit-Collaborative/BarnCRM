/**
 * The Grant Calendar tab's arithmetic, with no framework in it (F-08, ADR-0162
 * `0162-funders-restricted-funds-schedules-calendar.md` decision 8, plan Section 9.9): which days a
 * month view shows, and the dated rows laid into its weeks. The rows are sorted and marked overdue
 * by the Grant Pipeline's own `deadlineRows`, so the two views agree.
 *
 * Plain JavaScript in and out. Dates are ISO date strings ("2026-11-02"); months run 1 to 12;
 * `firstDay` is the first day of the week, 0 for Sunday to 6 for Saturday.
 */
import { deadlineRows } from 'c/grantPipelineModel';

const pad = (value) => String(value).padStart(2, '0');

/** A UTC date as an ISO date string. */
function iso(date) {
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

function utc(year, month, day) {
  return new Date(Date.UTC(year, month - 1, day));
}

/**
 * The month before or after.
 *
 * @param {number} year the year
 * @param {number} month 1 to 12
 * @param {number} delta months to move, negative for back
 * @returns {{year: number, month: number}}
 */
export function shiftMonth(year, month, delta) {
  const date = utc(year, month + delta, 1);
  return { year: date.getUTCFullYear(), month: date.getUTCMonth() + 1 };
}

/**
 * The first and last day a month view shows: whole weeks from the week holding the 1st to the
 * week holding the last day, so four to six weeks.
 *
 * @returns {{from: string, to: string}}
 */
export function monthRange(year, month, firstDay = 0) {
  const first = utc(year, month, 1);
  const last = utc(year, month + 1, 0);
  const start = new Date(first);
  start.setUTCDate(first.getUTCDate() - ((first.getUTCDay() - firstDay + 7) % 7));
  const end = new Date(last);
  end.setUTCDate(last.getUTCDate() + ((firstDay + 6 - last.getUTCDay() + 7) % 7));
  return { from: iso(start), to: iso(end) };
}

/**
 * A month view: its weeks, each of seven days, each day with its rows.
 *
 * @param {number} year the year
 * @param {number} month 1 to 12
 * @param {object[]} rows dated rows with `deadline` (ISO), `name` and `kind`
 * @param {string} today today's ISO date
 * @param {number} firstDay first day of the week, 0 for Sunday
 * @returns {object[]} `{key, days: [{key, date, day, inMonth, isToday, items}]}`; rows outside
 *   the view are left out, and each day's rows are sorted by name with `overdue` set
 */
export function monthWeeks(year, month, rows, today, firstDay = 0) {
  const { from, to } = monthRange(year, month, firstDay);
  const byDate = new Map();
  deadlineRows(rows, today).forEach((row) => {
    if (row.deadline >= from && row.deadline <= to) {
      if (!byDate.has(row.deadline)) {
        byDate.set(row.deadline, []);
      }
      byDate.get(row.deadline).push(row);
    }
  });
  const weeks = [];
  const cursor = new Date(`${from}T00:00:00Z`);
  while (iso(cursor) <= to) {
    const days = [];
    for (let i = 0; i < 7; i += 1) {
      const date = iso(cursor);
      days.push({
        key: date,
        date,
        day: cursor.getUTCDate(),
        inMonth: cursor.getUTCMonth() + 1 === month,
        isToday: date === today,
        items: byDate.get(date) || []
      });
      cursor.setUTCDate(cursor.getUTCDate() + 1);
    }
    weeks.push({ key: days[0].date, days });
  }
  return weeks;
}

/**
 * The days of the week in view order, by index (0 for Sunday), for the column headings.
 *
 * @param {number} firstDay first day of the week, 0 for Sunday
 * @returns {number[]}
 */
export function weekdayOrder(firstDay = 0) {
  return [0, 1, 2, 3, 4, 5, 6].map((offset) => (firstDay + offset) % 7);
}
