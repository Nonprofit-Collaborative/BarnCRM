import { TASKS, matchTasks, wordsOf } from 'c/dataManagerTasks';

const ALL = ['import', 'files', 'find', 'backup', 'update', 'optimizer', 'duplicates', 'delete'];

describe('c/dataManagerTasks', () => {
  it('names a Data Manager tile for every task', () => {
    TASKS.forEach((task) => {
      expect(ALL).toContain(task.tool);
      expect(task.text.length).toBeGreaterThan(0);
    });
  });

  it('drops filler words, punctuation and a plural s', () => {
    expect(wordsOf('I want to import my Donors, please')).toEqual(['import', 'donor', 'please']);
    expect(wordsOf('address')).toEqual(['address']);
  });

  it.each([
    ['fix capital letters in names', 'update', 'Fix capital letters in names'],
    ['delete test records', 'delete', 'Delete test records'],
    ['merge two households', 'duplicates', 'Merge two households'],
    ['import donors', 'import', 'Import donors and their gifts'],
    ['find people without email', 'find', 'Find people without email'],
    ['export to excel', 'find', 'Export records to a spreadsheet']
  ])('puts the right task first for "%s"', (query, tool, text) => {
    const [first] = matchTasks(query, ALL);
    expect(first).toEqual(expect.objectContaining({ tool, text }));
  });

  it('matches a half-typed word', () => {
    expect(matchTasks('dupl', ALL)[0].tool).toBe('duplicates');
  });

  it('lists only tools the person may open', () => {
    const results = matchTasks('delete test records', ['find']);
    expect(results.every((result) => result.tool === 'find')).toBe(true);
    expect(results.some((result) => result.tool === 'delete')).toBe(false);
  });

  it('returns nothing for an empty box, filler words or words no task uses', () => {
    expect(matchTasks('', ALL)).toEqual([]);
    expect(matchTasks('how do I', ALL)).toEqual([]);
    expect(matchTasks('zebra', ALL)).toEqual([]);
    expect(matchTasks('import', undefined)).toEqual([]);
  });

  it('shows at most five tasks, each with its own key', () => {
    const results = matchTasks('records', ALL);
    expect(results.length).toBeLessThanOrEqual(5);
    expect(new Set(results.map((result) => result.key)).size).toBe(results.length);
  });
});
