import { createElement } from 'lwc';
import Toast from 'lightning/toast';
import { CurrentPageReference } from 'lightning/navigation';
import RecordService from 'c/recordService';
import getForm from '@salesforce/apex/RecordServiceController.getForm';
import record from '@salesforce/apex/RecordServiceController.record';

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: createTestWireAdapter(), __esModule: true };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/RecordServiceController.getForm', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/RecordServiceController.record', () => ({ default: jest.fn() }), {
  virtual: true
});

const ENROLLMENT_ID = 'a09000000000001AAA';
const ANA = '003000000000001AAA';
const BEN = '003000000000002AAA';
const MEAL = 'a0A000000000001AAA';

function formOf(extra) {
  return {
    personObjectApiName: 'Contact',
    personFilterField: null,
    personId: ANA,
    enrollmentId: ENROLLMENT_ID,
    serviceId: MEAL,
    services: [{ label: 'Hot meal', value: MEAL }],
    attendance: [
      { label: 'Present', value: 'Present' },
      { label: 'Excused Absence', value: 'Excused Absence' }
    ],
    canCreate: true,
    dateLabel: 'Delivery Date',
    quantityLabel: 'Quantity',
    ...extra
  };
}

async function flush() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function render() {
  const element = createElement('c-record-service', { is: RecordService });
  element.recordId = ENROLLMENT_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-record-service', () => {
  let toast;
  beforeEach(() => {
    toast = jest.spyOn(Toast, 'show');
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('fills in the person and service from the enrollment and records it', async () => {
    getForm.mockResolvedValue(formOf());
    record.mockResolvedValue('a0B000000000001AAA');
    const element = await render();
    const closed = jest.fn();
    element.addEventListener('lightning__closeactionscreen', closed);

    expect(getForm).toHaveBeenCalledWith({ recordId: ENROLLMENT_ID });
    expect(q(element, 'person').value).toBe(ANA);
    expect(q(element, 'person').objectApiName).toBe('Contact');
    expect(q(element, 'service').value).toBe(MEAL);
    expect(q(element, 'attendance').value).toBe('Present');

    const quantity = q(element, 'quantity');
    quantity.value = '2';
    quantity.dispatchEvent(new CustomEvent('change'));
    q(element, 'save').click();
    await flush();

    expect(record).toHaveBeenCalledWith(
      expect.objectContaining({
        personId: ANA,
        serviceId: MEAL,
        attendance: 'Present',
        quantity: 2,
        enrollmentId: ENROLLMENT_ID
      })
    );
    expect(toast).toHaveBeenCalledWith(
      expect.objectContaining({ variant: 'success', label: 'c.Programs_RecordService_Saved' }),
      expect.anything()
    );
    expect(closed).toHaveBeenCalled();
  });

  it('drops the enrollment when another person is chosen, and an absence sends no quantity', async () => {
    getForm.mockResolvedValue(formOf());
    record.mockResolvedValue('a0B000000000001AAA');
    const element = await render();

    q(element, 'person').dispatchEvent(new CustomEvent('change', { detail: { recordId: BEN } }));
    q(element, 'attendance').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Excused Absence' } })
    );
    await flush();
    expect(q(element, 'quantity').disabled).toBe(true);
    q(element, 'save').click();
    await flush();

    expect(record.mock.calls[0][0]).toMatchObject({
      personId: BEN,
      enrollmentId: null,
      quantity: null
    });
  });

  it('cannot save without a person, and shows a refusal without closing', async () => {
    getForm.mockResolvedValue(formOf({ personId: null, enrollmentId: null }));
    record.mockRejectedValue({ body: { message: 'Choose a person.' } });
    const element = await render();
    expect(q(element, 'save').disabled).toBe(true);

    q(element, 'person').dispatchEvent(new CustomEvent('change', { detail: { recordId: ANA } }));
    await flush();
    q(element, 'save').click();
    await flush();
    expect(toast).toHaveBeenCalledWith(
      expect.objectContaining({ variant: 'error', label: 'Choose a person.' }),
      expect.anything()
    );
  });

  it('says so when the user cannot record or there is no service', async () => {
    getForm.mockResolvedValue(formOf({ canCreate: false }));
    const reader = await render();
    expect(q(reader, 'no-access')).not.toBeNull();
    expect(q(reader, 'save')).toBeNull();

    getForm.mockResolvedValue(formOf({ services: [], serviceId: null }));
    const empty = await render();
    expect(q(empty, 'no-services')).not.toBeNull();

    getForm.mockRejectedValue({});
    const failed = await render();
    expect(q(failed, 'load-error').message).toBe('c.Programs_Fail_RecordService');
  });

  it('on the Record Service tab starts on the person and returns to them after the save', async () => {
    getForm.mockImplementation(({ recordId }) =>
      Promise.resolve(formOf({ personId: recordId, enrollmentId: null }))
    );
    record.mockResolvedValue('a0B000000000001AAA');
    const element = createElement('c-record-service', { is: RecordService });
    document.body.appendChild(element);
    // eslint-disable-next-line @lwc/lwc/no-unexpected-wire-adapter-usages
    CurrentPageReference.emit({ type: 'standard__navItemPage', state: { c__personId: BEN } });
    await flush();

    expect(getForm).toHaveBeenLastCalledWith({ recordId: BEN });
    expect(q(element, 'person').value).toBe(BEN);

    q(element, 'save').click();
    await flush();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__recordPage',
      attributes: { recordId: BEN, actionName: 'view' }
    });
  });
});
