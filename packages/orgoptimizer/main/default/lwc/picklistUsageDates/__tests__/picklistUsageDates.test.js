import { groupsOf, mergeDates, applyDates, scanProgress } from 'c/picklistUsageDates';

describe('picklistUsageDates', () => {
  it('splits fields into groups in order', () => {
    expect(groupsOf(['a', 'b', 'c'], 2)).toEqual([['a', 'b'], ['c']]);
    expect(groupsOf([], 2)).toEqual([]);
    expect(groupsOf(undefined, 2)).toEqual([]);
  });

  it('keeps the newest date per value across chunks', () => {
    let newest = mergeDates({}, [
      { fieldName: 'A', value: 'x', lastUsed: '2024-01-01T00:00:00.000Z' },
      { fieldName: 'A', value: '', lastUsed: null }
    ]);
    newest = mergeDates(newest, [
      { fieldName: 'A', value: 'x', lastUsed: '2023-06-01T00:00:00.000Z' },
      { fieldName: 'A', value: 'y', lastUsed: '2025-02-01T00:00:00.000Z' },
      { fieldName: 'A', value: '', lastUsed: '2022-01-01T00:00:00.000Z' }
    ]);
    newest = mergeDates(newest, [
      { fieldName: 'A', value: 'y', lastUsed: '2025-03-01T00:00:00.000Z' },
      { fieldName: 'B', value: null, lastUsed: '2021-01-01T00:00:00.000Z' }
    ]);
    expect(newest).toEqual({
      A: {
        x: '2024-01-01T00:00:00.000Z',
        y: '2025-03-01T00:00:00.000Z',
        '': '2022-01-01T00:00:00.000Z'
      },
      B: { '': '2021-01-01T00:00:00.000Z' }
    });
  });

  it('does not change the map it was given', () => {
    const kept = { A: { x: '2024-01-01T00:00:00.000Z' } };
    mergeDates(kept, [{ fieldName: 'A', value: 'x', lastUsed: '2025-01-01T00:00:00.000Z' }]);
    expect(kept.A.x).toBe('2024-01-01T00:00:00.000Z');
  });

  it('writes dates onto the rows of the given fields only', () => {
    const rows = [
      { fieldName: 'A', value: 'x', lastUsed: null },
      { fieldName: 'A', value: 'never', lastUsed: null },
      { fieldName: 'B', value: 'z', lastUsed: '2020-01-01T00:00:00.000Z' },
      { fieldName: 'C', value: 'q', lastUsed: null }
    ];
    const newest = { A: { x: '2024-01-01T00:00:00.000Z' }, C: { q: '2024-01-01T00:00:00.000Z' } };
    const result = applyDates(rows, newest, ['A', 'C'], ['C']);
    expect(result[0].lastUsed).toBe('2024-01-01T00:00:00.000Z');
    expect(result[1].lastUsed).toBeNull();
    expect(result[2]).toBe(rows[2]);
    expect(result[3].lastUsed).toBeNull();
  });

  it('measures progress across groups and never passes the whole', () => {
    expect(scanProgress(0, 2, 20000, 50000)).toEqual({ read: 20000, of: 100000, percent: 20 });
    expect(scanProgress(1, 2, 50000, 50000)).toEqual({ read: 100000, of: 100000, percent: 100 });
    expect(scanProgress(1, 2, 60000, 50000).read).toBe(100000);
    expect(scanProgress(0, 0, 0, 0)).toEqual({ read: 0, of: 0, percent: 0 });
  });
});
