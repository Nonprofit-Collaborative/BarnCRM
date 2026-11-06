import {
  buildColumns,
  closedStages,
  daysBetween,
  deadlineRows,
  initialsOf,
  markDrag,
  moveTargets,
  urgencyOf
} from 'c/grantPipelineModel';

describe('grantPipelineModel', () => {
  it('lists the stages with no column as drop zones, in stage order', () => {
    expect(
      closedStages(
        ['Prospect', 'Applied', 'Awarded', 'Declined', 'Withdrawn'],
        ['Prospect', 'Applied']
      )
    ).toEqual(['Awarded', 'Declined', 'Withdrawn']);
    expect(closedStages(undefined, ['Prospect'])).toEqual([]);
  });

  it('marks the drag target column and the carried card', () => {
    const columns = [
      { stage: 'Prospect', cards: [{ id: 'a' }, { id: 'b' }] },
      { stage: 'Applied', cards: [] }
    ];
    const marked = markDrag(columns, {
      active: true,
      itemId: 'a',
      fromZone: 'Prospect',
      overZone: 'Applied'
    });
    expect(marked.map((column) => column.isTarget)).toEqual([false, true]);
    expect(marked[0].cards.map((card) => card.isDragging)).toEqual([true, false]);
    expect(columns[0].isTarget).toBeUndefined();
    expect(markDrag(columns, undefined)[1].isTarget).toBe(false);
  });

  it('says how urgent a deadline is in the status vocabulary', () => {
    expect(urgencyOf(-1)).toBe('overdue');
    expect(urgencyOf(0)).toBe('due soon');
    expect(urgencyOf(14)).toBe('due soon');
    expect(urgencyOf(15)).toBeNull();
    expect(urgencyOf(null)).toBeNull();
  });

  it('takes up to two initials from a name', () => {
    expect(initialsOf('Ana Maria Ruiz')).toBe('AM');
    expect(initialsOf('maria')).toBe('M');
    expect(initialsOf('')).toBe('');
    expect(initialsOf(null)).toBe('');
  });

  it('counts whole days either way and refuses unreadable dates', () => {
    expect(daysBetween('2026-11-02', '2026-11-12')).toBe(10);
    expect(daysBetween('2026-11-02', '2026-10-31')).toBe(-2);
    expect(daysBetween(null, '2026-11-02')).toBeNull();
    expect(daysBetween('not a date', '2026-11-02')).toBeNull();
  });

  it('puts cards and totals in their stage columns, in stage order', () => {
    const columns = buildColumns(
      ['Prospect', 'Applied'],
      [
        { stage: 'Applied', count: 2, amount: 30000 },
        { stage: 'Awarded', count: 1, amount: 5 }
      ],
      [
        { id: '1', stage: 'Applied' },
        { id: '2', stage: 'Applied' },
        { id: '3', stage: 'Awarded' }
      ]
    );
    expect(columns.map((column) => column.stage)).toEqual(['Prospect', 'Applied']);
    expect(columns[0]).toMatchObject({ count: 0, amount: 0, cards: [] });
    expect(columns[1]).toMatchObject({ count: 2, amount: 30000 });
    expect(columns[1].cards.map((card) => card.id)).toEqual(['1', '2']);
  });

  it('copes with nothing at all', () => {
    expect(buildColumns(undefined, undefined, undefined)).toEqual([]);
    expect(deadlineRows(undefined, '2026-11-02')).toEqual([]);
    expect(moveTargets(undefined, 'Prospect')).toEqual([]);
  });

  it('sorts deadlines soonest first and marks the overdue ones', () => {
    const rows = deadlineRows(
      [
        { id: 'b', name: 'B', deadline: '2026-11-20' },
        { id: 'a', name: 'A', deadline: '2026-10-30' },
        { id: 'c', name: 'C', deadline: '2026-11-20' },
        { id: 'none', name: 'No deadline', deadline: null }
      ],
      '2026-11-02'
    );
    expect(rows.map((row) => row.id)).toEqual(['a', 'b', 'c']);
    expect(rows[0]).toMatchObject({ daysLeft: -3, overdue: true });
    expect(rows[1]).toMatchObject({ daysLeft: 18, overdue: false });
  });

  it('offers every stage but the current one as a move', () => {
    expect(moveTargets(['Prospect', 'Applied', 'Awarded'], 'Applied')).toEqual([
      'Prospect',
      'Awarded'
    ]);
  });
});
