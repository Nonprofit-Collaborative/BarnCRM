import { createElement } from 'lwc';
import GiftTransactionMirror from 'c/giftTransactionMirror';
import getStatus from '@salesforce/apex/GiftTransactionMirrorController.getStatus';
import runNow from '@salesforce/apex/GiftTransactionMirrorController.runNow';
import compare from '@salesforce/apex/GiftTransactionMirrorController.compare';
import copyRangeAgain from '@salesforce/apex/GiftTransactionMirrorController.copyRangeAgain';
import { differenceTextOf, fill, isoDate, rowsOf, viewOf } from '../mirrorView';

jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.getStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.runNow',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.schedule',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/GiftTransactionMirrorController.stop', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.compare',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.copyRangeAgain',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Mirror_GiftTransactionMirror_DirectionGifts',
  () => ({
    default:
      'Direction: Gifts to Gift Transactions. Received gifts dated on or after {0} get a matching Gift Transaction with status {1}.'
  }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Mirror_GiftTransactionMirror_GiftTransactionSide',
  () => ({ default: 'Paid Gift Transactions: {0}, total {1}' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Mirror_OpportunityMirror_DifferenceCountAll',
  () => ({ default: 'Differences found: {0}. All are listed.' }),
  { virtual: true }
);

const READY = {
  available: true,
  direction: 'GiftsToGiftTransactions',
  paidStatus: 'Paid',
  startDate: '2026-01-01',
  notReadyReason: null,
  canRun: true,
  canManage: true,
  running: false,
  nextRunAt: null
};

const COMPARISON = {
  giftCount: 2,
  giftTotal: 150,
  giftTransactionCount: 1,
  giftTransactionTotal: 100,
  differenceCount: 1,
  differences: [
    {
      key: 'a01',
      giftId: 'a01',
      giftName: 'G-000001',
      giftAmount: 50,
      reason: 'No Gift Transaction'
    }
  ]
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function mount(status) {
  getStatus.mockResolvedValue(status);
  const element = createElement('c-gift-transaction-mirror', { is: GiftTransactionMirror });
  document.body.appendChild(element);
  await flush();
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-gift-transaction-mirror', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('names the start date and paid status, and offers Run Now and Schedule Nightly Run', async () => {
    const element = await mount(READY);
    expect(find(element, 'direction').textContent).toBe(
      'Direction: Gifts to Gift Transactions. Received gifts dated on or after Jan 1, 2026 get a matching Gift Transaction with status Paid.'
    );
    expect(find(element, 'run-now').disabled).toBe(false);
    expect(find(element, 'schedule-nightly').disabled).toBe(false);
  });

  it('says so, and offers nothing, where the org has no Gift Transactions', async () => {
    const element = await mount({ ...READY, available: false });
    expect(find(element, 'unavailable')).not.toBeNull();
    expect(find(element, 'run-now')).toBeNull();
    expect(find(element, 'compare')).toBeNull();
  });

  it('shows why nothing is copied yet and keeps the buttons off', async () => {
    const element = await mount({ ...READY, notReadyReason: 'Set a start date.' });
    expect(find(element, 'not-ready').textContent).toBe('Set a start date.');
    expect(find(element, 'direction')).toBeNull();
    expect(find(element, 'run-now').disabled).toBe(true);
  });

  it('points at the setting while the mirror is off, and still compares', async () => {
    const element = await mount({ ...READY, direction: 'Off' });
    expect(find(element, 'off')).not.toBeNull();
    expect(find(element, 'compare')).not.toBeNull();
  });

  it('starts a run and says it has started', async () => {
    runNow.mockResolvedValue({ ...READY, running: true });
    const element = await mount(READY);
    find(element, 'run-now').click();
    await flush();
    expect(runNow).toHaveBeenCalled();
    expect(find(element, 'running')).not.toBeNull();
    expect(find(element, 'run-now').disabled).toBe(true);
  });

  it('shows a refusal in the words the controller gives', async () => {
    runNow.mockRejectedValue({ body: { message: 'A run is already in progress.' } });
    const element = await mount(READY);
    find(element, 'run-now').click();
    await flush();
    expect(find(element, 'error').textContent).toBe('A run is already in progress.');
  });

  it('compares a range and copies those gifts again', async () => {
    compare.mockResolvedValue(COMPARISON);
    copyRangeAgain.mockResolvedValue({ ...READY, running: true });
    const element = await mount(READY);
    find(element, 'compare').click();
    await flush();
    expect(find(element, 'gift-transaction-side').textContent).toBe(
      'Paid Gift Transactions: 1, total $100.00'
    );
    expect(find(element, 'difference-count').textContent).toBe(
      'Differences found: 1. All are listed.'
    );
    find(element, 'copy-again').click();
    await flush();
    expect(copyRangeAgain).toHaveBeenCalledWith(
      expect.objectContaining({ fromDate: expect.any(String), toDate: expect.any(String) })
    );
  });

  it('shows a refusal from the comparison', async () => {
    compare.mockRejectedValue({ body: { message: 'Choose a shorter range.' } });
    const element = await mount(READY);
    find(element, 'compare').click();
    await flush();
    expect(find(element, 'error').textContent).toBe('Choose a shorter range.');
  });
});

describe('mirrorView', () => {
  it('fills every placeholder, repeated ones too', () => {
    expect(fill('{0} and {0}, {1}', 'a', 2)).toBe('a and a, 2');
    expect(isoDate(new Date(2026, 0, 5))).toBe('2026-01-05');
  });

  it('works out what shows from a status', () => {
    expect(viewOf(undefined, false).loaded).toBe(false);
    const view = viewOf({ ...READY, canManage: false }, false);
    expect(view.noManageShown).toBe(true);
    expect(view.runDisabled).toBe(true);
    expect(viewOf({ ...READY, canRun: false }, false).noAccessShown).toBe(true);
    expect(viewOf({ ...READY, running: true }, false).runDisabled).toBe(true);
    expect(viewOf(READY, true).scheduleDisabled).toBe(true);
  });

  it('counts and lists differences', () => {
    const labels = {
      noDifferences: 'None',
      differenceCount: '{0} of {1}',
      differenceCountAll: 'All {0}'
    };
    expect(differenceTextOf(undefined, labels)).toBe('None');
    expect(differenceTextOf({ differenceCount: 3, differences: [{}] }, labels)).toBe('3 of 1');
    const [row] = rowsOf({ differences: [{ giftTransactionId: '6gt' }] });
    expect(row.giftTransactionUrl).toBe('/6gt');
    expect(row.giftTransactionLabel).toBe('6gt');
    expect(rowsOf(undefined)).toEqual([]);
  });
});
