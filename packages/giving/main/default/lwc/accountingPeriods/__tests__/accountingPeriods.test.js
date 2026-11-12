import { createElement } from 'lwc';
import AccountingPeriods from 'c/accountingPeriods';
import getPeriod from '@salesforce/apex/AccountingPeriodController.getPeriod';
import closeThrough from '@salesforce/apex/AccountingPeriodController.closeThrough';
import { setHelpTextForTest } from 'c/barnHelpText';

setHelpTextForTest({
  Giving_Periods_NotClosed: 'No period is closed.',
  Giving_Periods_Saved: 'Saved. The books are closed through the date shown.',
  Giving_Periods_UnexpectedError: 'Something went wrong. The details are in the Error Log.'
});

jest.mock('@salesforce/apex/AccountingPeriodController.getPeriod', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/AccountingPeriodController.closeThrough',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const OPEN = {
  closedThrough: null,
  latestAllowed: '2026-09-22',
  canManage: true,
  canReopen: false
};

const CLOSED = { ...OPEN, closedThrough: '2026-08-31' };

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(view) {
  getPeriod.mockResolvedValue(view);
  const element = createElement('c-accounting-periods', { is: AccountingPeriods });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

const byId = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-accounting-periods', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says no period is closed on a new org', async () => {
    const element = await render(OPEN);
    expect(byId(element, 'current').textContent).toContain('No period is closed.');
    expect(byId(element, 'save').disabled).toBe(true);
  });

  it('shows the close date and never offers a date after the day before yesterday', async () => {
    const element = await render(CLOSED);
    const formatted = byId(element, 'current').querySelector('lightning-formatted-date-time');
    expect(formatted.value).toBe('2026-08-31');
    expect(byId(element, 'close-date').max).toBe('2026-09-22');
  });

  it('saves a new close date and shows the saved page', async () => {
    const element = await render(CLOSED);
    closeThrough.mockResolvedValue({ ...CLOSED, closedThrough: '2026-09-15' });

    const input = byId(element, 'close-date');
    input.value = '2026-09-15';
    input.dispatchEvent(new CustomEvent('change', { detail: { value: '2026-09-15' } }));
    await flushPromises();
    byId(element, 'save').click();
    await flushPromises();

    expect(closeThrough).toHaveBeenCalledWith({ closeDate: '2026-09-15' });
    expect(byId(element, 'notice').message).toContain('Saved.');
    expect(byId(element, 'current').querySelector('lightning-formatted-date-time').value).toBe(
      '2026-09-15'
    );
  });

  it('shows the refusal the controller gives', async () => {
    const element = await render(CLOSED);
    closeThrough.mockRejectedValue({
      body: { message: 'A closed period cannot be reopened here.' }
    });

    byId(element, 'close-date').dispatchEvent(
      new CustomEvent('change', { detail: { value: '2026-08-01' } })
    );
    await flushPromises();
    byId(element, 'save').click();
    await flushPromises();

    expect(byId(element, 'error').message).toContain('A closed period cannot be reopened here.');
  });

  it('shows the date without the field to someone who cannot change settings', async () => {
    const element = await render({ ...CLOSED, canManage: false });
    expect(byId(element, 'close-date')).toBeNull();
    expect(byId(element, 'read-only').variant).toBe('info');
  });

  it('says something went wrong when the page cannot load', async () => {
    getPeriod.mockRejectedValue({});
    const element = createElement('c-accounting-periods', { is: AccountingPeriods });
    document.body.appendChild(element);
    await flushPromises();
    expect(byId(element, 'error').message).toContain('Something went wrong.');
  });
});
