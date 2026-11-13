import {
  bar,
  groupTasks,
  isOpen,
  percent,
  timelineSpan,
  todayMark,
  utilizationRows,
  BILLABLE_COLUMNS
} from 'c/projectsModel';

describe('c-projects-model', () => {
  it('works out a whole percent and is 0 for nothing', () => {
    expect(percent(1, 3)).toBe(33);
    expect(percent(2, 0)).toBe(0);
    expect(percent(undefined, undefined)).toBe(0);
  });

  it('treats Done and Cancelled as closed', () => {
    expect(isOpen({ status: 'Blocked' })).toBe(true);
    expect(isOpen({ status: 'Done' })).toBe(false);
    expect(isOpen({ status: 'Cancelled' })).toBe(false);
  });

  it('groups tasks under their phases, leaves cancelled ones out of the count, and keeps loose ones last', () => {
    const groups = groupTasks(
      [{ id: 'p1', name: 'Build' }],
      [
        { id: 't1', phaseId: 'p1', status: 'Done' },
        { id: 't2', phaseId: 'p1', status: 'In Progress' },
        { id: 't3', phaseId: 'p1', status: 'Cancelled' },
        { id: 't4', phaseId: null, status: 'Not Started' }
      ]
    );
    expect(groups).toHaveLength(2);
    expect(groups[0]).toMatchObject({ id: 'p1', done: 1, total: 2, percent: 50 });
    expect(groups[0].tasks).toHaveLength(3);
    expect(groups[1]).toMatchObject({ id: null, total: 1, percent: 0 });
  });

  it('places phase bars on the project span and marks today', () => {
    const project = { startDate: '2027-01-01', targetDate: '2027-01-10' };
    const phases = [
      { startDate: '2027-01-01', endDate: '2027-01-05' },
      { startDate: '2027-01-06' }
    ];
    const span = timelineSpan(project, phases);
    expect(bar(phases[0], span)).toEqual({ left: 0, width: 50 });
    expect(bar(phases[1], span)).toEqual({ left: 50, width: 10 });
    expect(bar({}, span)).toBeNull();
    expect(timelineSpan({}, [])).toBeNull();
    expect(todayMark(span, new Date(2027, 0, 6))).toBe(50);
    expect(todayMark(span, new Date(2028, 0, 1))).toBeNull();
  });

  it('sorts utilization by name with the share of capacity used', () => {
    const rows = utilizationRows([
      { name: 'Zoe', logged: 20, capacity: 40 },
      { name: 'Ann', logged: 10, capacity: 0 }
    ]);
    expect(rows.map((row) => row.name)).toEqual(['Ann', 'Zoe']);
    expect(rows[1].used).toBe(50);
    expect(rows[0].used).toBe(0);
  });

  it('names the billable export columns', () => {
    expect(BILLABLE_COLUMNS.map((column) => column.path)).toContain('amount');
  });
});
