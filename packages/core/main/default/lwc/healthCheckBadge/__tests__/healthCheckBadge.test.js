import { healthCheckBadge, lastRunFrom } from 'c/healthCheckBadge';

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

  it('reads the stored last run, and treats a missing or unreadable one as never run', () => {
    const ranAt = '2026-11-20T09:00:00.000Z';
    expect(lastRunFrom(ranAt, '1, 2,3')).toEqual({ ranAt, errors: 1, warnings: 2, infos: 3 });
    expect(lastRunFrom(null, '1,2,3')).toEqual({ ranAt: null });
    expect(lastRunFrom(ranAt, null)).toEqual({ ranAt: null });
    expect(lastRunFrom(ranAt, '1,2')).toEqual({ ranAt: null });
    expect(lastRunFrom(ranAt, '1,,3')).toEqual({ ranAt: null });
    expect(lastRunFrom(ranAt, 'a,b,c')).toEqual({ ranAt: null });
  });
});
