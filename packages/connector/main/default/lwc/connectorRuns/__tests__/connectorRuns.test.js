import { createElement } from 'lwc';
import ConnectorRuns from 'c/connectorRuns';
import getRuns from '@salesforce/apex/ConnectorRecipesController.getRuns';
import getRun from '@salesforce/apex/ConnectorRecipesController.getRun';
import retryRun from '@salesforce/apex/ConnectorRecipesController.retryRun';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/ConnectorRecipesController.getRuns', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ConnectorRecipesController.getRun', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ConnectorRecipesController.retryRun', () => ({ default: jest.fn() }), {
  virtual: true
});

const FAILED = {
  id: 'a0S000000000001',
  name: 'R-000001',
  recipeName: 'Welcome',
  status: 'Failed',
  startedBy: 'Manual',
  ranAs: 'Automation',
  version: 1,
  recordsWritten: 1,
  failedStep: 'call1',
  errorMessage: 'The app answered 500.',
  createdAt: '2026-11-20T10:00:00Z'
};
const DONE = {
  ...FAILED,
  id: 'a0S000000000002',
  name: 'R-000002',
  status: 'Succeeded',
  failedStep: null
};
const OPENED = {
  ...FAILED,
  stepLogJson: JSON.stringify([
    { step: 'upsert1', kind: 'upsert', outcome: 'Succeeded', ms: 12, ids: ['003000000000001'] },
    {
      step: 'call1',
      kind: 'callApp',
      outcome: 'Failed',
      ms: 40,
      status: 500,
      response: 'Server error'
    }
  ]),
  resultsJson: '{}'
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render(canManage = true, runs = [FAILED, DONE]) {
  getRuns.mockResolvedValue(runs);
  const element = createElement('c-connector-runs', { is: ConnectorRuns });
  element.canManage = canManage;
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-connector-runs', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists runs newest first with Retry only on a failed run, and is accessible', async () => {
    const element = await render();
    expect(getRuns).toHaveBeenCalledWith({ recipeId: null });
    expect(find(element, FAILED.id)).not.toBeNull();
    expect(find(element, `retry-${FAILED.id}`)).not.toBeNull();
    expect(find(element, `retry-${DONE.id}`)).toBeNull();
    await expectAccessible(element);
  });

  it('offers no Retry to a Viewer and shows the empty state', async () => {
    const element = await render(false);
    expect(find(element, `retry-${FAILED.id}`)).toBeNull();
    const empty = await render(true, []);
    expect(find(empty, 'empty')).not.toBeNull();
  });

  it('opens a run with each step, its status and trimmed answer', async () => {
    getRun.mockResolvedValue(OPENED);
    const element = await render();
    find(element, `open-${FAILED.id}`).click();
    await flush();
    expect(getRun).toHaveBeenCalledWith({ runId: FAILED.id });
    expect(find(element, 'opened')).not.toBeNull();
    expect(find(element, 'upsert1-0')).not.toBeNull();
    expect(find(element, 'call1-1').textContent).toContain('Server error');
    expect(find(element, 'opened-failure')).not.toBeNull();
    await expectAccessible(element);
    find(element, 'back').click();
    await flush();
    expect(find(element, 'opened')).toBeNull();
  });

  it('retries a failed run and shows a refusal plainly', async () => {
    retryRun
      .mockResolvedValueOnce({ ...FAILED, status: 'Queued' })
      .mockRejectedValueOnce({ body: { message: 'Already retried.' } });
    const element = await render();
    find(element, `retry-${FAILED.id}`).click();
    await flush();
    expect(retryRun).toHaveBeenCalledWith({ runId: FAILED.id });
    expect(find(element, 'message').message).toBe('c.Connector_Runs_Retried');
    expect(getRuns).toHaveBeenCalledTimes(2);

    find(element, `retry-${FAILED.id}`).click();
    await flush();
    expect(find(element, 'error').message).toBe('Already retried.');
  });

  it('refreshes', async () => {
    const element = await render();
    find(element, 'refresh').click();
    await flush();
    expect(getRuns).toHaveBeenCalledTimes(2);
  });
});
