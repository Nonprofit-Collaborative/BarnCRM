/**
 * Territory Management's page logic with no Salesforce import (plan 9.9): the kinds a rule applies
 * to, the active rule count per kind against the most a run takes, and a run's summary read for
 * display. The page (c/territoryManager) renders what these return.
 */

/** What a rule applies to, in run order (the Applies To picklist values). */
export const KINDS = ['People', 'Households', 'Organizations'];
export const MODE_PREVIEW = 'Preview';
export const MODE_ASSIGN = 'Assign';
const BUSY_STATUSES = ['Queued', 'Running'];

/** Options for the Applies To picker. */
export function kindOptions() {
  return KINDS.map((kind) => ({ label: kind, value: kind }));
}

/** The kinds whose active rules, in active territories, are more than `max`. */
export function kindsOverLimit(territories, max) {
  const counts = {};
  for (const territory of territories || []) {
    if (!territory.active) {
      continue;
    }
    for (const rule of territory.rules || []) {
      if (rule.active) {
        counts[rule.appliesTo] = (counts[rule.appliesTo] || 0) + 1;
      }
    }
  }
  return KINDS.filter((kind) => (counts[kind] || 0) > max);
}

/** True when any territory has an active rule, so a run has something to do. */
export function hasActiveRule(territories) {
  return (territories || []).some(
    (territory) => territory.active && (territory.rules || []).some((rule) => rule.active)
  );
}

/** A run's summary: the count for each territory and the sample, empty when unreadable. */
export function parseSummary(summaryJson) {
  let summary;
  try {
    summary = summaryJson ? JSON.parse(summaryJson) : {};
  } catch {
    summary = {};
  }
  return {
    territories: Array.isArray(summary.territories) ? summary.territories : [],
    sample: Array.isArray(summary.sample) ? summary.sample : []
  };
}

/** True while a run is queued or running. */
export function isBusy(run) {
  return Boolean(run) && BUSY_STATUSES.includes(run.status);
}

/** A run's rows for display, newest first as given, each with a key and its summary read. */
export function runRows(runs) {
  return (runs || []).map((run) => ({
    ...run,
    key: run.id,
    summary: parseSummary(run.summaryJson),
    isAssign: run.mode === MODE_ASSIGN,
    busy: isBusy(run)
  }));
}
