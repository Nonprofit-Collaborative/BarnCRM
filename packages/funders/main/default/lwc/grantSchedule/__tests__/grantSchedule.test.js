import { createElement } from 'lwc';
import GrantSchedule from 'c/grantSchedule';
import getSchedule from '@salesforce/apex/GrantScheduleController.getSchedule';
import saveSchedule from '@salesforce/apex/GrantScheduleController.saveSchedule';
import markReceived from '@salesforce/apex/GrantScheduleController.markReceived';
import undoReceived from '@salesforce/apex/GrantScheduleController.undoReceived';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import { clearHelpTextForTest, setHelpTextForTest } from 'c/barnHelpText';

const TOAST = 'lightning__showtoast';

jest.mock('@salesforce/apex/GrantScheduleController.undoReceived', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/GrantScheduleController.getSchedule',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
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
  const element = createElement('c-grant-schedule', { is: GrantSchedule });
  element.recordId = GRANT_ID;
  document.body.appendChild(element);
  getSchedule.emit(schedule);
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
    refreshApex.mockImplementationOnce(() => {
      getSchedule.emit(SCHEDULED);
      return Promise.resolve();
    });
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
    expect(refreshApex).toHaveBeenCalledTimes(1);
  });

  it('offers Undo after Mark Received and puts the payment back', async () => {
    markReceived.mockResolvedValue({ id: PAYMENT_ID, status: 'Expected', dateValue: null });
    undoReceived.mockResolvedValue();
    const element = await render(SCHEDULED);
    const toasts = [];
    element.addEventListener(TOAST, (event) => toasts.push(event.detail));
    expect(one(element, '[data-id="undo-received"]')).toBeNull();

    one(element, '[data-id="mark-received"]').click();
    await flush();
    const undo = one(element, '[data-id="undo-received"]');
    expect(undo).not.toBeNull();

    undo.dispatchEvent(new CustomEvent('action'));
    await flush();
    expect(undoReceived).toHaveBeenCalledWith({
      paymentId: PAYMENT_ID,
      status: 'Expected',
      receivedDate: null
    });
    expect(one(element, '[data-id="undo-received"]')).toBeNull();
    expect(toasts[toasts.length - 1]).toMatchObject({ variant: 'success' });
  });

  it('shows the share of the award received as a meter', async () => {
    const element = await render(SCHEDULED);
    expect(one(element, '[data-id="received-meter"]').value).toBe(50);
    expect(one(element, '[data-id="received-meter"]').valueText).toBe('50%');
  });

  it('says what a schedule needs when it cannot be built', async () => {
    const element = await render({ ...BUILDABLE, stage: 'Applied', canBuild: false });
    expect(one(element, '[data-id="cannot-build"]').textContent).toBe(
      'c.Funders_Schedule_NeedsAwarded'
    );
    expect(one(element, '[data-id="build"]')).toBeNull();
  });

  it('names only the missing award field', async () => {
    setHelpTextForTest({ Funders_Schedule_NeedsFields: 'Add the {0} to build a schedule.' });
    const element = await render({
      ...BUILDABLE,
      endDate: null,
      canBuild: false,
      fieldLabels: { ...BUILDABLE.fieldLabels, endDate: 'Award End Date' }
    });
    expect(one(element, '[data-id="cannot-build"]').textContent).toBe(
      'Add the Award End Date to build a schedule.'
    );
    clearHelpTextForTest();
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

    document.body.removeChild(element);
    const broken = createElement('c-grant-schedule', { is: GrantSchedule });
    broken.recordId = GRANT_ID;
    document.body.appendChild(broken);
    getSchedule.error({ message: 'Could not load.' });
    await flush();
    expect(one(broken, '[data-id="error-message"]').message).toBe('Could not load.');
  });
});
