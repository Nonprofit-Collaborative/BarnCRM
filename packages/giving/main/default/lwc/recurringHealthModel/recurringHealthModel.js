/**
 * Recurring donor health arithmetic (G-27, canonical model R-RH3, R-RH4), framework-free so it
 * ports as it is (plan Section 9.9): monthly values by frequency, monthly recurring revenue, the
 * reasons a gift is on the Save the Sustainer list, and twelve months of received totals.
 */

/** How many times a month each Commitment frequency charges. */
const PER_MONTH = {
  Weekly: 52 / 12,
  'Every two weeks': 26 / 12,
  Monthly: 1,
  Quarterly: 1 / 3,
  'Twice a year': 1 / 6,
  Yearly: 1 / 12
};

export const REASON_FAILED = 'failed';
export const REASON_CARD = 'card';
export const REASON_CANCELLED = 'cancelled';
export const REASON_OVERDUE = 'overdue';

/** Rounds to cents. */
function cents(value) {
  return Math.round(value * 100) / 100;
}

/** One gift's amount as a monthly value; an unknown frequency counts as monthly. */
export function monthlyValue(amount, frequency) {
  const factor = Object.prototype.hasOwnProperty.call(PER_MONTH, frequency)
    ? PER_MONTH[frequency]
    : 1;
  return cents((Number(amount) || 0) * factor);
}

/** Monthly recurring revenue and active gift count from the per-frequency slices. */
export function recurringRevenue(slices) {
  return (slices || []).reduce(
    (sum, slice) => ({
      total: cents(sum.total + monthlyValue(slice.total, slice.frequency)),
      count: sum.count + (Number(slice.count) || 0)
    }),
    { total: 0, count: 0 }
  );
}

/** Why a gift is on the list, in a fixed order. */
export function reasonsFor(row) {
  const reasons = [];
  if (row.failedCharges > 0) {
    reasons.push(REASON_FAILED);
  }
  if (row.cardExpires) {
    reasons.push(REASON_CARD);
  }
  if (row.cancelledAtProcessor) {
    reasons.push(REASON_CANCELLED);
  }
  if (row.overdueSince) {
    reasons.push(REASON_OVERDUE);
  }
  return reasons;
}

/** The list's rows with their monthly value, largest first, and the at-risk revenue. */
export function atRisk(rows) {
  const decorated = (rows || [])
    .map((row) => ({
      ...row,
      monthly: monthlyValue(row.amount, row.frequency),
      reasons: reasonsFor(row)
    }))
    .sort((a, b) => b.monthly - a.monthly);
  const total = cents(decorated.reduce((sum, row) => sum + row.monthly, 0));
  return { rows: decorated, total };
}

/**
 * This month and the eleven before, oldest first, each with its total (0 when none) and its
 * share of the largest month (0 to 100), for a bar.
 */
export function lastTwelveMonths(totals, today = new Date()) {
  const byKey = new Map(
    (totals || []).map((row) => [`${row.year}-${row.month}`, Number(row.total) || 0])
  );
  const months = [];
  for (let back = 11; back >= 0; back--) {
    const day = new Date(today.getFullYear(), today.getMonth() - back, 1);
    const year = day.getFullYear();
    const month = day.getMonth() + 1;
    months.push({
      key: `${year}-${month}`,
      year,
      month,
      total: byKey.get(`${year}-${month}`) || 0
    });
  }
  const largest = Math.max(0, ...months.map((row) => row.total));
  return months.map((row) => ({
    ...row,
    share: largest > 0 ? Math.round((row.total / largest) * 100) : 0
  }));
}
