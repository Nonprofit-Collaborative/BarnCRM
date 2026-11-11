import { createElement } from 'lwc';
import FieldHistoryPanel from 'c/fieldHistoryPanel';
import BarnConfirmModal from 'c/barnConfirmModal';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import getHistory from '@salesforce/apex/FieldHistoryController.getHistory';
import restore from '@salesforce/apex/FieldHistoryController.restore';

jest.mock('@salesforce/apex/FieldHistoryController.getHistory', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FieldHistoryController.restore', () => ({ default: jest.fn() }), {
  virtual: true
});

const RECORD_ID = 'a05000000000001AAA';
const HISTORY_ID = 'a0H000000000001AAA';

const ENTRY = {
  historyId: HISTORY_ID,
  field: 'City__c',
  label: 'City',
  before: 'Springfield',
  after: 'Shelbyville',
  changedAt: '2026-11-10T10:00:00Z',
  changedBy: 'Ann Lee',
  cut: false,
  canRestore: true
};

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function build() {
  const element = createElement('c-field-history-panel', { is: FieldHistoryPanel });
  element.recordId = RECORD_ID;
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-field-history-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws nothing while Field History is off', async () => {
    getHistory.mockResolvedValue({ enabled: false, entries: [] });
    const element = await build();

    expect(getHistory).toHaveBeenCalledWith({ recordId: RECORD_ID });
    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('says when nothing is kept yet', async () => {
    getHistory.mockResolvedValue({ enabled: true, entries: [] });
    const element = await build();

    expect(find(element, 'empty')).not.toBeNull();
    expect(find(element, 'entries')).toBeNull();
  });

  it('lists the changes, marks a cut value and offers Restore only where allowed', async () => {
    getHistory.mockResolvedValue({
      enabled: true,
      entries: [
        ENTRY,
        { ...ENTRY, field: 'Notes__c', label: 'Notes', cut: true, canRestore: false }
      ]
    });
    const element = await build();

    expect(element.shadowRoot.querySelectorAll('[data-id="entry"]')).toHaveLength(2);
    expect(element.shadowRoot.querySelectorAll('[data-id="restore"]')).toHaveLength(1);
    expect(find(element, 'cut')).not.toBeNull();
  });

  it('restores after a confirm and refreshes the record', async () => {
    getHistory.mockResolvedValue({ enabled: true, entries: [ENTRY] });
    restore.mockResolvedValue({ enabled: true, entries: [ENTRY] });
    BarnConfirmModal.open = jest.fn(() => Promise.resolve(true));
    const element = await build();

    find(element, 'restore').click();
    await flushPromises();

    expect(BarnConfirmModal.open).toHaveBeenCalled();
    expect(restore).toHaveBeenCalledWith({
      recordId: RECORD_ID,
      historyId: HISTORY_ID,
      fieldName: 'City__c'
    });
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: RECORD_ID }]);
    expect(find(element, 'status')).not.toBeNull();
  });

  it('changes nothing when the restore is not confirmed', async () => {
    getHistory.mockResolvedValue({ enabled: true, entries: [ENTRY] });
    BarnConfirmModal.open = jest.fn(() => Promise.resolve(false));
    const element = await build();

    find(element, 'restore').click();
    await flushPromises();

    expect(restore).not.toHaveBeenCalled();
  });

  it('shows the server message when the history cannot be read', async () => {
    getHistory.mockRejectedValue({ body: { message: 'This record was not found.' } });
    const element = await build();

    expect(find(element, 'error').message).toBe('This record was not found.');
  });
});
