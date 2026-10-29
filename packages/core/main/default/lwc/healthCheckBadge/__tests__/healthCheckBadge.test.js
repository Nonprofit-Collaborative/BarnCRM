import { healthCheckBadge } from 'c/healthCheckBadge';

describe('c/healthCheckBadge', () => {
  it('says Not Run Yet before the first full run', () => {
    expect(healthCheckBadge(undefined)).toEqual({
      badgeLabel: 'c.Core_OrgOptimizer_BadgeNotRun',
      badgeVariant: ''
    });
    expect(healthCheckBadge({ ranAt: null }).badgeLabel).toBe('c.Core_OrgOptimizer_BadgeNotRun');
  });

  it('puts errors before warnings, and passes a clean run', () => {
    const ranAt = '2026-10-28T10:00:00.000Z';
    expect(healthCheckBadge({ ranAt, errors: 2, warnings: 3 }).badgeVariant).toBe('error');
    expect(healthCheckBadge({ ranAt, errors: 0, warnings: 3 }).badgeVariant).toBe('warning');
    expect(healthCheckBadge({ ranAt, errors: 0, warnings: 0, infos: 4 })).toEqual({
      badgeLabel: 'c.Core_OrgOptimizer_BadgePassed',
      badgeVariant: 'success'
    });
  });
});
