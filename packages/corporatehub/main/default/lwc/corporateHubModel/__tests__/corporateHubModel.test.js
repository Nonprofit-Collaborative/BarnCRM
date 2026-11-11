import {
  DUE_LATER,
  DUE_NONE,
  DUE_OVERDUE,
  DUE_TODAY,
  OUTCOMES,
  daysUntil,
  dueState,
  expiringSeats,
  groupName,
  percent,
  skillGaps,
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

  it('counts each skill, wanted first, and lists the wanted ones nobody holds', () => {
    const result = skillGaps(
      ['Finance', 'Legal'],
      [{ values: ['Finance', 'HR'] }, { values: ['Finance'] }, {}]
    );
    expect(result.counts).toEqual([
      { skill: 'Finance', count: 2 },
      { skill: 'Legal', count: 0 },
      { skill: 'HR', count: 1 }
    ]);
    expect(result.gaps).toEqual(['Legal']);
    expect(skillGaps(undefined, undefined)).toEqual({ counts: [], gaps: [] });
  });

  it('finds the seats ending within the window, overdue included', () => {
    const seats = [
      { id: 'a', due: '2027-05-01' },
      { id: 'b', due: '2027-05-20' },
      { id: 'c', due: '2027-09-01' },
      { id: 'd', due: null }
    ];
    expect(expiringSeats(seats, '2027-05-04', 30).map((s) => s.id)).toEqual(['a', 'b']);
    expect(expiringSeats(undefined, '2027-05-04', 30)).toEqual([]);
  });

  it('rounds a percent and is 0 for an empty whole', () => {
    expect(percent(1, 3)).toBe(33);
    expect(percent(2, 3)).toBe(67);
    expect(percent(5, 0)).toBe(0);
    expect(percent(null, 4)).toBe(0);
  });
});
