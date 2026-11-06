// The record test wire adapter is emitted to on purpose, which is how a wired component is
// driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import SessionScheduleSessions from 'c/sessionScheduleSessions';
import BarnConfirmModal from 'c/barnConfirmModal';
import getSchedulePreview from '@salesforce/apex/SessionScheduleController.getSchedulePreview';
import createSessionsNow from '@salesforce/apex/SessionScheduleController.createSessionsNow';
import removeFutureSessions from '@salesforce/apex/SessionScheduleController.removeFutureSessions';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';

jest.mock(
  '@salesforce/apex/SessionScheduleController.getSchedulePreview',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/SessionScheduleController.createSessionsNow',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/SessionScheduleController.removeFutureSessions',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const SCHEDULE_ID = 'a0T000000000001';
const MISSING = {
  active: true,
  turnedOff: false,
  canCreate: true,
  canRemove: true,
  missing: 16,
  through: '2027-04-26',
  createdThrough: null
};

async function flush() {
  for (let i = 0; i < 5; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

async function loaded(preview) {
  getSchedulePreview.mockResolvedValue(preview);
  const element = createElement('c-session-schedule-sessions', { is: SessionScheduleSessions });
  element.recordId = SCHEDULE_ID;
  document.body.appendChild(element);
  getRecord.emit({ fields: { LastModifiedDate: { value: '2027-03-01T12:00:00.000Z' } } });
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-session-schedule-sessions', () => {
  beforeEach(() => {
    setHelpTextForTest({
      Programs_SessionSchedule_Preview: '{0} sessions will be created through {1}.',
      Programs_SessionSchedule_Created: 'Sessions created: {0}.',
      Programs_SessionSchedule_Removed: 'Sessions removed: {0}.'
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    clearHelpTextForTest();
    jest.clearAllMocks();
  });

  it('previews the next run and creates the sessions now', async () => {
    const element = await loaded(MISSING);
    expect(find(element, 'preview').textContent).toMatch(/^16 sessions will be created through /);
    expect(find(element, 'edit-note')).toBeNull();
    createSessionsNow.mockResolvedValue({
      ...MISSING,
      missing: 0,
      created: 16,
      createdThrough: '2027-04-26'
    });

    find(element, 'create-now').click();
    await flush();

    expect(createSessionsNow).toHaveBeenCalledWith({ scheduleId: SCHEDULE_ID });
    expect(find(element, 'result-message').message).toBe('Sessions created: 16.');
    expect(find(element, 'preview').textContent).toBe('c.Programs_SessionSchedule_UpToDate');
    expect(find(element, 'edit-note').textContent).toBe('c.Programs_SessionSchedule_EditNote');
    expect(find(element, 'create-now').disabled).toBe(true);
  });

  it('removes future sessions only after the confirm', async () => {
    const element = await loaded({ ...MISSING, missing: 0, createdThrough: '2027-04-26' });
    BarnConfirmModal.open.mockResolvedValueOnce(false);
    find(element, 'remove-future').click();
    await flush();
    expect(removeFutureSessions).not.toHaveBeenCalled();

    BarnConfirmModal.open.mockResolvedValueOnce(true);
    removeFutureSessions.mockResolvedValue({ ...MISSING, missing: 0, removed: 6 });
    find(element, 'remove-future').click();
    await flush();

    expect(BarnConfirmModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ confirmVariant: 'destructive' })
    );
    expect(removeFutureSessions).toHaveBeenCalledWith({ scheduleId: SCHEDULE_ID });
    expect(find(element, 'result-message').message).toBe('Sessions removed: 6.');
  });

  it('says an inactive or turned-off schedule creates nothing, and shows a failure', async () => {
    let element = await loaded({ ...MISSING, active: false, canCreate: false, canRemove: false });
    expect(find(element, 'preview').textContent).toBe('c.Programs_SessionSchedule_Inactive');
    expect(find(element, 'create-now')).toBeNull();
    expect(find(element, 'remove-future')).toBeNull();
    document.body.removeChild(element);

    element = await loaded({ ...MISSING, turnedOff: true, canCreate: false });
    expect(find(element, 'preview').textContent).toBe('c.Programs_SessionSchedule_TurnedOff');
    document.body.removeChild(element);

    element = await loaded({ ...MISSING, missing: 1 });
    expect(find(element, 'preview').textContent).toBe('c.Programs_SessionSchedule_PreviewOne');
    createSessionsNow.mockRejectedValue({ body: { message: 'Not created.' } });
    find(element, 'create-now').click();
    await flush();
    expect(find(element, 'error-message').message).toBe('Not created.');
  });

  it('shows the default failure when the preview does not load', async () => {
    getSchedulePreview.mockRejectedValue({});
    const element = createElement('c-session-schedule-sessions', { is: SessionScheduleSessions });
    element.recordId = SCHEDULE_ID;
    document.body.appendChild(element);
    getRecord.emit({ fields: { LastModifiedDate: { value: '2027-03-01T12:00:00.000Z' } } });
    await flush();
    expect(find(element, 'error-message').message).toBe('c.Programs_Fail_Schedule');
  });
});
