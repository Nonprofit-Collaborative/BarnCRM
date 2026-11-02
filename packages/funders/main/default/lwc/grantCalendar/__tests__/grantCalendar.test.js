import { createElement } from 'lwc';
import GrantCalendar from 'c/grantCalendar';
import getCalendar from '@salesforce/apex/GrantCalendarController.getCalendar';

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/GrantCalendarController.getCalendar', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock('@salesforce/i18n/firstDayOfWeek', () => ({ default: 1 }), { virtual: true });
jest.mock(
  '@salesforce/label/c.Funders_Pipeline_KindApplication',
  () => ({ default: 'Application' }),
  {
    virtual: true
  }
);

const CALENDAR = {
  today: '2026-11-05',
  paymentLabel: 'Grant Payment',
  rows: [
    { id: 'g1', name: 'Literacy', kind: 'application', deadline: '2026-11-10' },
    {
      id: 'r1',
      name: 'Q1 report',
      kind: 'requirement',
      requirementType: 'Financial Report',
      grantName: 'Youth Award',
      deadline: '2026-11-03'
    },
    {
      id: 'p1',
      name: 'P-000001',
      kind: 'payment',
      grantName: 'Youth Award',
      amount: 17500,
      deadline: '2026-11-20'
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render() {
  const element = createElement('c-grant-calendar', { is: GrantCalendar });
  document.body.appendChild(element);
  await flush();
  return element;
}

const all = (element, selector) => Array.from(element.shadowRoot.querySelectorAll(selector));
const one = (element, selector) => element.shadowRoot.querySelector(selector);

describe('c-grant-calendar', () => {
  beforeEach(() => {
    jest.useFakeTimers({ doNotFake: ['setTimeout'] });
    jest.setSystemTime(new Date(2026, 10, 5, 12));
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.useRealTimers();
    jest.clearAllMocks();
  });

  it('asks for the whole weeks of this month and draws each entry on its day', async () => {
    getCalendar.mockResolvedValue(CALENDAR);
    const element = await render();

    expect(getCalendar).toHaveBeenCalledWith({
      fromDate: '2026-11-01',
      toDate: '2026-12-05',
      mineOnly: false
    });
    expect(one(element, '[data-id="month"]').textContent.trim()).toBe('November 2026');
    expect(all(element, 'th').map((th) => th.textContent.trim())[0]).toBe('Sun');
    expect(all(element, '[data-id="week"]')).toHaveLength(5);
    const items = all(element, '[data-id="item"]');
    expect(items.map((item) => item.textContent.trim())).toEqual([
      'Financial Report: Youth Award',
      'Application: Literacy',
      'Grant Payment: Youth Award 17,500'
    ]);
    expect(items[0].className).toContain('slds-text-color_error');
    expect(items[1].className).not.toContain('slds-text-color_error');
  });

  it('moves a month at a time and switches to Mine', async () => {
    getCalendar.mockResolvedValue({ ...CALENDAR, rows: [] });
    const element = await render();

    one(element, '[data-id="next"]').click();
    await flush();
    expect(getCalendar).toHaveBeenLastCalledWith({
      fromDate: '2026-11-29',
      toDate: '2027-01-02',
      mineOnly: false
    });
    expect(one(element, '[data-id="month"]').textContent.trim()).toBe('December 2026');

    one(element, '[data-id="previous"]').click();
    await flush();
    one(element, '[data-id="previous"]').click();
    await flush();
    expect(one(element, '[data-id="month"]').textContent.trim()).toBe('October 2026');

    one(element, '[data-id="scope"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'mine' } })
    );
    await flush();
    expect(getCalendar).toHaveBeenLastCalledWith(expect.objectContaining({ mineOnly: true }));
  });

  it('opens the record an entry names', async () => {
    getCalendar.mockResolvedValue(CALENDAR);
    const element = await render();
    one(element, '[data-kind="payment"]').click();
    expect(mockNavigate.mock.calls[0][0].attributes).toEqual({
      recordId: 'p1',
      objectApiName: 'Grant_Payment__c',
      actionName: 'view'
    });
  });

  it('shows the reason when the calendar cannot load', async () => {
    getCalendar.mockRejectedValue({ body: { message: 'No access' } });
    const element = await render();
    expect(one(element, '[data-id="error-message"]').textContent.trim()).toBe('No access');
    expect(all(element, '[data-id="item"]')).toHaveLength(0);
  });
});
