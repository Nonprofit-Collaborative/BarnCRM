import {
  REASON_CARD,
  REASON_FAILED,
  REASON_OVERDUE,
  atRisk,
  lastTwelveMonths,
  monthlyValue,
  reasonsFor,
  recurringRevenue
} from 'c/recurringHealthModel';

describe('c/recurringHealthModel', () => {
  it('turns each frequency into a monthly value', () => {
    expect(monthlyValue(12, 'Weekly')).toBe(52);
    expect(monthlyValue(26, 'Every two weeks')).toBe(56.33);
    expect(monthlyValue(25, 'Monthly')).toBe(25);
    expect(monthlyValue(30, 'Quarterly')).toBe(10);
    expect(monthlyValue(60, 'Twice a year')).toBe(10);
    expect(monthlyValue(120, 'Yearly')).toBe(10);
    expect(monthlyValue(5, 'Someday')).toBe(5);
    expect(monthlyValue(null, 'Monthly')).toBe(0);
  });

  it('adds the slices into monthly recurring revenue', () => {
    expect(
      recurringRevenue([
        { frequency: 'Monthly', total: 100, count: 4 },
        { frequency: 'Yearly', total: 1200, count: 2 }
      ])
    ).toEqual({ total: 200, count: 6 });
    expect(recurringRevenue(undefined)).toEqual({ total: 0, count: 0 });
  });

  it('names the reasons in order and sorts the list by monthly value', () => {
    expect(
      reasonsFor({ failedCharges: 2, cardExpires: '2026-12-31', overdueSince: '2026-10-01' })
    ).toEqual([REASON_FAILED, REASON_CARD, REASON_OVERDUE]);
    const result = atRisk([
      { id: 'a', amount: 120, frequency: 'Yearly', failedCharges: 1 },
      { id: 'b', amount: 50, frequency: 'Monthly', cardExpires: '2026-12-31' }
    ]);
    expect(result.rows.map((row) => row.id)).toEqual(['b', 'a']);
    expect(result.total).toBe(60);
  });

  it('fills twelve months, oldest first, with zero where nothing came in', () => {
    const months = lastTwelveMonths(
      [
        { year: 2026, month: 11, total: 200 },
        { year: 2026, month: 1, total: 100 }
      ],
      new Date(2026, 10, 11)
    );
    expect(months).toHaveLength(12);
    expect(months[0]).toMatchObject({ year: 2025, month: 12, total: 0, share: 0 });
    expect(months[1]).toMatchObject({ year: 2026, month: 1, total: 100, share: 50 });
    expect(months[11]).toMatchObject({ year: 2026, month: 11, total: 200, share: 100 });
  });
});
