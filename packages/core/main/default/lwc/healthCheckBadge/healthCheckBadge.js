import BADGE_ERRORS from '@salesforce/label/c.Core_OrgOptimizer_BadgeErrors';
import BADGE_WARNINGS from '@salesforce/label/c.Core_OrgOptimizer_BadgeWarnings';
import BADGE_PASSED from '@salesforce/label/c.Core_OrgOptimizer_BadgePassed';
import BADGE_NOT_RUN from '@salesforce/label/c.Core_OrgOptimizer_BadgeNotRun';

/**
 * The one badge for a Health Check result (HealthCheckController.getLastRun's summary), so the
 * Org Optimizer tile and the Health Check summary on BarnCRM Home always agree: errors first,
 * then warnings, then Passed; Not Run Yet before the first full run.
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
  return { badgeLabel: BADGE_PASSED, badgeVariant: 'success' };
}
