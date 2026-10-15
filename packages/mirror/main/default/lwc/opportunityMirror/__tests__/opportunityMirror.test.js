import { createElement } from 'lwc';
import OpportunityMirror from 'c/opportunityMirror';
import getStatus from '@salesforce/apex/OpportunityMirrorController.getStatus';
import runNow from '@salesforce/apex/OpportunityMirrorController.runNow';
import compare from '@salesforce/apex/OpportunityMirrorController.compare';
import copyRangeAgain from '@salesforce/apex/OpportunityMirrorController.copyRangeAgain';

jest.mock(
  '@salesforce/apex/OpportunityMirrorController.getStatus',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/OpportunityMirrorController.runNow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/OpportunityMirrorController.schedule', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/OpportunityMirrorController.stop', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/OpportunityMirrorController.compare', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/OpportunityMirrorController.copyRangeAgain',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Mirror_OpportunityMirror_DirectionOpportunities',
  () => ({ default: 'Won Opportunities closed on or after {0} become gifts.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Mirror_OpportunityMirror_GiftSide',
  () => ({ default: 'Gifts: {0}, total {1}' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Mirror_OpportunityMirror_DifferenceCount',
  () => ({ default: 'Differences found: {0}. The first {1} are listed.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Mirror_OpportunityMirror_DifferenceCountAll',
  () => ({ default: 'Differences found: {0}. All are listed.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Mirror_OpportunityMirror_LastRun',
  () => ({ default: 'Last completed run: started {0}. {1}' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Mirror_OpportunityMirror_ErrorFailed',
  () => ({ default: 'Something went wrong.' }),
  { virtual: true }
);

const READY = {
  available: true,
  direction: 'GiftsToOpportunities',
  startDate: null,
  canRun: true,
  canManage: true,
  running: false,
  nextRunAt: null
};

const COMPARISON = {
  giftCount: 4,
  giftTotal: 175,
  opportunityCount: 3,
  opportunityTotal: 275,
  differenceCount: 1,
  differences: [
    {
      key: 'a01',
      giftId: 'a01',
      giftName: 'G-0001',
      giftAmount: 100,
      opportunityId: '006',
      opportunityName: 'Luis gift',
      opportunityAmount: 175,
      reason: 'Amount differs'
    }
  ]
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function mount(status) {
  getStatus.mockResolvedValue(status);
  const element = createElement('c-opportunity-mirror', { is: OpportunityMirror });
  document.body.appendChild(element);
  await flush();
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-opportunity-mirror', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the direction and offers Run now and Schedule nightly', async () => {
    const element = await mount(READY);
    expect(find(element, 'direction')).not.toBeNull();
    expect(find(element, 'run-now').disabled).toBe(false);
    expect(find(element, 'schedule-nightly')).not.toBeNull();
    expect(find(element, 'stop')).toBeNull();
  });

  it('offers Stop once the nightly run is scheduled', async () => {
    const element = await mount({ ...READY, nextRunAt: '2026-09-26T01:30:00.000Z' });
    expect(find(element, 'stop')).not.toBeNull();
    expect(find(element, 'schedule-nightly')).toBeNull();
  });

  it('says so, and offers nothing, where the org has no Opportunities', async () => {
    const element = await mount({ ...READY, available: false });
    expect(find(element, 'unavailable')).not.toBeNull();
    expect(find(element, 'run-now')).toBeNull();
    expect(find(element, 'compare')).toBeNull();
  });

  it('points at the setting while the mirror is off, and still compares', async () => {
    const element = await mount({ ...READY, direction: 'Off' });
    expect(find(element, 'off')).not.toBeNull();
    expect(find(element, 'run-now')).toBeNull();
    expect(find(element, 'compare')).not.toBeNull();
  });

  it('names the start date in Opportunities to Gifts', async () => {
    const element = await mount({
      ...READY,
      direction: 'OpportunitiesToGifts',
      startDate: '2026-01-01'
    });
    expect(find(element, 'direction').textContent).toBe(
      'Won Opportunities closed on or after Jan 1, 2026 become gifts.'
    );
  });

  it('keeps the buttons off for someone who cannot manage settings', async () => {
    const element = await mount({ ...READY, canManage: false });
    expect(find(element, 'no-manage')).not.toBeNull();
    expect(find(element, 'run-now').disabled).toBe(true);
    expect(find(element, 'schedule-nightly').disabled).toBe(true);
  });

  it('explains why the buttons are off for someone without Opportunity access', async () => {
    const element = await mount({ ...READY, canRun: false });
    expect(find(element, 'no-access')).not.toBeNull();
    expect(find(element, 'run-now').disabled).toBe(true);
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

  it('compares a range, lists the differences and offers to copy them again', async () => {
    compare.mockResolvedValue(COMPARISON);
    copyRangeAgain.mockResolvedValue({ ...READY, running: true });
    const element = await mount(READY);
    find(element, 'compare').click();
    await flush();
    expect(compare).toHaveBeenCalledWith(
      expect.objectContaining({ fromDate: expect.any(String), toDate: expect.any(String) })
    );
    expect(find(element, 'gift-side').textContent).toBe('Gifts: 4, total $175.00');
    expect(find(element, 'difference-count').textContent).toBe(
      'Differences found: 1. All are listed.'
    );
    expect(find(element, 'differences').data[0].giftUrl).toBe('/a01');
    const compared = compare.mock.calls[0][0];
    const from = find(element, 'from');
    from.value = '2020-01-01';
    from.dispatchEvent(new CustomEvent('change'));
    await flush();
    find(element, 'copy-again').click();
    await flush();
    expect(copyRangeAgain).toHaveBeenCalledWith(compared);
  });

  it('says when only the first differences are listed', async () => {
    compare.mockResolvedValue({ ...COMPARISON, differenceCount: 3 });
    const element = await mount(READY);
    find(element, 'compare').click();
    await flush();
    expect(find(element, 'difference-count').textContent).toBe(
      'Differences found: 3. The first 1 are listed.'
    );
  });

  it('shows the last completed run and its summary', async () => {
    const element = await mount({
      ...READY,
      lastRunAt: '2026-09-24T08:30:00.000Z',
      lastSummary: '3 Opportunities created.'
    });
    expect(find(element, 'last-run').textContent).toContain('3 Opportunities created.');
  });

  it('shows a spinner until the status arrives', async () => {
    getStatus.mockReturnValue(new Promise(() => {}));
    const element = createElement('c-opportunity-mirror', { is: OpportunityMirror });
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'spinner')).not.toBeNull();
  });

  it('checks again until a running run has finished', async () => {
    jest.useFakeTimers();
    try {
      const element = await mount({ ...READY, running: true });
      expect(find(element, 'running')).not.toBeNull();
      getStatus.mockResolvedValue(READY);
      jest.advanceTimersByTime(10000);
      await flush();
      expect(getStatus).toHaveBeenCalledTimes(2);
      expect(find(element, 'running')).toBeNull();
    } finally {
      jest.useRealTimers();
    }
  });

  it('does not offer to copy again in Opportunities to Gifts', async () => {
    compare.mockResolvedValue(COMPARISON);
    const element = await mount({
      ...READY,
      direction: 'OpportunitiesToGifts',
      startDate: '2026-01-01'
    });
    find(element, 'compare').click();
    await flush();
    expect(find(element, 'differences')).not.toBeNull();
    expect(find(element, 'copy-again')).toBeNull();
  });

  it('falls back to a plain message when a failure has none', async () => {
    getStatus.mockRejectedValue(new Error('boom'));
    const element = createElement('c-opportunity-mirror', { is: OpportunityMirror });
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'error').textContent).toBe('Something went wrong.');
  });
});
