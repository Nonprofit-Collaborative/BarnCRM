import { createElement } from 'lwc';
import { clearHelpTextForTest, setHelpTextForTest } from 'c/barnHelpText';
import RecurringDonorHealth from 'c/recurringDonorHealth';
import getPage from '@salesforce/apex/RecurringHealthController.getPage';
import createFollowUp from '@salesforce/apex/RecurringHealthController.createFollowUp';

jest.mock('@salesforce/apex/RecurringHealthController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/RecurringHealthController.createFollowUp',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const PAGE = {
  expiryDays: 60,
  unmatched: 2,
  byFrequency: [{ frequency: 'Monthly', total: 75, count: 3 }],
  months: [],
  rows: [
    {
      id: 'a05000000000001AAA',
      name: 'CM-000001',
      donorName: 'Rae Sustainer',
      amount: 25,
      frequency: 'Monthly',
      failedCharges: 2,
      lastFailedCharge: '2026-11-01'
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount() {
  const element = createElement('c-recurring-donor-health', { is: RecurringDonorHealth });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-recurring-donor-health', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the revenue, the unmatched events and the gift at risk', async () => {
    getPage.mockResolvedValue(PAGE);
    const element = mount();
    await flush();

    expect(find(element, 'active').textContent).toBe('3');
    expect(find(element, 'unmatched')).not.toBeNull();
    const items = element.shadowRoot.querySelectorAll('[data-id="save-list"] li');
    expect(items).toHaveLength(1);
    expect(items[0].textContent).toContain('Rae Sustainer');
    expect(element.shadowRoot.querySelectorAll('[data-id="months"] li')).toHaveLength(12);
  });

  it('creates a follow-up task for the row', async () => {
    getPage.mockResolvedValue(PAGE);
    createFollowUp.mockResolvedValue('00T000000000001AAA');
    const element = mount();
    await flush();

    find(element, 'follow-up').click();
    await flush();

    expect(createFollowUp).toHaveBeenCalledWith({ commitmentId: 'a05000000000001AAA' });
  });

  it('says so when nothing is at risk, and shows a failure where the person sees it', async () => {
    getPage.mockResolvedValue({ ...PAGE, rows: [], unmatched: 0 });
    let element = mount();
    await flush();
    expect(find(element, 'no-rows')).not.toBeNull();
    expect(find(element, 'unmatched')).toBeNull();

    document.body.removeChild(element);
    getPage.mockRejectedValue({ body: { message: 'Nope' } });
    element = mount();
    await flush();
    expect(find(element, 'error-message')).not.toBeNull();
  });

  it('shows a capped unmatched count with a plus', async () => {
    setHelpTextForTest({ Giving_RecurringHealth_Unmatched: '{0} unmatched' });
    getPage.mockResolvedValue({ ...PAGE, unmatched: 10000 });
    const element = mount();
    await flush();
    expect(find(element, 'unmatched').message).toBe(`${(10000).toLocaleString()}+ unmatched`);
    clearHelpTextForTest();
  });
});
