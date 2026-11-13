/**
 * The call for speakers' shared rules, with no framework in it (EV-06, canonical model 29EV20,
 * plan Section 9.9): which statuses can still be scored or decided, the score choices, how an
 * average reads, and the status word for an application's badge.
 *
 * Plain JavaScript in and out, so a WordPress block or Node can use the same module.
 */
import { badgeWord } from 'c/barnFormat';

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
  return badgeWord(STATUS_WORDS, status);
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

/* EV-21: weighted criteria, the scoring matrix, compare, assignments and blind review. */

export const MAX_CRITERIA = 10;
export const MAX_WEIGHT = 10;
export const MAX_LABEL = 40;
/** How many proposals Compare puts side by side. */
export const MAX_COMPARE = 4;

/**
 * Whether a list of `{ label, weight }` can be saved (R-SA6): at most 10, each label set, unique
 * ignoring case and at most 40 characters, each weight a whole number from 1 to 10. The same rule
 * as `EventProposalReview.validated`.
 */
export function criteriaValid(criteria) {
  const list = criteria || [];
  const seen = new Set();
  return (
    list.length <= MAX_CRITERIA &&
    list.every((criterion) => {
      const label = String((criterion && criterion.label) || '').trim();
      const weight = Number(criterion && criterion.weight);
      const key = label.toLowerCase();
      const fresh = !seen.has(key);
      seen.add(key);
      return (
        label.length > 0 &&
        label.length <= MAX_LABEL &&
        Number.isInteger(weight) &&
        weight >= 1 &&
        weight <= MAX_WEIGHT &&
        fresh
      );
    })
  );
}

/**
 * R-SA7: the weighted score of one review, sum(weight x score) / sum(weight) to two decimals, or
 * null while any criterion is unscored. The same rule as `EventProposalReview.weightedScore`.
 */
export function weightedScore(criteria, scores) {
  const list = criteria || [];
  if (!list.length) {
    return null;
  }
  let total = 0;
  let weights = 0;
  for (const criterion of list) {
    const score = Number((scores || {})[criterion.label]);
    if (!isValidScore(score)) {
      return null;
    }
    total += criterion.weight * score;
    weights += criterion.weight;
  }
  return Math.round((total / weights) * 100 + Number.EPSILON) / 100;
}

/** A review's whole Score: the weighted score rounded, halves up. */
export function roundScore(weighted) {
  return weighted === null || weighted === undefined ? null : Math.floor(Number(weighted) + 0.5);
}

/** A review's scores by criterion label, from its JSON; empty when unreadable. */
export function scoresOf(json) {
  try {
    return json ? JSON.parse(json) : {};
  } catch {
    return {};
  }
}

/**
 * The scoring matrix: per proposal, the average score of each criterion over its scored
 * reviews (to one decimal, '' when none), the total of their weighted scores, the weighted
 * average and the count. Without criteria `cells` is empty.
 */
export function matrixRows(applications, criteria) {
  return (applications || []).map((application) => {
    const scored = (application.reviews || []).filter(
      (review) => review.score !== null && review.score !== undefined
    );
    const cells = (criteria || []).map((criterion) => {
      const values = scored
        .map((review) => Number(scoresOf(review.criteriaScores)[criterion.label]))
        .filter(isValidScore);
      return {
        key: `${application.id}-${criterion.label}`,
        text: values.length
          ? (values.reduce((sum, value) => sum + value, 0) / values.length).toFixed(1)
          : ''
      };
    });
    const total = scored.reduce(
      (sum, review) => sum + Number(review.weightedScore || review.score || 0),
      0
    );
    return {
      id: application.id,
      name: application.name,
      cells,
      total: scored.length ? total.toFixed(2) : '',
      average:
        application.weightedAverage === null || application.weightedAverage === undefined
          ? ''
          : Number(application.weightedAverage).toFixed(2),
      reviews: scored.length
    };
  });
}

/** Whether the chosen proposals can be compared: two to four of them. */
export function canCompare(chosen) {
  const count = (chosen || []).length;
  return count >= 2 && count <= MAX_COMPARE;
}

/**
 * Blind review (decision 12): while a proposal is undecided, the applicant's, presenters' and
 * reviewers' names read `hidden`. A working aid only: the records stay readable.
 */
export function blinded(application, blind, hidden) {
  if (!blind || !isUndecided(application.status)) {
    return application;
  }
  return {
    ...application,
    applicant: hidden,
    contactId: null,
    presenters: (application.presenters || []).map((presenter) => ({
      ...presenter,
      name: hidden
    })),
    reviews: (application.reviews || []).map((review) => ({ ...review, reviewer: hidden }))
  };
}
