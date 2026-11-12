import {
  hasActiveRule,
  kindOptions,
  kindsOverLimit,
  parseSummary,
  runRows
} from 'c/territoryModel';

const territories = [
  {
    active: true,
    rules: [
      { active: true, appliesTo: 'People' },
      { active: true, appliesTo: 'People' },
      { active: false, appliesTo: 'Households' }
    ]
  },
  { active: false, rules: [{ active: true, appliesTo: 'Households' }] }
];

describe('territoryModel', () => {
  it('offers the three kinds in run order', () => {
    expect(kindOptions().map((option) => option.value)).toEqual([
      'People',
      'Households',
      'Organizations'
    ]);
  });

  it('counts active rules of active territories against the limit', () => {
    expect(kindsOverLimit(territories, 1)).toEqual(['People']);
    expect(kindsOverLimit(territories, 2)).toEqual([]);
    expect(hasActiveRule(territories)).toBe(true);
    expect(hasActiveRule([territories[1]])).toBe(false);
  });

  it('reads a run summary, and an unreadable one as empty', () => {
    expect(
      parseSummary('{"territories":[{"name":"North","changes":2}],"sample":[]}').territories
    ).toHaveLength(1);
    expect(parseSummary('not json')).toEqual({ territories: [], sample: [] });
    const rows = runRows([{ id: 'r1', mode: 'Assign', status: 'Running', summaryJson: null }]);
    expect(rows[0]).toEqual(expect.objectContaining({ key: 'r1', isAssign: true, busy: true }));
  });
});
