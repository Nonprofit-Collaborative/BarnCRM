import { createElement } from 'lwc';
import GrantSchedule from 'c/grantSchedule';
import getSchedule from '@salesforce/apex/GrantScheduleController.getSchedule';
import saveSchedule from '@salesforce/apex/GrantScheduleController.saveSchedule';
import markReceived from '@salesforce/apex/GrantScheduleController.markReceived';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

const TOAST = 'lightning__showtoast';

jest.mock('@salesforce/apex/GrantScheduleController.getSchedule', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GrantScheduleController.saveSchedule', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/GrantScheduleController.markReceived', () => ({ default: jest.fn() }), {
  virtual: true
});

const GRANT_ID = 'a01000000000001AAA';
const PAYMENT_ID = 'a03000000000001AAA';

const BUILDABLE = {
  stage: 'Awarded',
  amountAwarded: 25000,
  startDate: '2027-01-01',
  endDate: '2028-12-31',
  amountScheduled: 0,
  amountReceived: 0,
  payments: [],
  canBuild: true,
  canMarkReceived: true,
  frequency: null,
  frequencies: ['Once', 'Annual', 'Semiannual', 'Quarterly', 'Monthly'].map((value) => ({
    label: value,
    value
  })),
  fieldLabels: { awarded: 'Amount Awarded', dueDate: 'Due Date', frequency: 'Payment Frequency' }
};

const SCHEDULED = {
  ...BUILDABLE,
  amountScheduled: 25000,
  amountReceived: 12500,
  canBuild: false,
  payments: [
    {
      id: 'a03000000000002AAA',
      name: 'P-000001',
      dueDate: '2027-01-01',
      amount: 12500,
      status: 'Received',
      receivedDate: '2027-01-03'
    },
    { id: PAYMENT_ID, name: 'P-000002', dueDate: '2028-01-01', amount: 12500, status: 'Expected' }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(schedule) {
  getSchedule.mockResolvedValue(schedule);
  const element = createElement('c-grant-schedule', { is: GrantSchedule });
  element.recordId = GRANT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);
const all = (element, selector) => element.shadowRoot.querySelectorAll(selector);

describe('c-grant-schedule', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('previews an annual schedule and saves it', async () => {
    saveSchedule.mockResolvedValue();
    const element = await render(BUILDABLE);
    expect(one(element, '[data-id="frequency"]').label).toBe('Payment Frequency');
    expect(one(element, '[data-id="frequency"]').value).toBe('Annual');
    expect(all(element, '[data-id="preview-row"]')).toHaveLength(2);

    one(element, '[data-id="frequency"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Quarterly' } })
    );
    await flush();
    expect(all(element, '[data-id="preview-row"]')).toHaveLength(8);

    one(element, '[data-id="frequency"]').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Annual' } })
    );
    await flush();
    getSchedule.mockResolvedValue(SCHEDULED);
    one(element, '[data-id="build-schedule"]').click();
    await flush();

    expect(saveSchedule).toHaveBeenCalledWith({
      grantId: GRANT_ID,
      frequency: 'Annual',
      paymentsJson: JSON.stringify([
        { dueDate: '2027-01-01', amount: 12500 },
        { dueDate: '2028-01-01', amount: 12500 }
      ])
    });
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: GRANT_ID }]);
    expect(all(element, '[data-id="payment"]')).toHaveLength(2);
    expect(one(element, '[data-id="build"]')).toBeNull();
  });

  it('offers Mark Received on expected payments only', async () => {
    markReceived.mockResolvedValue();
    const element = await render(SCHEDULED);
    const buttons = all(element, '[data-id="mark-received"]');
    expect(buttons).toHaveLength(1);
    expect(buttons[0].dataset.paymentId).toBe(PAYMENT_ID);

    buttons[0].click();
    await flush();
    expect(markReceived).toHaveBeenCalledWith({ paymentId: PAYMENT_ID });
    expect(getSchedule).toHaveBeenCalledTimes(2);
  });

  it('says what a schedule needs when it cannot be built', async () => {
    const element = await render({ ...BUILDABLE, stage: 'Applied', canBuild: false });
    expect(one(element, '[data-id="cannot-build"]')).not.toBeNull();
    expect(one(element, '[data-id="build"]')).toBeNull();
  });

  it('hides Mark Received from someone who cannot change payments', async () => {
    const element = await render({ ...SCHEDULED, canMarkReceived: false });
    expect(all(element, '[data-id="mark-received"]')).toHaveLength(0);
  });

  it('shows a refused save and a load error', async () => {
    saveSchedule.mockRejectedValue({ body: { message: 'Refused.' } });
    const element = await render(BUILDABLE);
    const toasts = [];
    element.addEventListener(TOAST, (event) => toasts.push(event.detail));
    one(element, '[data-id="build-schedule"]').click();
    await flush();
    expect(toasts[0]).toMatchObject({ message: 'Refused.', variant: 'error' });

    getSchedule.mockRejectedValue({ body: { message: 'Could not load.' } });
    const broken = createElement('c-grant-schedule', { is: GrantSchedule });
    broken.recordId = GRANT_ID;
    document.body.appendChild(broken);
    await flush();
    expect(one(broken, '[data-id="error-message"]').textContent).toBe('Could not load.');
  });
});
