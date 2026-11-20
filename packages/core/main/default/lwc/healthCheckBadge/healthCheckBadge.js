import BADGE_ERRORS from '@salesforce/label/c.Core_OrgOptimizer_BadgeErrors';
import BADGE_WARNINGS from '@salesforce/label/c.Core_OrgOptimizer_BadgeWarnings';
import BADGE_ALL_CLEAR from '@salesforce/label/c.Core_OrgOptimizer_BadgeAllClear';
import BADGE_NOT_RUN from '@salesforce/label/c.Core_OrgOptimizer_BadgeNotRun';

/**
 * The one badge for a Health Check result (the Org Optimizer's last run summary, or
 * `lastRunFrom` below), so the Org Optimizer tile, its Health Check section and the Health
 * Check tile on BarnCRM Home always agree, in the panel's own words: Needs Fixing first, then
 * Worth Knowing, then All Clear; Not Run Yet before the first full run (admin-6).
 * Returns `{ badgeLabel, badgeVariant }` for c-barn-tool-tile or c-barn-stat-tile.
 */
export function healthCheckBadge(lastRun) {
  if (!lastRun || !lastRun.ranAt) {
    return { badgeLabel: BADGE_NOT_RUN, badgeVariant: '' };
  }
  if (lastRun.errors > 0) {
    return { badgeLabel: BADGE_ERRORS.replace('{0}', lastRun.errors), badgeVariant: 'error' };
  }
  if (lastRun.warnings > 0) {
    return {
      badgeLabel: BADGE_WARNINGS.replace('{0}', lastRun.warnings),
      badgeVariant: 'warning'
    };
  }
  return { badgeLabel: BADGE_ALL_CLEAR, badgeVariant: 'success' };
}

/**
 * The stored last run (ADR-0106): when it ran and its counts as "errors,warnings,infos", read
 * into `{ ranAt, errors, warnings, infos }`. A run never made, or counts nobody can read, come
 * back with no `ranAt`, which reads as Not Run Yet; the next run writes them again.
 */
export function lastRunFrom(ranAt, stored) {
  const parts = typeof stored === 'string' ? stored.split(',').map((part) => part.trim()) : [];
  if (!ranAt || parts.length !== 3 || parts.some((part) => !/^\d+$/.test(part))) {
    return { ranAt: null };
  }
  const [errors, warnings, infos] = parts.map(Number);
  return { ranAt, errors, warnings, infos };
}
