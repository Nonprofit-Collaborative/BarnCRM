import { createElement } from 'lwc';
import Toast from 'lightning/toast';
import VolunteerLogHours from 'c/volunteerLogHours';
import getContext from '@salesforce/apex/VolunteerLogHoursController.getContext';

jest.mock(
  '@salesforce/apex/VolunteerLogHoursController.getContext',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const SHIFT_ID = 'a0V000000000001';
const JOB_ID = 'a0J000000000001';
const FROM_SHIFT = {
  canCreate: true,
  hasPersonAccounts: false,
  personObject: 'Contact',
  personFilterField: null,
  personId: null,
  jobId: JOB_ID,
  shiftId: SHIFT_ID,
  dateWorked: '2026-03-14',
  hours: 3
};

function build() {
  const element = createElement('c-volunteer-log-hours', { is: VolunteerLogHours });
  element.recordId = SHIFT_ID;
  document.body.appendChild(element);
  return element;
}

function find(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

async function flush() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

function field(element, name) {
  return [...element.shadowRoot.querySelectorAll('lightning-input-field')].find(
    (input) => input.fieldName === name
  );
}

describe('c-volunteer-log-hours', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('prefills the job, the shift, the date and the hours from a shift', async () => {
    getContext.mockResolvedValue(FROM_SHIFT);
    const element = build();
    await flush();

    expect(getContext).toHaveBeenCalledWith({ recordId: SHIFT_ID });
    expect(field(element, 'Volunteer_Job__c').value).toBe(JOB_ID);
    expect(field(element, 'Volunteer_Shift__c').value).toBe(SHIFT_ID);
    expect(field(element, 'Date_Worked__c').value).toBe('2026-03-14');
    expect(field(element, 'Hours__c').value).toBe(3);
    const picker = find(element, '[data-id="person-picker"]');
    expect(picker.objectApiName).toBe('Contact');
    expect(picker.value).toBeNull();
  });

  it('saves the person into the contact field with the other values', async () => {
    getContext.mockResolvedValue(FROM_SHIFT);
    const element = build();
    await flush();
    const form = find(element, 'lightning-record-edit-form');
    form.submit = jest.fn();
    const picker = find(element, '[data-id="person-picker"]');
    picker.reportValidity = jest.fn(() => true);
    element.shadowRoot.querySelectorAll('lightning-input-field').forEach((input) => {
      input.reportValidity = jest.fn(() => true);
    });
    picker.dispatchEvent(new CustomEvent('change', { detail: { recordId: '003000000000009' } }));
    await flush();

    find(element, '[data-id="save"]').click();
    await flush();

    expect(form.submit).toHaveBeenCalledWith(
      expect.objectContaining({
        Contact__c: '003000000000009',
        Volunteer_Job__c: JOB_ID,
        Volunteer_Shift__c: SHIFT_ID
      })
    );
  });

  it('thanks and closes after the save', async () => {
    getContext.mockResolvedValue(FROM_SHIFT);
    const showSpy = jest.spyOn(Toast, 'show');
    const element = build();
    await flush();

    find(element, 'lightning-record-edit-form').dispatchEvent(
      new CustomEvent('success', { detail: { id: 'a0H000000000001' } })
    );
    await flush();

    expect(showSpy).toHaveBeenCalledWith(
      expect.objectContaining({ label: 'c.Volunteers_LogHours_Saved', variant: 'success' }),
      expect.anything()
    );
    showSpy.mockRestore();
  });

  it('says so when the role cannot enter hours, with no form', async () => {
    getContext.mockResolvedValue({ ...FROM_SHIFT, canCreate: false });
    const element = build();
    await flush();

    expect(find(element, '[data-id="blocker"]').message).toBe('c.Volunteers_LogHours_NoAccess');
    expect(find(element, 'lightning-record-edit-form')).toBeNull();
    expect(find(element, '[data-id="save"]').disabled).toBe(true);
  });

  it('says the form did not open when loading fails', async () => {
    getContext.mockRejectedValue({ body: { message: 'boom' } });
    const element = build();
    await flush();

    expect(find(element, '[data-id="blocker"]').message).toBe('c.Volunteers_LogHours_LoadFailed');
  });
});
