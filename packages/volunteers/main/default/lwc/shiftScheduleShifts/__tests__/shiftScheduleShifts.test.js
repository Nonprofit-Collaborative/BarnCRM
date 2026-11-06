// The record test wire adapter is emitted to on purpose, which is how a wired component is
// driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import ShiftScheduleShifts from 'c/shiftScheduleShifts';
import getPreview from '@salesforce/apex/ShiftScheduleController.getPreview';
import createNow from '@salesforce/apex/ShiftScheduleController.createNow';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';

jest.mock('@salesforce/apex/ShiftScheduleController.getPreview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ShiftScheduleController.createNow', () => ({ default: jest.fn() }), {
  virtual: true
});

const SCHEDULE_ID = 'a0S000000000001';
const MISSING = {
  active: true,
  turnedOff: false,
  canCreate: true,
  missing: 12,
  through: '2026-04-27',
  createdThrough: null
};

function build() {
  const element = createElement('c-shift-schedule-shifts', { is: ShiftScheduleShifts });
  element.recordId = SCHEDULE_ID;
  document.body.appendChild(element);
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function flush() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function loaded(preview) {
  getPreview.mockResolvedValue(preview);
  const element = build();
  getRecord.emit({ fields: { LastModifiedDate: { value: '2026-03-02T12:00:00.000Z' } } });
  await flush();
  return element;
}

describe('c-shift-schedule-shifts', () => {
  beforeEach(() => {
    setHelpTextForTest({
      Volunteers_Schedule_Preview: '{0} shifts will be created through {1}.',
      Volunteers_Schedule_Created: 'Shifts created: {0}.'
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    clearHelpTextForTest();
    jest.clearAllMocks();
  });

  it('previews how many shifts the next run creates and through which day', async () => {
    const element = await loaded(MISSING);
    const preview = find(element, 'preview');
    expect(preview.textContent).toMatch(/^12 shifts will be created through /);
    expect(preview.textContent).toMatch(/2026/);
    expect(find(element, 'create-now').disabled).toBe(false);
  });

  it('creates the shifts now and says how many', async () => {
    const element = await loaded(MISSING);
    createNow.mockResolvedValue({ ...MISSING, missing: 0, createdThrough: '2026-04-27' });

    find(element, 'create-now').click();
    await flush();

    expect(createNow).toHaveBeenCalledWith({ scheduleId: SCHEDULE_ID });
    expect(find(element, 'result-message').message).toBe('Shifts created: 12.');
    expect(find(element, 'preview').textContent).toBe('c.Volunteers_Schedule_UpToDate');
    expect(find(element, 'create-now').disabled).toBe(true);
  });

  it('says an inactive schedule creates nothing and offers no button', async () => {
    const element = await loaded({ ...MISSING, active: false, canCreate: false, missing: 0 });
    expect(find(element, 'preview').textContent).toBe('c.Volunteers_Schedule_Inactive');
    expect(find(element, 'create-now')).toBeNull();
  });

  it('shows the server message when creating fails', async () => {
    const element = await loaded(MISSING);
    createNow.mockRejectedValue({ body: { message: 'Not created.' } });

    find(element, 'create-now').click();
    await flush();

    expect(find(element, 'error-message').message).toBe('Not created.');
  });
});
