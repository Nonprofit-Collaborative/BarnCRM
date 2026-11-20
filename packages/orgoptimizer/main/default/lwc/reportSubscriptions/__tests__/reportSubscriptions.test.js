import { createElement } from 'lwc';
import ReportSubscriptions from 'c/reportSubscriptions';
import getView from '@salesforce/apex/ReportSubscriptions.getView';
import subscribe from '@salesforce/apex/ReportSubscriptions.subscribe';
import check from '@salesforce/apex/ReportSubscriptions.check';

jest.mock('@salesforce/apex/ReportSubscriptions.getView', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportSubscriptions.subscribe', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportSubscriptions.check', () => ({ default: jest.fn() }), {
  virtual: true
});

const VIEW = {
  canSubscribe: true,
  canUseConnection: true,
  connected: true,
  reports: [
    {
      id: '00O000000000001AAA',
      name: 'LYBUNT Donors',
      folder: 'BarnCRM Giving',
      description: 'Gave last year'
    },
    { id: '00O000000000002AAA', name: 'Errors by Day', folder: 'BarnCRM Admin' }
  ]
};

async function flush() {
  for (let i = 0; i < 6; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

function render() {
  const element = createElement('c-report-subscriptions', { is: ReportSubscriptions });
  document.body.appendChild(element);
  return element;
}

const all = (element, selector) => element.shadowRoot.querySelectorAll(selector);
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-report-subscriptions', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    getView.mockResolvedValue(VIEW);
    subscribe.mockResolvedValue('707000000000001AAA');
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it('lists the reports with a link and Subscribe', async () => {
    const element = render();
    await flush();
    expect(all(element, '[data-id="report"]')).toHaveLength(2);
    expect(one(element, '[data-id="report-link"]').getAttribute('href')).toBe(
      '/lightning/r/Report/00O000000000001AAA/view'
    );
    expect(all(element, 'lightning-button[data-id="00O000000000001AAA"]')).toHaveLength(1);
  });

  it('sends the schedule, polls, and says subscribed once the job is done', async () => {
    check
      .mockResolvedValueOnce({ state: 'Running' })
      .mockResolvedValueOnce({ state: 'Subscribed' })
      .mockResolvedValueOnce({ state: 'Subscribed' });
    const element = render();
    await flush();
    one(element, 'lightning-button[data-id="00O000000000001AAA"]').click();
    await flush();
    const frequency = one(element, 'lightning-combobox[data-field="frequency"]');
    frequency.dispatchEvent(new CustomEvent('change', { detail: { value: 'monthly' } }));
    await flush();
    const day = one(element, 'lightning-input[data-field="monthDay"]');
    day.dispatchEvent(new CustomEvent('change', { detail: { value: '15' } }));
    one(element, 'lightning-combobox[data-field="hour"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: '8' } })
    );
    await flush();
    one(element, '[data-id="save"]').click();
    for (let i = 0; i < 3; i++) {
      // eslint-disable-next-line no-await-in-loop
      await flush();
      jest.runOnlyPendingTimers();
    }
    await flush();
    expect(JSON.parse(subscribe.mock.calls[0][0].scheduleJson)).toEqual({
      reportId: '00O000000000001AAA',
      frequency: 'monthly',
      weekday: 'mon',
      monthDay: 15,
      hour: 8
    });
    expect(check).toHaveBeenCalledTimes(3);
    expect(one(element, '[data-id="result"]').variant).toBe('success');
  });

  it('shows a refused subscription in words', async () => {
    check.mockResolvedValue({
      state: 'Failed',
      message: 'You already have 7 report subscriptions'
    });
    const element = render();
    await flush();
    one(element, 'lightning-button[data-id="00O000000000002AAA"]').click();
    await flush();
    one(element, '[data-id="save"]').click();
    await flush();
    const result = one(element, '[data-id="result"]');
    expect(result.variant).toBe('error');
    expect(result.message).toBe('You already have 7 report subscriptions');
  });

  it('explains a missing connection and offers no Subscribe', async () => {
    getView.mockResolvedValue({ ...VIEW, canSubscribe: false, connected: false });
    const element = render();
    await flush();
    expect(one(element, '[data-id="connection-needed"]')).not.toBeNull();
    expect(one(element, '[data-id="connection"]')).not.toBeNull();
    expect(all(element, 'lightning-button[data-id="00O000000000001AAA"]')).toHaveLength(0);
  });

  it('points a person without the connection permissions to the report itself', async () => {
    getView.mockResolvedValue({
      ...VIEW,
      canSubscribe: false,
      canUseConnection: false,
      connected: false
    });
    const element = render();
    await flush();
    expect(one(element, '[data-id="open-to-subscribe"]')).not.toBeNull();
    expect(one(element, '[data-id="connection"]')).toBeNull();
    expect(all(element, '[data-id="report-link"]')).toHaveLength(2);
  });

  it('says when there are no reports', async () => {
    getView.mockResolvedValue({ ...VIEW, reports: [] });
    const element = render();
    await flush();
    expect(one(element, '[data-id="no-reports"]')).not.toBeNull();
  });
});
