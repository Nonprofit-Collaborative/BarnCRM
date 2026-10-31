/**
 * Ranks volunteers for a shift (V-11). Framework-free on purpose (plan 9.9): no lightning or
 * @salesforce imports, so the same module runs in a browser or a Node test, and anything that
 * can supply the input below can reuse it.
 *
 * Input, plain JSON:
 *   shift:      { weekday: 'Monday', requiredSkillIds: ['a01...'] }
 *   candidates: [{ personId, name, availableDays: ['Monday'], skillIds: [], interestIds: [],
 *                  hoursOnJob: 12, hoursTotal: 80, onboarding: 'cleared' | 'open' | 'none' }]
 *   weights:    optional; any key left out uses DEFAULT_WEIGHTS.
 *
 * Output: the candidates best first, each `{ personId, name, score, reasons }` where `reasons`
 * is a list of `{ code, ...values }` that the caller turns into words. Everyone passed in is
 * ranked; the caller decides how many to show. Ties break on name, so the order is stable.
 *
 * The score is the sum of the signals below, so a person can score under zero.
 */

/** The documented weights (admin guide, Suggested Volunteers). Points added to a person's score. */
export const DEFAULT_WEIGHTS = {
  /** Up to this many points for the share of the job's required skills the person has as skills. */
  skillMatch: 30,
  /** Up to this many points for required skills the person lists only as interests. */
  interestMatch: 10,
  /** Added when the shift's weekday is one of the person's available days. */
  availableDay: 25,
  /** Taken off (as a negative) when the person lists available days and the shift's is not one. */
  unavailableDay: -25,
  /** Up to this many points for approved hours already given on this job, reaching it at hoursOnJobCap. */
  hoursOnJob: 20,
  hoursOnJobCap: 40,
  /** Up to this many points for approved hours given in total, reaching it at hoursTotalCap. */
  hoursTotal: 5,
  hoursTotalCap: 200,
  /** Added when every onboarding step the person has is current (completed and not expired). */
  onboardingCleared: 10,
  /** Taken off (as a negative) when the person has an onboarding step that is not current. */
  onboardingOpen: -15
};

export const REASON = {
  SKILLS: 'skills',
  INTERESTS: 'interests',
  AVAILABLE_DAY: 'availableDay',
  UNAVAILABLE_DAY: 'unavailableDay',
  NO_AVAILABILITY: 'noAvailability',
  HOURS_ON_JOB: 'hoursOnJob',
  ONBOARDING_CLEARED: 'onboardingCleared',
  ONBOARDING_OPEN: 'onboardingOpen'
};

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function share(have, wanted) {
  return wanted === 0 ? 0 : have / wanted;
}

function capped(value, cap) {
  const number = Number(value) || 0;
  return cap > 0 ? Math.min(number, cap) / cap : 0;
}

function scoreOne(candidate, shift, weights) {
  const reasons = [];
  let score = 0;

  const required = asArray(shift.requiredSkillIds);
  if (required.length > 0) {
    const skills = new Set(asArray(candidate.skillIds));
    const interests = new Set(asArray(candidate.interestIds));
    const skillHits = required.filter((id) => skills.has(id)).length;
    const interestHits = required.filter((id) => !skills.has(id) && interests.has(id)).length;
    if (skillHits > 0) {
      score += weights.skillMatch * share(skillHits, required.length);
      reasons.push({ code: REASON.SKILLS, matched: skillHits, total: required.length });
    }
    if (interestHits > 0) {
      score += weights.interestMatch * share(interestHits, required.length);
      reasons.push({ code: REASON.INTERESTS, matched: interestHits, total: required.length });
    }
  }

  const days = asArray(candidate.availableDays);
  if (days.length === 0) {
    reasons.push({ code: REASON.NO_AVAILABILITY });
  } else if (days.includes(shift.weekday)) {
    score += weights.availableDay;
    reasons.push({ code: REASON.AVAILABLE_DAY, day: shift.weekday });
  } else {
    score += weights.unavailableDay;
    reasons.push({ code: REASON.UNAVAILABLE_DAY, day: shift.weekday });
  }

  const hoursOnJob = Number(candidate.hoursOnJob) || 0;
  if (hoursOnJob > 0) {
    score += weights.hoursOnJob * capped(hoursOnJob, weights.hoursOnJobCap);
    reasons.push({ code: REASON.HOURS_ON_JOB, hours: hoursOnJob });
  }
  score += weights.hoursTotal * capped(candidate.hoursTotal, weights.hoursTotalCap);

  if (candidate.onboarding === 'cleared') {
    score += weights.onboardingCleared;
    reasons.push({ code: REASON.ONBOARDING_CLEARED });
  } else if (candidate.onboarding === 'open') {
    score += weights.onboardingOpen;
    reasons.push({ code: REASON.ONBOARDING_OPEN });
  }

  return {
    personId: candidate.personId,
    name: candidate.name,
    score: Math.round(score * 10) / 10,
    reasons
  };
}

export function rankSuggestions(shift, candidates, weights) {
  const used = { ...DEFAULT_WEIGHTS, ...(weights || {}) };
  return asArray(candidates)
    .map((candidate) => scoreOne(candidate, shift || {}, used))
    .sort((a, b) => b.score - a.score || String(a.name).localeCompare(String(b.name)));
}
