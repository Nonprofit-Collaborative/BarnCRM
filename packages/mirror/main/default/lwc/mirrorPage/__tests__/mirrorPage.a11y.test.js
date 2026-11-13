import { createElement } from 'lwc';
import MirrorPage from 'c/mirrorPage';
import getOpportunityStatus from '@salesforce/apex/OpportunityMirrorController.getStatus';
import getGiftTransactionStatus from '@salesforce/apex/GiftTransactionMirrorController.getStatus';
import { expectAccessible } from 'barn/a11y';

jest.mock(
  '@salesforce/apex/OpportunityMirrorController.getStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
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
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.getStatus',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.runNow',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.schedule',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/GiftTransactionMirrorController.stop', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.compare',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.copyRangeAgain',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
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

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

describe('c-mirror-page accessibility', () => {
  afterEach(() => {
    document.body.replaceChildren();
    jest.clearAllMocks();
  });

  it.each(['opportunity', 'giftTransaction'])(
    'passes the accessibility checks (%s)',
    async (kind) => {
      getOpportunityStatus.mockResolvedValue(READY);
      getGiftTransactionStatus.mockResolvedValue(READY);
      const element = createElement('c-mirror-page', { is: MirrorPage });
      element.kind = kind;
      document.body.appendChild(element);
      await flush();
      await expectAccessible(element);
    }
  );
});
