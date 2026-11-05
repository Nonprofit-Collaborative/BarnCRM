import { monthRange, monthWeeks, shiftMonth, weekdayOrder } from 'c/grantCalendarModel';

describe('grantCalendarModel', () => {
  it('moves across years', () => {
    expect(shiftMonth(2026, 12, 1)).toEqual({ year: 2027, month: 1 });
    expect(shiftMonth(2027, 1, -1)).toEqual({ year: 2026, month: 12 });
    expect(shiftMonth(2027, 3, 0)).toEqual({ year: 2027, month: 3 });
  });

  it('shows whole weeks around the month, from the chosen first day', () => {
    // November 2026 starts on a Sunday and ends on a Monday.
    expect(monthRange(2026, 11, 0)).toEqual({ from: '2026-11-01', to: '2026-12-05' });
    expect(monthRange(2026, 11, 1)).toEqual({ from: '2026-10-26', to: '2026-12-06' });
    // February 2026 is exactly four weeks from Sunday.
    expect(monthRange(2026, 2, 0)).toEqual({ from: '2026-02-01', to: '2026-02-28' });
  });

  it('lays the rows into their days, sorted, with overdue marked', () => {
    const rows = [
      { id: 'b', name: 'Report', kind: 'requirement', deadline: '2026-11-10' },
      { id: 'a', name: 'Application', kind: 'application', deadline: '2026-11-10' },
      { id: 'c', name: 'Payment', kind: 'payment', deadline: '2026-11-03' },
      { id: 'x', name: 'Outside', kind: 'payment', deadline: '2027-01-15' },
      { id: 'y', name: 'No date', kind: 'payment' }
    ];
    const weeks = monthWeeks(2026, 11, rows, '2026-11-05', 0);
    expect(weeks).toHaveLength(5);
    weeks.forEach((week) => expect(week.days).toHaveLength(7));
    const days = weeks.flatMap((week) => week.days);
    const tenth = days.find((day) => day.date === '2026-11-10');
    expect(tenth.items.map((item) => item.id)).toEqual(['a', 'b']);
    expect(tenth.items[0].overdue).toBe(false);
    expect(days.find((day) => day.date === '2026-11-03').items[0].overdue).toBe(true);
    expect(days.find((day) => day.date === '2026-11-05').isToday).toBe(true);
    expect(days.find((day) => day.date === '2026-12-01').inMonth).toBe(false);
    expect(days.flatMap((day) => day.items)).toHaveLength(3);
  });

  it('copes with no rows', () => {
    const weeks = monthWeeks(2026, 2, undefined, '2026-02-01');
    expect(weeks).toHaveLength(4);
    expect(weeks[0].key).toBe('2026-02-01');
  });

  it('orders the weekday headings from the first day', () => {
    expect(weekdayOrder(0)).toEqual([0, 1, 2, 3, 4, 5, 6]);
    expect(weekdayOrder(1)).toEqual([1, 2, 3, 4, 5, 6, 0]);
  });
});
