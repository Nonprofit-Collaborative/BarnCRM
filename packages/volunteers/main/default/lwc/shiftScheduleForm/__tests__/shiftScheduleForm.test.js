import { createElement } from 'lwc';
import ShiftScheduleForm from 'c/shiftScheduleForm';
import getFormSettings from '@salesforce/apex/ShiftScheduleController.getFormSettings';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';
import { shiftPreview } from '../preview';

jest.mock(
  '@salesforce/apex/ShiftScheduleController.getFormSettings',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// Monday 2 March 2026, eight weeks ahead: through Monday 27 April.
const SETTINGS = { today: '2026-03-02', horizonWeeks: 8 };
const JOB_ID = 'a0J000000000001';

function build() {
  const element = createElement('c-shift-schedule-form', { is: ShiftScheduleForm });
  element.recordId = JOB_ID;
  element.objectApiName = 'Volunteer_Job__c';
  document.body.appendChild(element);
  return element;
}

async function flush() {
  for (let i = 0; i < 3; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

function field(element, fieldName) {
  return [...element.shadowRoot.querySelectorAll('lightning-input-field')].find(
    (input) => input.fieldName === fieldName
  );
}

function change(element, fieldName, value) {
  const input = field(element, fieldName);
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

function previewOf(element) {
  const line = element.shadowRoot.querySelector('[data-id="preview"]');
  return line ? line.textContent : null;
}

describe('shiftPreview', () => {
  it('counts the chosen days from today to the horizon', () => {
    const result = shiftPreview(
      { weekdays: 'Saturday;Sunday', everyNWeeks: 1, startDate: '2026-02-28' },
      '2026-03-02',
      8
    );
    expect(result).toEqual({ count: 16, through: '2026-04-27', problem: null });
  });

  it('skips the weeks between repeats, counted from the start week', () => {
    const result = shiftPreview(
      { weekdays: ['Monday'], everyNWeeks: 2, startDate: '2026-03-02' },
      '2026-03-02',
      8
    );
    expect(result.count).toBe(5);
  });

  it('stops at the end date and names the problems', () => {
    expect(
      shiftPreview(
        { weekdays: 'Monday', everyNWeeks: 1, startDate: '2026-03-02', endDate: '2026-03-16' },
        '2026-03-02',
        8
      )
    ).toEqual({ count: 3, through: '2026-03-16', problem: null });
    expect(shiftPreview({ weekdays: '', startDate: '2026-03-02' }, '2026-03-02', 8).problem).toBe(
      'weekdays'
    );
    expect(
      shiftPreview(
        { weekdays: 'Monday', startDate: '2026-03-10', endDate: '2026-03-01' },
        '2026-03-02',
        8
      ).problem
    ).toBe('dates');
  });
});

describe('c-shift-schedule-form', () => {
  beforeEach(() => {
    setHelpTextForTest({
      Volunteers_Schedule_Preview: '{0} shifts will be created through {1}.',
      Volunteers_ScheduleForm_NoDays: 'Choose at least one day.',
      Volunteers_ScheduleForm_BadDates: 'Choose a start date.'
    });
  });

  afterEach(() => {
    clearHelpTextForTest();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('prefills the job and updates the preview as the fields change', async () => {
    const element = build();
    getFormSettings.emit(SETTINGS);
    await flush();

    expect(field(element, 'Job__c').value).toBe(JOB_ID);
    expect(previewOf(element)).toBe('Choose at least one day.');

    change(element, 'Weekdays__c', 'Saturday;Sunday');
    await flush();
    expect(previewOf(element)).toBe('Choose a start date.');

    change(element, 'Start_Date__c', '2026-02-28');
    await flush();
    expect(previewOf(element)).toMatch(/^16 shifts will be created through /);

    change(element, 'Every_N_Weeks__c', 2);
    await flush();
    expect(previewOf(element)).toMatch(/^8 shifts will be created through /);
  });
});
