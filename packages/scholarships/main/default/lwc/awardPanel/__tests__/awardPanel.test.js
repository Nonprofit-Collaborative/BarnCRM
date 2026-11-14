import { createElement } from 'lwc';
import AwardPanel from 'c/awardPanel';
import getAward from '@salesforce/apex/ScholarshipsController.getAward';
import makeLetter from '@salesforce/apex/ScholarshipsController.makeLetter';
import buildSchedule from '@salesforce/apex/ScholarshipsController.buildSchedule';
import markPaid from '@salesforce/apex/ScholarshipsController.markPaid';
import setRequirement from '@salesforce/apex/ScholarshipsController.setRequirement';

jest.mock('@salesforce/apex/ScholarshipsController.getAward', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ScholarshipsController.makeLetter', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ScholarshipsController.respond', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ScholarshipsController.buildSchedule', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ScholarshipsController.markPaid', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ScholarshipsController.setRequirement',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/ScholarshipsController.startRenewal', () => ({ default: jest.fn() }), {
  virtual: true
});

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

const PANEL = {
  canManage: true,
  payments: [
    { id: 'a01000000000001AAA', name: 'DSB-1', amount: 500, status: 'Scheduled', held: true },
    { id: 'a01000000000002AAA', name: 'DSB-2', amount: 500, status: 'Scheduled', held: false }
  ],
  requirements: [
    { id: 'a02000000000001AAA', name: 'Enrollment', type: 'Condition', status: 'Open' }
  ]
};

function mount() {
  const element = createElement('c-award-panel', { is: AwardPanel });
  element.recordId = 'a03000000000001AAA';
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-award-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('holds back a payment, pays the other, releases a condition', async () => {
    getAward.mockResolvedValue(PANEL);
    markPaid.mockResolvedValue();
    setRequirement.mockResolvedValue();
    makeLetter.mockResolvedValue('069000000000001AAA');
    const element = mount();
    await flush();
    expect(find(element, 'held')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="mark-paid"]')).toHaveLength(1);
    find(element, 'mark-paid').click();
    await flush();
    find(element, 'save-paid').click();
    await flush();
    expect(markPaid).toHaveBeenCalledWith(
      expect.objectContaining({ paymentId: 'a01000000000002AAA', method: 'Check' })
    );
    find(element, 'met').click();
    await flush();
    expect(setRequirement).toHaveBeenCalledWith({
      requirementId: 'a02000000000001AAA',
      status: 'Met'
    });
    find(element, 'letter').click();
    await flush();
    expect(makeLetter).toHaveBeenCalled();
  });

  it('starts the paid date on the local day, not the UTC day', async () => {
    jest.useFakeTimers({
      now: new Date(2026, 10, 12, 23, 30),
      doNotFake: ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval', 'setImmediate']
    });
    try {
      getAward.mockResolvedValue(PANEL);
      markPaid.mockResolvedValue();
      const element = mount();
      await flush();
      find(element, 'mark-paid').click();
      await flush();
      find(element, 'save-paid').click();
      await flush();
      expect(markPaid).toHaveBeenCalledWith(expect.objectContaining({ paidOn: '2026-11-12' }));
    } finally {
      jest.useRealTimers();
    }
  });

  it('builds a schedule and shows a refusal', async () => {
    getAward.mockResolvedValue({ ...PANEL, canManage: false });
    buildSchedule.mockRejectedValue({ body: { message: 'Nothing left to schedule' } });
    const element = mount();
    await flush();
    expect(find(element, 'waive')).toBeNull();
    find(element, 'schedule').click();
    await flush();
    find(element, 'save-schedule').click();
    await flush();
    await flush();
    expect(buildSchedule).toHaveBeenCalledWith(
      expect.objectContaining({ count: 2, monthsApart: 6 })
    );
    expect(find(element, 'error-message').message).toBe('Nothing left to schedule');
  });
});
