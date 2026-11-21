import { healthCheckBadge } from 'c/healthCheckBadge';

describe('c/healthCheckBadge', () => {
  it('says Not Run Yet before the first full run', () => {
    expect(healthCheckBadge(undefined)).toEqual({
      badgeLabel: 'c.Core_OrgOptimizer_BadgeNotRun',
      badgeVariant: ''
    });
    expect(healthCheckBadge({ ranAt: null }).badgeLabel).toBe('c.Core_OrgOptimizer_BadgeNotRun');
  });

  it('puts Needs Fixing before Worth Knowing, and says All Clear for a clean run', () => {
    const ranAt = '2026-10-28T10:00:00.000Z';
    expect(healthCheckBadge({ ranAt, errors: 2, warnings: 3 })).toEqual({
      badgeLabel: 'c.Core_OrgOptimizer_BadgeErrors',
      badgeVariant: 'error'
    });
    expect(healthCheckBadge({ ranAt, errors: 0, warnings: 3 })).toEqual({
      badgeLabel: 'c.Core_OrgOptimizer_BadgeWarnings',
      badgeVariant: 'warning'
    });
    expect(healthCheckBadge({ ranAt, errors: 0, warnings: 0, infos: 4 })).toEqual({
      badgeLabel: 'c.Core_OrgOptimizer_BadgeAllClear',
      badgeVariant: 'success'
    });
  });
});
