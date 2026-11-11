import {
  DUE_LATER,
  DUE_NONE,
  DUE_OVERDUE,
  DUE_TODAY,
  OUTCOMES,
  daysUntil,
  dueState,
  groupName,
  todayIso
} from 'c/corporateHubModel';

describe('c-corporate-hub-model', () => {
  it('counts whole days across a month and a year end', () => {
    expect(daysUntil('2027-01-01', '2026-12-31')).toBe(1);
    expect(daysUntil('2027-03-01', '2027-02-27')).toBe(2);
    expect(daysUntil('2027-02-01', '2027-02-11')).toBe(-10);
    expect(daysUntil(null, '2027-02-11')).toBeNull();
    expect(daysUntil('not a date', '2027-02-11')).toBeNull();
  });

  it('says overdue, today, later or no date', () => {
    expect(dueState('2027-05-01', '2027-05-04')).toEqual({ state: DUE_OVERDUE, count: 3 });
    expect(dueState('2027-05-04', '2027-05-04')).toEqual({ state: DUE_TODAY, count: 0 });
    expect(dueState('2027-05-14', '2027-05-04')).toEqual({ state: DUE_LATER, count: 10 });
    expect(dueState(undefined, '2027-05-04')).toEqual({ state: DUE_NONE, count: 0 });
  });

  it('reads today in the local day', () => {
    expect(todayIso(new Date(2027, 0, 5, 23, 30))).toBe('2027-01-05');
  });

  it('turns a typed group name into a developer name', () => {
    expect(groupName('  Board Members ')).toBe('Board_Members');
    expect(groupName(undefined)).toBe('');
  });

  it('offers the three cycle outcomes, Done first', () => {
    expect(OUTCOMES).toEqual(['Done', 'Done Late', 'Not Required']);
  });
});
