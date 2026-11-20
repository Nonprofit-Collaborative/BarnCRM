import {
  newDocument,
  newStep,
  addStep,
  flatten,
  problems,
  pathSuggestions,
  waitMinutes,
  filled,
  STEP_KINDS
} from 'c/connectorRecipeRules';

const keys = (document) => problems(document).map((problem) => problem.key);

function withSteps(steps) {
  const document = newDocument();
  document.steps = steps;
  return document;
}

describe('c/connectorRecipeRules For Each, Wait and Change Data (CN-05)', () => {
  it('offers the three steps with their defaults showing', () => {
    const kinds = STEP_KINDS.map((kind) => kind.value);
    expect(kinds).toEqual(expect.arrayContaining(['forEach', 'wait', 'transform']));
    const document = newDocument();
    expect(newStep(document, 'forEach')).toMatchObject({ items: '', do: [] });
    expect(newStep(document, 'wait')).toMatchObject({ amount: 1, unit: 'hours' });
    expect(newStep(document, 'transform')).toMatchObject({ map: '', input: 'trigger' });
  });

  it('adds a step inside a For Each and shows it one level in', () => {
    let document = addStep(newDocument(), 'forEach');
    document = addStep(
      document,
      'stop',
      document.steps.length ? flatten(document)[0].address : null,
      'do'
    );
    const rows = flatten(document);
    expect(rows).toHaveLength(2);
    expect(rows[1]).toMatchObject({ depth: 1, branch: 'do' });
  });

  it('times a Wait from 5 minutes to 30 days in whole units', () => {
    expect(waitMinutes({ amount: 1, unit: 'hours' })).toBe(60);
    expect(waitMinutes({ amount: 30, unit: 'days' })).toBe(43200);
    expect(waitMinutes({ amount: 4, unit: 'minutes' })).toBeNull();
    expect(waitMinutes({ amount: 31, unit: 'days' })).toBeNull();
    expect(waitMinutes({ amount: 1.5, unit: 'hours' })).toBeNull();
    expect(waitMinutes({ amount: 1, unit: 'weeks' })).toBeNull();
  });

  it('asks for a list, a map and a Wait in range', () => {
    expect(keys(withSteps([{ id: 'each', kind: 'forEach', items: 'people', do: [] }]))).toEqual([
      'Connector_Recipe_ErrorItems'
    ]);
    expect(
      keys(withSteps([{ id: 'reshape', kind: 'transform', map: '', input: 'trigger' }]))
    ).toEqual(['Connector_Recipe_ErrorMap']);
    expect(keys(withSteps([{ id: 'pause', kind: 'wait', amount: 2, unit: 'minutes' }]))).toEqual([
      'Connector_Recipe_ErrorWait'
    ]);
  });

  it('refuses a Wait, For Each or Load Rows inside a For Each', () => {
    const inner = [
      { id: 'pause', kind: 'wait', amount: 1, unit: 'hours' },
      { id: 'again', kind: 'forEach', items: 'loop.item.list', do: [] },
      { id: 'load', kind: 'importRows', template: 'a0T000000000001', rows: 'loop.item.rows' }
    ];
    const found = problems(
      withSteps([{ id: 'each', kind: 'forEach', items: 'trigger.people', do: inner }])
    ).filter((problem) => problem.key === 'Connector_Recipe_ErrorInLoop');
    expect(found.map((problem) => problem.args[0])).toEqual(['pause', 'again', 'load']);
    const wait = withSteps([{ id: 'pause', kind: 'wait', amount: 1, unit: 'hours' }]);
    expect(keys(wait)).toEqual([]);
  });

  it('allows one If or For Each inside another, no deeper', () => {
    const deepest = { id: 'third', kind: 'forEach', items: 'trigger.a', do: [] };
    const middle = {
      id: 'second',
      kind: 'if',
      conditions: [{ path: 'loop.item', operator: 'is not null' }],
      then: [deepest],
      otherwise: []
    };
    const document = withSteps([
      { id: 'first', kind: 'forEach', items: 'trigger.a', do: [middle] }
    ]);
    expect(problems(document)).toEqual(
      expect.arrayContaining([{ key: 'Connector_Recipe_ErrorNesting', args: ['third'] }])
    );
  });

  it('suggests the loop item inside and the results after', () => {
    const save = { id: 'save', kind: 'upsert', map: 'a0T000000000001', input: 'loop.item' };
    const document = withSteps([
      { id: 'reshape', kind: 'transform', map: 'a0T000000000002', input: 'trigger' },
      { id: 'each', kind: 'forEach', items: 'trigger.people', do: [save] },
      { id: 'end', kind: 'stop', outcome: 'Succeeded', message: '' }
    ]);
    expect(pathSuggestions(document, save)).toEqual(
      expect.arrayContaining(['loop.item', 'loop.index', 'steps.reshape'])
    );
    const after = pathSuggestions(document, document.steps[2]);
    expect(after).toContain('steps.each.count');
    expect(after).not.toContain('loop.item');
  });
});

describe('c/connectorRecipeRules blanks an import left (CN-08)', () => {
  it('blocks Save until each blank is filled', () => {
    const step = {
      id: 'pause',
      kind: 'wait',
      amount: 1,
      unit: 'hours',
      fill: ['headers', 'connection']
    };
    expect(keys(withSteps([step]))).toEqual(['Connector_Recipe_ErrorFill']);
    const half = filled(step, 'headers');
    expect(half.fill).toEqual(['connection']);
    const done = filled(half, 'connection');
    expect(done.fill).toBeUndefined();
    expect(keys(withSteps([done]))).toEqual([]);
    expect(filled(done, 'map')).toBe(done);
  });
});
