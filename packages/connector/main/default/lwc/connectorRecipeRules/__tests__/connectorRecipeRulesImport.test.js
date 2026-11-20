import {
  newDocument,
  newStep,
  problems,
  pathSuggestions,
  importLimits,
  STEP_KINDS
} from 'c/connectorRecipeRules';

const keys = (document) => problems(document).map((problem) => problem.key);

function withStep(changes) {
  const document = newDocument();
  document.steps = [{ ...newStep(document, 'importRows'), ...changes }];
  return document;
}

describe('c/connectorRecipeRules Load Rows (CN-09)', () => {
  it('offers Load Rows with its defaults showing', () => {
    expect(STEP_KINDS.map((kind) => kind.value)).toContain('importRows');
    const step = newStep(newDocument(), 'importRows');
    expect(step).toMatchObject({
      id: 'importRows1',
      template: '',
      rows: 'trigger.rows',
      limits: { rows: 1000, rejected: 0, created: 1000, updated: 1000 }
    });
    expect(importLimits({ limits: { rejected: 5 } }).map((limit) => limit.value)).toEqual([
      1000, 5, 1000, 1000
    ]);
  });

  it('asks for a template, a value path and limits from 0 to 4,000', () => {
    expect(keys(withStep({}))).toEqual(['Connector_Recipe_ErrorTemplate']);
    expect(keys(withStep({ template: 'a0T000000000001', rows: 'rows' }))).toEqual([
      'Connector_Recipe_ErrorPath'
    ]);
    expect(keys(withStep({ template: 'a0T000000000001', limits: { rows: 0 } }))).toEqual([
      'Connector_Recipe_ErrorLimits'
    ]);
    expect(keys(withStep({ template: 'a0T000000000001', limits: { updated: 4001 } }))).toEqual([
      'Connector_Recipe_ErrorLimits'
    ]);
    expect(keys(withStep({ template: 'a0T000000000001', limits: {} }))).toEqual([]);
  });

  it('suggests what a later step can read from it', () => {
    const document = withStep({ id: 'load', template: 'a0T000000000001' });
    document.steps.push({ id: 'stop1', kind: 'stop', outcome: 'Succeeded', message: '' });
    expect(pathSuggestions(document, document.steps[1])).toEqual(
      expect.arrayContaining(['steps.load.batch', 'steps.load.created', 'steps.load.rejected'])
    );
  });
});
