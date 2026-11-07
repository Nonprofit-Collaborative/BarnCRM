/**
 * The call for speakers' shared rules, with no framework in it (EV-06, canonical model 29EV20,
 * plan Section 9.9): which statuses can still be scored or decided, the score choices, how an
 * average reads, and the status word for an application's badge.
 *
 * Plain JavaScript in and out, so a WordPress block or Node can use the same module.
 */

/** The statuses an application can still be reviewed and decided in (R-SA4). */
export const UNDECIDED = Object.freeze(['Submitted', 'In Review']);

/** The scores a reviewer can give (R-SA3). */
export const SCORES = Object.freeze([1, 2, 3, 4, 5]);

const STATUS_WORDS = Object.freeze({
  Submitted: 'new',
  'In Review': 'review',
  Accepted: 'approved',
  Declined: 'rejected',
  Withdrawn: 'inactive'
});

/** The badge word for an application's status. */
export function statusWord(status) {
  return STATUS_WORDS[status] || 'neutral';
}

/** Whether the application is still open to scores and a decision. */
export function isUndecided(status) {
  return UNDECIDED.includes(status);
}

/** Whether a score is a whole number from 1 to 5. */
export function isValidScore(score) {
  const value = Number(score);
  return Number.isInteger(value) && value >= 1 && value <= 5;
}

/** The score choices as combobox options, as text values. */
export function scoreOptions() {
  return SCORES.map((score) => ({ label: String(score), value: String(score) }));
}

/** An average to one decimal, or an empty string before the first review. */
export function averageText(average, reviewCount) {
  if (!reviewCount || average === null || average === undefined) {
    return '';
  }
  return `${Number(average).toFixed(1)} (${reviewCount})`;
}
