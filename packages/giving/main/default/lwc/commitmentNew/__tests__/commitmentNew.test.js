import { createElement } from 'lwc';
import CommitmentNew from 'c/commitmentNew';
import { CurrentPageReference } from 'lightning/navigation';
import getDefaults from '@salesforce/apex/CommitmentEntryController.getDefaults';
import preview from '@salesforce/apex/CommitmentEntryController.preview';
import save from '@salesforce/apex/CommitmentEntryController.save';
import { clearHelpTextForTest, setHelpTextForTest } from 'c/barnHelpText';

const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
  const actual = jest.requireActual('lightning/navigation');
  const Navigate = Symbol('Navigate');
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](...args) {
        mockNavigate(...args);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return { ...actual, NavigationMixin, __esModule: true };
});

function getNavigateCalledWith() {
  const calls = mockNavigate.mock.calls;
  return calls.length ? calls[calls.length - 1][0] : undefined;
}

jest.mock(
  '@salesforce/apex/CommitmentEntryController.getDefaults',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/CommitmentEntryController.preview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CommitmentEntryController.save', () => ({ default: jest.fn() }), {
  virtual: true
});

const CONTACT_ID = '003000000000001AAA';
const DEFAULTS = {
  canCreate: true,
  hasPersonAccounts: false,
  frequencies: [
    { label: 'Monthly', value: 'Monthly' },
    { label: 'Yearly', value: 'Yearly' }
  ],
  defaultFrequency: 'Monthly'
};

async function flush() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function build(state = {}) {
  const element = createElement('c-commitment-new', { is: CommitmentNew });
  document.body.appendChild(element);
  CurrentPageReference.emit({
    type: 'standard__objectPage',
    attributes: { objectApiName: 'Commitment__c', actionName: 'new' },
    state
  });
  await flush();
  return element;
}

function field(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function type(element, id, value) {
  const input = field(element, id);
  input.value = value;
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-commitment-new', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    getDefaults.mockResolvedValue(DEFAULTS);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
    clearHelpTextForTest();
  });

  it('asks for a pledge the natural way', async () => {
    const element = await build();

    expect(field(element, 'kind').value).toBe('Pledge');
    expect(field(element, 'donor-kind').value).toBe('person');
    expect(field(element, 'total').label).toBe('c.Giving_AskPipeline_FieldPledgeTotal');
    expect(field(element, 'payments').label).toBe('c.Giving_AskPipeline_FieldPayments');
    expect(field(element, 'last-payment-date').label).toBe(
      'c.Giving_CommitmentNew_LastPaymentDate'
    );
    expect(field(element, 'start-date').label).toBe('c.Giving_AskPipeline_FieldFirstPayment');
    expect(field(element, 'frequency').value).toBe('Monthly');
    expect(field(element, 'amount')).toBeNull();
    expect(field(element, 'donor-person').displayInfo).toEqual({ additionalFields: ['Email'] });
  });

  it('asks for the amount each time on a recurring gift', async () => {
    const element = await build();

    field(element, 'kind').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Recurring' } })
    );
    await flush();

    expect(field(element, 'total')).toBeNull();
    expect(field(element, 'payments')).toBeNull();
    expect(field(element, 'amount').label).toBe('c.Giving_CommitmentNew_AmountEachTime');
    expect(field(element, 'start-date').label).toBe('c.Core_Shared_StartDate');
  });

  it('fills in the donor of the page New was chosen from', async () => {
    getDefaults.mockResolvedValue({ ...DEFAULTS, donorId: CONTACT_ID, donorKind: 'person' });
    const json = JSON.stringify({ attributes: { recordId: CONTACT_ID } });
    const element = await build({ inContextOfRef: '1.' + Buffer.from(json).toString('base64') });

    expect(getDefaults).toHaveBeenCalledWith({ contextId: CONTACT_ID });
    expect(field(element, 'donor-person').value).toBe(CONTACT_ID);
  });

  it('previews the payments once the pledge is complete', async () => {
    setHelpTextForTest({
      Giving_CommitmentNew_PreviewPledge: '{0} payments of {1}, last {2} on {3}.'
    });
    preview.mockResolvedValue({
      installments: [
        { expectedAmount: 83.33, dueDate: '2027-01-15' },
        { expectedAmount: 83.33, dueDate: '2027-02-15' },
        { expectedAmount: 83.34, dueDate: '2027-03-15' }
      ]
    });
    const element = await build();

    type(element, 'total', '250');
    type(element, 'start-date', '2027-01-15');
    jest.runAllTimers();
    expect(preview).not.toHaveBeenCalled();

    type(element, 'payments', '3');
    jest.runAllTimers();
    await flush();

    expect(preview).toHaveBeenCalledTimes(1);
    const input = preview.mock.calls[0][0].input;
    expect(input).toMatchObject({ kind: 'Pledge', total: 250, payments: 3, frequency: 'Monthly' });
    const text = field(element, 'preview-text').textContent;
    expect(text).toContain('3 payments of');
    expect(text).toContain('83.33');
    expect(text).toContain('83.34');
  });

  it('clears the last payment date when the number of payments is typed', async () => {
    const element = await build();

    type(element, 'last-payment-date', '2027-12-15');
    await flush();
    type(element, 'payments', '12');
    await flush();

    expect(field(element, 'last-payment-date').value).toBeUndefined();
  });

  it('opens the new commitment once it is saved', async () => {
    save.mockResolvedValue({ success: true, commitmentId: 'a0B000000000001AAA' });
    const element = await build();

    field(element, 'save').click();
    await flush();

    expect(save).toHaveBeenCalledTimes(1);
    expect(getNavigateCalledWith()).toEqual({
      type: 'standard__recordPage',
      attributes: { recordId: 'a0B000000000001AAA', actionName: 'view' }
    });
  });

  it('shows why a save was refused and stays on the screen', async () => {
    save.mockResolvedValue({ success: false, error: 'Choose the donor.' });
    const element = await build();

    field(element, 'save').click();
    await flush();

    const error = field(element, 'error');
    expect(error.variant).toBe('error');
    expect(error.message).toBe('Choose the donor.');
  });

  it('goes back to the commitments list on cancel', async () => {
    const element = await build();

    field(element, 'cancel').click();

    expect(getNavigateCalledWith()).toEqual({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Commitment__c', actionName: 'home' }
    });
  });

  it('says so to a person who may not create commitments', async () => {
    getDefaults.mockResolvedValue({ ...DEFAULTS, canCreate: false });
    const element = await build();

    expect(field(element, 'no-permission').message).toBe('c.Giving_Commitment_NoPermission');
    expect(field(element, 'save')).toBeNull();
  });
});
