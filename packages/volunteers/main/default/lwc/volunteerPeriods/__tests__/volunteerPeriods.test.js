import { periodDates, periodOptions, THIS_YEAR, LAST_YEAR, CUSTOM } from 'c/volunteerPeriods';

describe('c/volunteerPeriods', () => {
  const today = new Date(2026, 10, 4);

  it('runs This Year from 1 January to today', () => {
    expect(periodDates(THIS_YEAR, today)).toEqual({ fromDate: '2026-01-01', toDate: '2026-11-04' });
  });

  it('takes the whole of the year before for Last Year', () => {
    expect(periodDates(LAST_YEAR, today)).toEqual({ fromDate: '2025-01-01', toDate: '2025-12-31' });
  });

  it('leaves Custom dates to the person', () => {
    expect(periodDates(CUSTOM, today)).toBeUndefined();
  });

  it('lists the three choices in order with the labels given', () => {
    expect(periodOptions({ thisYear: 'A', lastYear: 'B', custom: 'C' })).toEqual([
      { label: 'A', value: THIS_YEAR },
      { label: 'B', value: LAST_YEAR },
      { label: 'C', value: CUSTOM }
    ]);
  });
});
