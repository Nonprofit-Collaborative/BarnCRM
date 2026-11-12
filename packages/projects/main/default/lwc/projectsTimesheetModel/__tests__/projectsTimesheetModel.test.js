import {
  addDays,
  buildGrid,
  cellChanges,
  groupApprovals,
  isEditable,
  mondayOf,
  newRow,
  round2,
  weekDays,
  weekStatus,
  withTotals
} from 'c/projectsTimesheetModel';

const MONDAY = '2026-11-09';
const days = weekDays(MONDAY);

const entry = (id, iso, hours, extra = {}) => ({
  Id: id,
  Project__c: 'p1',
  Project__r: { Name: 'Rollout' },
  Task__c: 't1',
  Task__r: { Name: 'Build' },
  Billable__c: true,
  Date__c: iso,
  Hours__c: hours,
  Status__c: 'Open',
  ...extra
});

describe('c-projects-timesheet-model week math', () => {
  it('finds the Monday of any day, and Sunday belongs to the week before', () => {
    expect(mondayOf('2026-11-12')).toBe(MONDAY);
    expect(mondayOf('2026-11-09')).toBe(MONDAY);
    expect(mondayOf('2026-11-15')).toBe(MONDAY);
    expect(mondayOf('2026-11-16')).toBe('2026-11-16');
  });

  it('crosses month and year ends and leap days without moving a day', () => {
    expect(addDays('2026-12-30', 3)).toBe('2027-01-02');
    expect(addDays('2028-02-28', 1)).toBe('2028-02-29');
    expect(mondayOf('2027-01-01')).toBe('2026-12-28');
    expect(addDays(MONDAY, -7)).toBe('2026-11-02');
  });

  it('lists seven days from Monday with the weekend marked', () => {
    expect(days).toHaveLength(7);
    expect(days[0]).toMatchObject({ iso: MONDAY, name: 'Mon', day: 9, weekend: false });
    expect(days[6]).toMatchObject({ iso: '2026-11-15', name: 'Sun', weekend: true });
  });

  it('rounds to two decimals', () => {
    expect(round2(0.1 + 0.2)).toBe(0.3);
    expect(round2(undefined)).toBe(0);
  });
});

describe('c-projects-timesheet-model grid', () => {
  it('groups entries into one row per project, task and billable flag with totals', () => {
    const grid = buildGrid(
      [
        entry('e1', MONDAY, 4),
        entry('e2', '2026-11-10', 3.5),
        entry('e3', MONDAY, 1, { Task__c: null, Task__r: null, Billable__c: false })
      ],
      days
    );
    expect(grid.rows).toHaveLength(2);
    expect(grid.rows[0].total).toBe(7.5);
    expect(grid.rows[0].cells[0]).toMatchObject({ hours: 4, entryId: 'e1', editable: true });
    expect(grid.dayTotals).toEqual([5, 3.5, 0, 0, 0, 0, 0]);
    expect(grid.total).toBe(8.5);
  });

  it('locks Submitted and Approved cells and a cell holding two entries', () => {
    const grid = buildGrid(
      [
        entry('e1', MONDAY, 4, { Status__c: 'Submitted' }),
        entry('e2', '2026-11-10', 2, { Status__c: 'Approved' }),
        entry('e3', '2026-11-11', 1),
        entry('e4', '2026-11-11', 2),
        entry('e5', '2026-11-12', 2, { Status__c: 'Rejected', Rejection_Reason__c: 'Wrong task' })
      ],
      days
    );
    const cells = grid.rows[0].cells;
    expect(cells[0].editable).toBe(false);
    expect(cells[1].editable).toBe(false);
    expect(cells[2]).toMatchObject({ hours: 3, editable: false, entryId: null });
    expect(cells[3]).toMatchObject({ editable: true, status: 'Rejected', reason: 'Wrong task' });
    expect(cells[4].editable).toBe(true);
    expect(isEditable('Submitted')).toBe(false);
    expect(isEditable(null)).toBe(true);
  });

  it('adds an empty row and totals it', () => {
    const row = newRow({ Id: 'p2', Name: 'Other' }, null, true, days);
    const grid = withTotals([row], days);
    expect(row.key).toBe('p2||1');
    expect(grid.total).toBe(0);
    expect(grid.rows[0].cells.every((cell) => cell.editable)).toBe(true);
  });
});

describe('c-projects-timesheet-model status and edits', () => {
  it('counts statuses and says what Submit and Recall can do', () => {
    const none = weekStatus([], []);
    expect(none.canSubmit).toBe(false);
    expect(none.canRecall).toBe(false);
    const mixed = weekStatus(
      [entry('a', MONDAY, 1), entry('b', MONDAY, 1, { Status__c: 'Submitted' })],
      [{ Status__c: 'Rejected' }, { Status__c: null }]
    );
    expect(mixed).toMatchObject({ Open: 1, Submitted: 1, Rejected: 1, none: 1 });
    expect(mixed.canSubmit).toBe(true);
    expect(mixed.canRecall).toBe(true);
  });

  it('turns edits into new entries and changed hours, and reports what it cannot send', () => {
    const grid = buildGrid(
      [
        entry('e1', MONDAY, 4),
        entry('e2', '2026-11-10', 2, { Status__c: 'Submitted' }),
        entry('e3', '2026-11-11', 2)
      ],
      days
    );
    const key = grid.rows[0].key;
    const result = cellChanges(grid.rows, {
      [`${key}|${days[0].iso}`]: '5', // changed
      [`${key}|${days[1].iso}`]: '9', // locked: ignored
      [`${key}|${days[2].iso}`]: '', // cleared
      [`${key}|${days[3].iso}`]: '1.5', // new
      [`${key}|${days[4].iso}`]: 'abc', // invalid
      [`${key}|${days[5].iso}`]: '25' // too many hours
    });
    expect(result.cells).toEqual([
      expect.objectContaining({ id: 'e1', hours: 5, workDate: days[0].iso }),
      expect.objectContaining({
        id: null,
        hours: 1.5,
        projectId: 'p1',
        taskId: 't1',
        billable: true
      })
    ]);
    expect(result.cleared).toEqual([{ row: key, iso: days[2].iso }]);
    expect(result.invalid).toHaveLength(2);
  });

  it('sends nothing for an unchanged cell or a blank empty one', () => {
    const grid = buildGrid([entry('e1', MONDAY, 4)], days);
    const key = grid.rows[0].key;
    const result = cellChanges(grid.rows, {
      [`${key}|${days[0].iso}`]: '4',
      [`${key}|${days[1].iso}`]: ''
    });
    expect(result).toEqual({ cells: [], cleared: [], invalid: [] });
  });
});

describe('c-projects-timesheet-model approvals', () => {
  it('groups the queue by person and week, oldest first, with hours and expense amounts', () => {
    const user = (id, name) => ({ User__c: id, User__r: { Name: name } });
    const groups = groupApprovals(
      [
        { ...entry('a', '2026-11-12', 2), ...user('u1', 'Zed') },
        { ...entry('b', '2026-11-09', 1.5), ...user('u1', 'Zed') },
        { ...entry('c', '2026-11-03', 3), ...user('u2', 'Amy'), Project__r: { Name: 'Other' } }
      ],
      [
        {
          Id: 'x',
          Date__c: '2026-11-10',
          Amount__c: 40.25,
          Project__r: { Name: 'Rollout' },
          ...user('u1', 'Zed')
        }
      ]
    );
    expect(groups).toHaveLength(2);
    expect(groups[0]).toMatchObject({ person: 'Amy', weekStart: '2026-11-02', hours: 3 });
    expect(groups[1]).toMatchObject({
      person: 'Zed',
      weekStart: MONDAY,
      hours: 3.5,
      amount: 40.25,
      projects: 'Rollout'
    });
    expect(groups[1].ids.sort()).toEqual(['a', 'b', 'x']);
    expect(groups[1].lines.filter((line) => line.kind === 'expense')).toHaveLength(1);
  });

  it('handles an empty queue', () => {
    expect(groupApprovals(undefined, undefined)).toEqual([]);
  });
});
