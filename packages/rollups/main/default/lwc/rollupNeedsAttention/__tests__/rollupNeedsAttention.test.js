import { createElement } from 'lwc';
import RollupNeedsAttention from 'c/rollupNeedsAttention';
import getAttention from '@salesforce/apex/RollupAttentionController.getAttention';
import retry from '@salesforce/apex/RollupAttentionController.retry';
import processNow from '@salesforce/apex/RollupAttentionController.processNow';

jest.mock(
  '@salesforce/apex/RollupAttentionController.getAttention',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/RollupAttentionController.retry', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RollupAttentionController.processNow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_RollupBuilder_Started', () => ({ default: 'Started.' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_RollupBuilder_Retried',
  () => ({ default: 'Back in the queue.' }),
  { virtual: true }
);

const ROW = {
  key: 'a0Q1a01',
  entryId: 'a0Q000000000001AAA',
  recordId: '001000000000001AAA',
  name: 'Rivera Household',
  error: 'A validation rule refused it.',
  failedAt: '2026-10-12T02:30:00.000Z',
  attempts: 5
};

const ATTENTION = {
  canManage: true,
  waiting: '1,204 records waiting, oldest 3 minutes ago.',
  failed: [ROW, { ...ROW, key: 'a0Q1a02', recordId: '001000000000002AAA', name: 'Chen' }],
  nightlyScheduled: false,
  lastRun: 'Last full run: Completed.'
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function build(attention) {
  getAttention.mockResolvedValue(attention);
  const element = createElement('c-rollup-needs-attention', { is: RollupNeedsAttention });
  document.body.appendChild(element);
  await flush();
  return element;
}

const query = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-rollup-needs-attention', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows what is waiting, each failed record with a link, and the nightly warning', async () => {
    const element = await build(ATTENTION);

    expect(query(element, 'waiting').textContent).toBe(ATTENTION.waiting);
    expect(query(element, 'nightly-off')).not.toBeNull();
    expect(query(element, 'last-run').textContent).toBe(ATTENTION.lastRun);
    const table = query(element, 'failed');
    expect(table.data.map((row) => row.link)).toEqual([
      '/001000000000001AAA',
      '/001000000000002AAA'
    ]);
  });

  it('retries the entries of the selected records once each', async () => {
    retry.mockResolvedValue({ ...ATTENTION, failed: [] });
    const element = await build(ATTENTION);

    query(element, 'failed').dispatchEvent(
      new CustomEvent('rowselection', { detail: { selectedRows: ATTENTION.failed } })
    );
    await flush();
    query(element, 'retry').click();
    await flush();

    expect(retry).toHaveBeenCalledWith({ entryIds: ['a0Q000000000001AAA'] });
    expect(query(element, 'notice').textContent).toBe('Back in the queue.');
    expect(query(element, 'nothing-failed')).not.toBeNull();
  });

  it('retries all, and offers no Retry to someone who cannot manage settings', async () => {
    retry.mockResolvedValue(ATTENTION);
    const element = await build(ATTENTION);
    query(element, 'retry-all').click();
    await flush();
    expect(retry).toHaveBeenCalledWith({ entryIds: null });

    const readOnly = await build({ ...ATTENTION, canManage: false, nightlyScheduled: true });
    expect(query(readOnly, 'retry-all')).toBeNull();
    expect(query(readOnly, 'nightly-off')).toBeNull();
  });

  it('starts the waiting records now, and offers Start now only when some wait', async () => {
    processNow.mockResolvedValue({ ...ATTENTION, hasWaiting: false });
    const element = await build({ ...ATTENTION, hasWaiting: true });

    query(element, 'start-now').click();
    await flush();

    expect(processNow).toHaveBeenCalledTimes(1);
    expect(query(element, 'notice').textContent).toBe('Started.');
    expect(query(element, 'start-now')).toBeNull();

    const readOnly = await build({ ...ATTENTION, hasWaiting: true, canManage: false });
    expect(query(readOnly, 'start-now')).toBeNull();
  });
});
