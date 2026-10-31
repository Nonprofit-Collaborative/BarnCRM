import { createElement } from 'lwc';
import ServiceDeliveryLog from 'c/serviceDeliveryLog';
import getLog from '@salesforce/apex/ServiceDeliveryLogController.getLog';
import save from '@salesforce/apex/ServiceDeliveryLogController.save';
import {
  entriesToSave,
  format,
  isAbsence,
  logRows,
  markAllPresent,
  withAttendance,
  withQuantity
} from '../logRows';

jest.mock('@salesforce/apex/ServiceDeliveryLogController.getLog', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ServiceDeliveryLogController.save', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Log_Saved', () => ({ default: '{0} saved.' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Log_SavedOne', () => ({ default: 'One saved.' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Log_NothingToSave', () => ({ default: 'Nothing.' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Log_Quantity', () => ({ default: 'Quantity ({0})' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Programs_Log_NotRecorded', () => ({ default: 'Not Recorded' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Programs_Log_AttendanceFor',
  () => ({ default: 'Attendance for {0}' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Programs_Log_QuantityFor', () => ({ default: 'Quantity for {0}' }), {
  virtual: true
});

const PROGRAM_ID = 'a08000000000001AAA';
const SERVICE_ID = 'a0A000000000001AAA';
const ATTENDANCE = [
  { label: 'Present', value: 'Present' },
  { label: 'Excused Absence', value: 'Excused Absence' },
  { label: 'Unexcused Absence', value: 'Unexcused Absence' }
];
const ANA = {
  key: '003000000000001AAA',
  personName: 'Ana Rivera',
  contactId: '003000000000001AAA',
  accountId: null,
  enrollmentId: 'a09000000000001AAA',
  deliveryId: null,
  attendance: null,
  quantity: null
};
const BEN = {
  key: '003000000000002AAA',
  personName: 'Ben Okafor',
  contactId: '003000000000002AAA',
  accountId: null,
  enrollmentId: 'a09000000000002AAA',
  deliveryId: 'a0B000000000001AAA',
  attendance: 'Present',
  quantity: 2
};

function logOf(rows, extra) {
  return {
    services: [{ label: 'Tutoring hour', value: SERVICE_ID, unit: 'Hours' }],
    serviceId: SERVICE_ID,
    deliveryDate: '2026-10-31',
    attendance: ATTENDANCE,
    rows,
    moreThanShown: false,
    canEdit: true,
    saved: 0,
    ...extra
  };
}

const LABELS = {
  notRecorded: 'Not Recorded',
  attendanceFor: 'Attendance for {0}',
  quantityFor: 'Quantity for {0}'
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render() {
  const element = createElement('c-service-delivery-log', { is: ServiceDeliveryLog });
  element.recordId = PROGRAM_ID;
  document.body.appendChild(element);
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const findAll = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('logRows (framework free)', () => {
  it('fills placeholders and knows an absence', () => {
    expect(format('{0} saved.', 3)).toBe('3 saved.');
    expect(format(undefined)).toBe('');
    expect(isAbsence('Excused Absence')).toBe(true);
    expect(isAbsence('Present')).toBe(false);
  });

  it('offers Not Recorded only to someone with nothing recorded', () => {
    const rows = logRows(logOf([ANA, BEN]), {}, LABELS);
    expect(rows[0].options[0]).toEqual({ label: 'Not Recorded', value: '' });
    expect(rows[0].quantityDisabled).toBe(true);
    expect(rows[0].quantity).toBeNull();
    expect(rows[0].attendanceFor).toBe('Attendance for Ana Rivera');
    expect(rows[1].options).toHaveLength(3);
    expect(rows[1].quantity).toBe(2);
    expect(rows[1].quantityDisabled).toBe(false);
    expect(logRows(undefined, {}, LABELS)).toEqual([]);
  });

  it('sets the quantity an attendance implies', () => {
    const log = logOf([ANA, BEN]);
    let drafts = withAttendance(log, {}, ANA.key, 'Present');
    expect(drafts[ANA.key]).toEqual({ attendance: 'Present', quantity: 1 });
    drafts = withAttendance(log, drafts, BEN.key, 'Unexcused Absence');
    expect(drafts[BEN.key]).toEqual({ attendance: 'Unexcused Absence', quantity: 0 });
    drafts = withAttendance(log, drafts, BEN.key, 'Present');
    expect(drafts[BEN.key].quantity).toBe(1);
    drafts = withQuantity(log, drafts, ANA.key, '2.5');
    expect(drafts[ANA.key]).toEqual({ attendance: 'Present', quantity: 2.5 });
    expect(withQuantity(log, {}, ANA.key, '')[ANA.key].quantity).toBeNull();
  });

  it('marks only the unrecorded present and saves only real changes', () => {
    const log = logOf([ANA, BEN]);
    const drafts = markAllPresent(log, {});
    expect(Object.keys(drafts)).toEqual([ANA.key]);
    expect(entriesToSave(log, drafts)).toEqual([
      {
        contactId: ANA.contactId,
        accountId: null,
        enrollmentId: ANA.enrollmentId,
        deliveryId: null,
        attendance: 'Present',
        quantity: 1
      }
    ]);
    const unchanged = { [BEN.key]: { attendance: 'Present', quantity: 2 } };
    expect(entriesToSave(log, unchanged)).toEqual([]);
    const absent = withAttendance(log, {}, BEN.key, 'Excused Absence');
    expect(entriesToSave(log, absent)[0]).toMatchObject({
      deliveryId: BEN.deliveryId,
      quantity: 0
    });
    expect(entriesToSave(undefined, {})).toEqual([]);
  });
});

describe('c-service-delivery-log', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows a row per person with a header', async () => {
    getLog.mockResolvedValue(logOf([ANA, BEN]));
    const element = await render();
    expect(getLog).toHaveBeenCalledWith({
      programId: PROGRAM_ID,
      serviceId: undefined,
      deliveryDate: undefined
    });
    expect(findAll(element, 'row')).toHaveLength(2);
    expect(find(element, 'header').textContent).toContain('Quantity (Hours)');
    expect(find(element, 'save')).not.toBeNull();
  });

  it('says when the program has no active service', async () => {
    getLog.mockResolvedValue(logOf([], { services: [], serviceId: null }));
    const element = await render();
    expect(find(element, 'no-services')).not.toBeNull();
    expect(find(element, 'save')).toBeNull();
  });

  it('says when nobody is enrolled and when more are not shown', async () => {
    getLog.mockResolvedValue(logOf([], { moreThanShown: true }));
    const element = await render();
    expect(find(element, 'empty')).not.toBeNull();
    expect(find(element, 'more')).not.toBeNull();
  });

  it('is read only without edit access', async () => {
    getLog.mockResolvedValue(logOf([BEN], { canEdit: false }));
    const element = await render();
    expect(find(element, 'attendance')).toBeNull();
    expect(find(element, 'recorded').textContent).toContain('Present');
    expect(find(element, 'save')).toBeNull();
  });

  it('reloads for another service or day', async () => {
    getLog.mockResolvedValue(logOf([ANA]));
    const element = await render();
    find(element, 'service').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'a0A000000000002AAA' } })
    );
    await flush();
    expect(getLog).toHaveBeenLastCalledWith({
      programId: PROGRAM_ID,
      serviceId: 'a0A000000000002AAA',
      deliveryDate: '2026-10-31'
    });
    const date = find(element, 'date');
    date.value = '2026-10-30';
    date.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(getLog).toHaveBeenLastCalledWith({
      programId: PROGRAM_ID,
      serviceId: SERVICE_ID,
      deliveryDate: '2026-10-30'
    });
    const calls = getLog.mock.calls.length;
    date.value = '';
    date.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(getLog.mock.calls).toHaveLength(calls);
  });

  it('marks everyone present and saves', async () => {
    getLog.mockResolvedValue(logOf([ANA, BEN]));
    save.mockResolvedValue(
      logOf([{ ...ANA, deliveryId: 'a0B2', attendance: 'Present', quantity: 1 }, BEN], { saved: 1 })
    );
    const element = await render();
    find(element, 'mark-all-present').click();
    await flush();
    find(element, 'save').click();
    await flush();
    expect(save).toHaveBeenCalledWith({
      programId: PROGRAM_ID,
      serviceId: SERVICE_ID,
      deliveryDate: '2026-10-31',
      entries: [expect.objectContaining({ contactId: ANA.contactId, attendance: 'Present' })]
    });
    expect(find(element, 'result').textContent).toBe('One saved.');
  });

  it('records one person by hand and reports how many were saved', async () => {
    getLog.mockResolvedValue(logOf([ANA, BEN]));
    save.mockResolvedValue(logOf([ANA, BEN], { saved: 2 }));
    const element = await render();
    const [anaAttendance, benAttendance] = findAll(element, 'attendance');
    anaAttendance.dispatchEvent(new CustomEvent('change', { detail: { value: 'Present' } }));
    await flush();
    const anaQuantity = findAll(element, 'quantity')[0];
    anaQuantity.value = '3';
    anaQuantity.dispatchEvent(new CustomEvent('change'));
    benAttendance.dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Unexcused Absence' } })
    );
    await flush();
    find(element, 'save').click();
    await flush();
    const entries = save.mock.calls[0][0].entries;
    expect(entries).toHaveLength(2);
    expect(entries[0].quantity).toBe(3);
    expect(entries[1].quantity).toBe(0);
    expect(find(element, 'result').textContent).toBe('2 saved.');
  });

  it('says when there is nothing to save', async () => {
    getLog.mockResolvedValue(logOf([ANA]));
    const element = await render();
    find(element, 'save').click();
    await flush();
    expect(save).not.toHaveBeenCalled();
    expect(find(element, 'result').textContent).toBe('Nothing.');
  });

  it('shows a refusal in its own words, or a general message', async () => {
    getLog.mockResolvedValue(logOf([ANA]));
    save.mockRejectedValue({ body: { message: 'Quantity cannot be negative.' } });
    const element = await render();
    find(element, 'mark-all-present').click();
    find(element, 'save').click();
    await flush();
    expect(find(element, 'error-message').textContent).toContain('Quantity cannot be negative.');

    getLog.mockRejectedValue({});
    const second = await render();
    expect(second.shadowRoot.querySelector('[data-id="error-message"]').textContent).toContain(
      'Programs_Log_ActionFailed'
    );
  });
});
