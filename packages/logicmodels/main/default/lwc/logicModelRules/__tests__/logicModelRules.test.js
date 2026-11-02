import {
  RESULTS_SHEET_COLUMNS,
  STAGES,
  backwardLinks,
  canLink,
  columns,
  findings,
  isComputed,
  linkTargets,
  liveLinks,
  moveOrders,
  nextOrder,
  progress,
  rankOf,
  resultsSheetRows,
  samePeriodExists,
  sourceReady,
  stageOf,
  takesIndicators
} from 'c/logicModelRules';

const model = () => ({
  elements: [
    { id: 'in1', name: 'Tutors', type: 'Input', sortOrder: 10 },
    { id: 'ac1', name: 'Sessions', type: 'Activity', sortOrder: 10 },
    { id: 'ac2', name: 'Calls home', type: 'Activity', sortOrder: 20 },
    { id: 'ou1', name: 'Sessions held', type: 'Output', sortOrder: 10 },
    { id: 'oc1', name: 'Reads at home', type: 'Outcome', term: 'Short Term', sortOrder: 10 },
    { id: 'im1', name: 'Literate city', type: 'Impact', sortOrder: 10 }
  ],
  links: [
    { id: 'l1', fromId: 'in1', toId: 'ac1' },
    { id: 'l2', fromId: 'ac1', toId: 'ou1' },
    { id: 'l3', fromId: 'ou1', toId: 'oc1' },
    { id: 'l4', fromId: 'oc1', toId: 'im1' },
    { id: 'l5', fromId: 'gone', toId: 'im1' }
  ],
  indicators: [{ id: 'i1', elementId: 'oc1', periods: [] }]
});

describe('logicModelRules', () => {
  it('places each part in its column, in order', () => {
    expect(STAGES.map((stage) => stage.rank)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    expect(stageOf({ type: 'Outcome', term: 'Long Term' }).key).toBe('Outcome_Long');
    expect(stageOf({ type: 'Outcome' }).key).toBe('Outcome_Short');
    expect(stageOf(null)).toBeUndefined();
    expect(rankOf({ type: 'Nothing' })).toBe(0);
    const cols = columns(model());
    expect(cols).toHaveLength(7);
    expect(cols[1].elements.map((element) => element.id)).toEqual(['ac1', 'ac2']);
    expect(columns(undefined)[0].elements).toEqual([]);
  });

  it('allows arrows forward only and once per pair', () => {
    const m = model();
    expect(canLink(m.elements[0], m.elements[1])).toBe(true);
    expect(canLink(m.elements[1], m.elements[0])).toBe(false);
    expect(canLink(m.elements[1], m.elements[2])).toBe(false);
    expect(canLink(m.elements[0], m.elements[0])).toBe(false);
    expect(liveLinks(m)).toHaveLength(4);
    expect(linkTargets(m, 'in1').map((element) => element.id)).toEqual([
      'ac2',
      'ou1',
      'oc1',
      'im1'
    ]);
  });

  it('names the arrows a column change would turn backward', () => {
    const m = model();
    // Sessions held (output) sits between Sessions (activity) and Reads at home (short term).
    expect(backwardLinks(m, 'ou1', 'Output')).toEqual([]);
    expect(backwardLinks(m, 'ou1', 'Outcome_Short')).toEqual([
      { id: 'l3', fromName: 'Sessions held', toName: 'Reads at home' }
    ]);
    expect(backwardLinks(m, 'ou1', 'Activity')).toEqual([
      { id: 'l2', fromName: 'Sessions', toName: 'Sessions held' }
    ]);
    expect(backwardLinks(m, 'ou1', 'Impact').map((link) => link.id)).toEqual(['l3']);
    expect(backwardLinks(m, 'ac2', 'Impact')).toEqual([]);
    expect(backwardLinks(m, 'nope', 'Input')).toEqual([]);
    expect(backwardLinks(m, 'ou1', 'Nowhere')).toEqual([]);
  });

  it('measures outputs and outcomes only', () => {
    expect(takesIndicators({ type: 'Output' })).toBe(true);
    expect(takesIndicators({ type: 'Outcome', term: 'Intermediate Term' })).toBe(true);
    expect(takesIndicators({ type: 'Activity' })).toBe(false);
    expect(takesIndicators({ type: 'Impact' })).toBe(false);
  });

  it('finds what needs attention', () => {
    const codes = findings(model()).map(
      (finding) => `${finding.code}:${finding.elementId || finding.stage}`
    );
    expect(codes).toEqual(['noArrowIn:ac2', 'noArrowOut:ac2']);
    const empty = findings({ elements: [], links: [], indicators: [] }).map(
      (finding) => finding.stage
    );
    expect(empty).toEqual(['Activity', 'Output', 'Impact', 'Outcome']);
    const unmeasured = findings({ ...model(), indicators: [] });
    expect(unmeasured.some((finding) => finding.code === 'noIndicator')).toBe(true);
  });

  it('works out progress either way', () => {
    expect(progress({}, { targetValue: 10 })).toEqual({ state: 'none', percent: null });
    expect(progress({}, { targetValue: 10, resultValue: 12 })).toEqual({
      state: 'met',
      percent: 100
    });
    expect(progress({ baselineValue: 10 }, { targetValue: 30, resultValue: 20 })).toEqual({
      state: 'partial',
      percent: 50
    });
    expect(progress({ betterWhen: 'Lower' }, { targetValue: 5, resultValue: 4 }).state).toBe('met');
    expect(
      progress({ betterWhen: 'Lower', baselineValue: 20 }, { targetValue: 10, resultValue: 15 })
    ).toEqual({
      state: 'partial',
      percent: 50
    });
    expect(progress({ baselineValue: 30 }, { targetValue: 30, resultValue: 'x' }).state).toBe(
      'none'
    );
    expect(progress({ baselineValue: 40 }, { targetValue: 30, resultValue: 20 }).percent).toBe(0);
  });

  it('spots a period with the same dates', () => {
    const indicator = { periods: [{ id: 'p1', startDate: '2026-01-01', endDate: '2026-03-31' }] };
    expect(samePeriodExists(indicator, { startDate: '2026-01-01', endDate: '2026-03-31' })).toBe(
      true
    );
    expect(
      samePeriodExists(indicator, { id: 'p1', startDate: '2026-01-01', endDate: '2026-03-31' })
    ).toBe(false);
    expect(samePeriodExists(undefined, { startDate: 'a', endDate: 'b' })).toBe(false);
  });

  it('renumbers a column when a part moves', () => {
    expect(moveOrders(model(), 'ac2', -1)).toEqual([
      { id: 'ac2', sortOrder: 10 },
      { id: 'ac1', sortOrder: 20 }
    ]);
    expect(moveOrders(model(), 'ac1', -1)).toEqual([]);
    expect(moveOrders(model(), 'nope', 1)).toEqual([]);
    expect(nextOrder(model(), 'Activity')).toBe(30);
    expect(nextOrder(model(), 'Outcome_Long')).toBe(10);
  });

  it('decides when a source can be saved', () => {
    expect(sourceReady({ source: 'Manual' })).toBe(true);
    expect(sourceReady({ source: 'Import' })).toBe(true);
    expect(sourceReady({ source: 'Guessed' })).toBe(false);
    expect(sourceReady(undefined)).toBe(false);
    const computed = { source: 'Computed', queryId: 'q1', dateField: 'D__c', function: 'count' };
    expect(sourceReady(computed)).toBe(true);
    expect(sourceReady({ ...computed, queryId: null })).toBe(false);
    expect(sourceReady({ ...computed, dateField: '' })).toBe(false);
    expect(sourceReady({ ...computed, function: 'median' })).toBe(false);
    expect(sourceReady({ ...computed, function: 'sum' })).toBe(false);
    expect(sourceReady({ ...computed, function: 'sum', field: 'Hours__c' })).toBe(true);
    expect(sourceReady({ ...computed, function: 'unique', field: 'Contact__c' })).toBe(true);
    expect(isComputed({ source: 'Computed' })).toBe(true);
    expect(isComputed({ source: 'Import' })).toBe(false);
    expect(isComputed(undefined)).toBe(false);
  });

  it('writes the results sheet for every period not computed, in column order', () => {
    const sheet = {
      ...model(),
      name: 'Reading Model',
      indicators: [
        {
          id: 'i2',
          elementId: 'oc1',
          name: 'Reading daily',
          unit: 'students',
          source: 'Import',
          periods: [
            {
              id: 'p3',
              name: 'Q1',
              startDate: '2026-01-01',
              endDate: '2026-03-31',
              targetValue: 30,
              resultValue: null,
              notes: null
            }
          ]
        },
        {
          id: 'i1',
          elementId: 'ou1',
          name: 'Sessions',
          source: 'Manual',
          periods: [{ id: 'p1', name: 'Q1', startDate: '2026-01-01', endDate: '2026-03-31' }]
        },
        {
          id: 'i3',
          elementId: 'ou1',
          name: 'Counted',
          source: 'Computed',
          periods: [{ id: 'p9', name: 'Q1' }]
        }
      ]
    };
    const rows = resultsSheetRows(sheet);
    expect(rows.map((row) => row.periodId)).toEqual(['p1', 'p3']);
    expect(rows[1]).toMatchObject({
      model: 'Reading Model',
      part: 'Reads at home',
      indicator: 'Reading daily',
      unit: 'students',
      period: 'Q1',
      target: 30
    });
    expect(RESULTS_SHEET_COLUMNS.map((column) => column.label)).toEqual(
      expect.arrayContaining(['Period Id', 'Target', 'Result', 'Notes'])
    );
    expect(resultsSheetRows(undefined)).toEqual([]);
  });
});
