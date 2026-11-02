/**
 * The Award Schedule card's arithmetic, with no framework in it (F-05, canonical model 29ZM
 * R-GP2, plan Section 9.9): the amount awarded split evenly over payments a period apart, the first
 * on the award start date and none after the award end date, the last taking the cents left by
 * rounding.
 *
 * Plain JavaScript in and out, so a WordPress block or Node can use the same module. Dates are ISO
 * date strings ("2027-01-01"), the shape the server sends and takes.
 */

/** Months between payments for each frequency; Once is a single payment. */
export const FREQUENCY_MONTHS = Object.freeze({
  Once: 0,
  Annual: 12,
  Semiannual: 6,
  Quarterly: 3,
  Monthly: 1
});

/** The most payments one schedule may hold, as the server allows: monthly for ten years. */
export const MAX_PAYMENTS = 120;

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

const pad = (value) => String(value).padStart(2, '0');

/**
 * The ISO date `months` calendar months after `iso`, on the same day of the month or the last day
 * of a shorter month (January 31 plus one month is February 28 or 29). Null when unreadable.
 */
export function addMonths(iso, months) {
  const match = ISO_DATE.exec(iso || '');
  if (!match) {
    return null;
  }
  const total = Number(match[1]) * 12 + (Number(match[2]) - 1) + months;
  const year = Math.floor(total / 12);
  const month = (total % 12) + 1;
  const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const day = Math.min(Number(match[3]), lastDay);
  return `${year}-${pad(month)}-${pad(day)}`;
}

/**
 * The payments of a schedule.
 *
 * @param {{amount: number, start: string, end: string, frequency: string}} award the amount
 *   awarded, the award start and end dates, and one of the FREQUENCY_MONTHS keys
 * @returns {{key: string, dueDate: string, amount: number}[]} in date order; empty when the award
 *   cannot be split (no amount above zero, a missing or reversed period, an unknown frequency) or
 *   would need more than MAX_PAYMENTS payments
 */
export function buildPayments(award) {
  const { amount, start, end, frequency } = award || {};
  const step = FREQUENCY_MONTHS[frequency];
  const cents = Math.round(Number(amount) * 100);
  if (
    step === undefined ||
    !(cents > 0) ||
    !ISO_DATE.test(start || '') ||
    !ISO_DATE.test(end || '') ||
    end < start
  ) {
    return [];
  }
  const dates = [start];
  if (step > 0) {
    for (
      let next = addMonths(start, step);
      next <= end;
      next = addMonths(start, dates.length * step)
    ) {
      if (dates.length >= MAX_PAYMENTS) {
        return [];
      }
      dates.push(next);
    }
  }
  const each = Math.floor(cents / dates.length);
  const last = cents - each * (dates.length - 1);
  return dates.map((dueDate, index) => ({
    key: dueDate,
    dueDate,
    amount: (index === dates.length - 1 ? last : each) / 100
  }));
}
