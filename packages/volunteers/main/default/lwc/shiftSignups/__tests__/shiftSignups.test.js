import { createElement } from 'lwc';

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
    return { NavigationMixin, __esModule: true };
  },
  { virtual: true }
);
import ShiftSignups from 'c/shiftSignups';
import getPanel from '@salesforce/apex/VolunteerShiftSignupsController.getPanel';
import addSignup from '@salesforce/apex/VolunteerShiftSignupsController.addSignup';
import setStatus from '@salesforce/apex/VolunteerShiftSignupsController.setStatus';

jest.mock(
  '@salesforce/apex/VolunteerShiftSignupsController.getPanel',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/VolunteerShiftSignupsController.addSignup',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/VolunteerShiftSignupsController.setStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Signups_MarkAttended',
  () => ({ default: 'Mark {0} attended' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Signups_NoHoursWarning',
  () => ({ default: '{0} has no hours.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Volunteers_Signups_HoursWritten',
  () => ({ default: 'Hours recorded.' }),
  { virtual: true }
);

const SHIFT_ID = 'a06000000000001AAA';
// The field the server names for the person account filter; the component passes it through.
const FILTER_FIELD = 'Person_Flag_Field';
const OPTIONS = ['Signed up', 'Confirmed', 'Attended', 'No show', 'Cancelled'].map((value) => ({
  label: value,
  value
}));
const ANA = {
  recordId: 'a07000000000001AAA',
  name: 'VS-000001',
  personName: 'Ana Rivera',
  status: 'Signed up'
};

function panelOf(signups, extra) {
  return {
    shiftName: 'Food pantry sort: 14 Mar 2026',
    volunteersNeeded: 4,
    slotsFilled: signups.length,
    slotsRemaining: 4 - signups.length,
    signups,
    moreThanShown: false,
    canAdd: true,
    canEdit: true,
    hasPersonAccounts: false,
    personFilterField: null,
    statusOptions: OPTIONS,
    hoursWritten: false,
    ...extra
  };
}

function build() {
  const element = createElement('c-shift-signups', { is: ShiftSignups });
  element.recordId = SHIFT_ID;
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-shift-signups', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows places needed, filled and remaining, and the sign-ups in a captioned table', async () => {
    getPanel.mockResolvedValue(panelOf([ANA]));
    const element = build();
    await flush();

    expect(getPanel).toHaveBeenCalledWith({ shiftId: SHIFT_ID });
    expect(byId(element, 'needed').textContent).toBe('4');
    expect(byId(element, 'filled').textContent).toBe('1');
    expect(byId(element, 'remaining').textContent).toBe('3');
    expect(byId(element, 'caption')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="signup"]').length).toBe(1);
    expect(element.shadowRoot.querySelector('.mark-attended').ariaLabel).toBe(
      'Mark Ana Rivera attended'
    );
  });

  it('adds a sign-up for the person chosen', async () => {
    getPanel.mockResolvedValue(panelOf([]));
    addSignup.mockResolvedValue(panelOf([ANA]));
    const element = build();
    await flush();
    expect(byId(element, 'empty-state')).not.toBeNull();

    byId(element, 'add-button').click();
    await flush();
    expect(byId(element, 'save-button').disabled).toBe(true);
    expect(byId(element, 'person-picker').objectApiName).toBe('Contact');

    byId(element, 'person-picker').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: '003000000000001AAA' } })
    );
    await flush();
    byId(element, 'save-button').click();
    await flush();

    expect(addSignup).toHaveBeenCalledWith({
      shiftId: SHIFT_ID,
      personId: '003000000000001AAA',
      status: 'Signed up'
    });
    expect(byId(element, 'add-form')).toBeNull();
    expect(byId(element, 'filled').textContent).toBe('1');
    // Announced once, in the status region, not by a toast as well.
    expect(byId(element, 'result-text').textContent).toContain('Volunteers_Signups_Added');
    expect(byId(element, 'result-warning')).toBeNull();
  });

  it('shows a spinner while the panel loads', async () => {
    getPanel.mockResolvedValue(panelOf([ANA]));
    const element = build();
    expect(byId(element, 'loading')).not.toBeNull();
    await flush();
    expect(byId(element, 'loading')).toBeNull();
  });

  it('warns, naming the person, when Attended created no hours entry', async () => {
    getPanel.mockResolvedValue(panelOf([ANA]));
    setStatus.mockResolvedValue(
      panelOf([{ ...ANA, status: 'Attended' }], { hoursWritten: false, hoursExist: false })
    );
    const element = build();
    await flush();

    element.shadowRoot.querySelector('.mark-attended').click();
    await flush();

    expect(byId(element, 'result-warning')).not.toBeNull();
    expect(byId(element, 'result').textContent).toContain('Ana Rivera has no hours.');
  });

  it('does not warn when the sign-up already has an hours entry', async () => {
    getPanel.mockResolvedValue(panelOf([ANA]));
    setStatus.mockResolvedValue(
      panelOf([{ ...ANA, status: 'Attended' }], { hoursWritten: false, hoursExist: true })
    );
    const element = build();
    await flush();

    element.shadowRoot.querySelector('.mark-attended').click();
    await flush();

    expect(byId(element, 'result-warning')).toBeNull();
  });

  it('offers person accounts only where people are accounts', async () => {
    getPanel.mockResolvedValue(
      panelOf([], { hasPersonAccounts: true, personFilterField: FILTER_FIELD })
    );
    const element = build();
    await flush();
    byId(element, 'add-button').click();
    await flush();

    const picker = byId(element, 'person-picker');
    expect(picker.objectApiName).toBe('Account');
    expect(picker.filter.criteria[0]).toEqual({
      fieldPath: FILTER_FIELD,
      operator: 'eq',
      value: true
    });
  });

  it('marks a sign-up attended and says the hours were recorded', async () => {
    getPanel.mockResolvedValue(panelOf([ANA]));
    setStatus.mockResolvedValue(panelOf([{ ...ANA, status: 'Attended' }], { hoursWritten: true }));
    const element = build();
    await flush();

    element.shadowRoot.querySelector('.mark-attended').click();
    await flush();

    expect(setStatus).toHaveBeenCalledWith({ signupId: ANA.recordId, status: 'Attended' });
    expect(byId(element, 'result').textContent).toContain('Hours recorded.');
    expect(element.shadowRoot.querySelector('.mark-attended')).toBeNull();
  });

  it('changes the status from the picker, and marks a no show', async () => {
    getPanel.mockResolvedValue(panelOf([ANA]));
    setStatus.mockResolvedValue(panelOf([{ ...ANA, status: 'Confirmed' }]));
    const element = build();
    await flush();

    element.shadowRoot
      .querySelector('.status-picker')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Confirmed' } }));
    await flush();
    expect(setStatus).toHaveBeenLastCalledWith({ signupId: ANA.recordId, status: 'Confirmed' });

    element.shadowRoot.querySelector('.mark-no-show').click();
    await flush();
    expect(setStatus).toHaveBeenLastCalledWith({ signupId: ANA.recordId, status: 'No show' });
  });

  it('shows the reason a save was refused', async () => {
    getPanel.mockResolvedValue(panelOf([ANA]));
    setStatus.mockRejectedValue({ body: { message: 'This person is already signed up.' } });
    const element = build();
    await flush();

    element.shadowRoot.querySelector('.mark-no-show').click();
    await flush();

    expect(byId(element, 'error-message').textContent.trim()).toBe(
      'This person is already signed up.'
    );
  });

  it('links each row to its sign-up record, named for the person', async () => {
    getPanel.mockResolvedValue(panelOf([ANA]));
    const element = build();
    await flush();

    const link = byId(element, 'signup-link');
    expect(link.tagName).toBe('A');
    expect(link.textContent).toBe('Ana Rivera');
    expect(link.getAttribute('href')).toBe(`/lightning/r/Volunteer_Signup__c/${ANA.recordId}/view`);
    link.click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__recordPage',
      attributes: {
        recordId: ANA.recordId,
        objectApiName: 'Volunteer_Signup__c',
        actionName: 'view'
      }
    });
  });

  it('is read only for a person who may not change sign-ups', async () => {
    getPanel.mockResolvedValue(panelOf([ANA], { canAdd: false, canEdit: false }));
    const element = build();
    await flush();

    expect(byId(element, 'add-button')).toBeNull();
    expect(element.shadowRoot.querySelector('.status-picker')).toBeNull();
    expect(element.shadowRoot.querySelector('.mark-attended')).toBeNull();
  });
});
