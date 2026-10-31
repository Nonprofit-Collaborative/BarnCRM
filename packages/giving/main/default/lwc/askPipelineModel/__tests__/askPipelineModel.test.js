import { buildColumns, daysBetween, listRows, OTHER_COLUMN } from 'c/askPipelineModel';

describe('askPipelineModel', () => {
  it('counts whole days between two ISO dates, never below zero', () => {
    expect(daysBetween('2026-10-01', '2026-10-31')).toBe(30);
    expect(daysBetween('2026-11-02', '2026-10-31')).toBe(0);
    expect(daysBetween(null, '2026-10-31')).toBeNull();
    expect(daysBetween('not a date', '2026-10-31')).toBeNull();
  });

  it('builds one column per stage in list order with the exact totals and the cards', () => {
    const columns = buildColumns(
      ['Identified', 'Asked'],
      [
        { stage: 'Asked', count: 3, amount: 4500 },
        { stage: 'Identified', count: 1, amount: 100 }
      ],
      [{ id: 'a1', stage: 'Asked', stageChangedDate: '2026-10-21' }],
      '2026-10-31'
    );
    expect(columns.map((column) => column.stage)).toEqual(['Identified', 'Asked']);
    expect(columns[1].count).toBe(3);
    expect(columns[1].amount).toBe(4500);
    expect(columns[1].cards[0].daysInStage).toBe(10);
    expect(columns[0].cards).toEqual([]);
  });

  it('gathers asks at a stage not in the list in one extra column', () => {
    const columns = buildColumns(
      ['Identified'],
      [
        { stage: 'Old stage', count: 2, amount: 50 },
        { stage: 'Retired', count: 1, amount: null }
      ],
      [{ id: 'a2', stage: 'Old stage', stageChangedDate: null }],
      '2026-10-31'
    );
    const other = columns[columns.length - 1];
    expect(other.key).toBe(OTHER_COLUMN);
    expect(other.isOther).toBe(true);
    expect(other.count).toBe(3);
    expect(other.amount).toBe(50);
    expect(other.cards[0].daysInStage).toBeNull();
  });

  it('leaves the extra column out when every ask is at a listed stage', () => {
    const columns = buildColumns(['Identified'], [], [], '2026-10-31');
    expect(columns).toHaveLength(1);
    expect(buildColumns(null, null, null, '2026-10-31')).toEqual([]);
  });

  it('lists the cards in stage order for the list view', () => {
    const columns = buildColumns(
      ['Identified', 'Asked'],
      [],
      [
        { id: 'late', stage: 'Asked' },
        { id: 'early', stage: 'Identified' }
      ],
      '2026-10-31'
    );
    expect(listRows(columns).map((row) => row.id)).toEqual(['early', 'late']);
    expect(listRows(null)).toEqual([]);
  });
});
