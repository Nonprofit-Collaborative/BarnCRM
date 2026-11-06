// The getRecord test adapter is emitted to on purpose, which is how a wired component is
// driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import Toast from 'lightning/toast';
import { getRecord, notifyRecordUpdateAvailable, updateRecord } from 'lightning/uiRecordApi';
import GivingQuickStatus from 'c/givingQuickStatus';
import GiftCancelPending from 'c/giftCancelPending';
import { QUICK_STATUS, fieldId, quickStatus, updateInput } from '../quickStatusActions';

const GIFT_ID = 'a01000000000001AAA';

function build(action) {
  const element = createElement('c-giving-quick-status', { is: GivingQuickStatus });
  element.recordId = GIFT_ID;
  element.action = action;
  document.body.appendChild(element);
  return element;
}

function record(field, value) {
  return { id: GIFT_ID, fields: { [field]: { value } } };
}

function pick(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function settle() {
  for (let i = 0; i < 4; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}

describe('c-giving-quick-status', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('asks once, then cancels a pending gift and closes', async () => {
    const element = build('cancelPendingGift');
    const closed = jest.fn();
    element.addEventListener('lightning__closeactionscreen', closed);
    const toast = jest.spyOn(Toast, 'show');
    getRecord.emit(record('Status__c', 'Pending'));
    await settle();

    expect(pick(element, 'title').textContent).toBe('c.Giving_QuickStatus_CancelPendingGift');
    expect(pick(element, 'confirm-text').textContent).toBe(
      'c.Giving_QuickStatus_CancelPendingGift_Confirm'
    );
    expect(pick(element, 'confirm').variant).toBe('destructive');

    pick(element, 'confirm').click();
    await settle();

    expect(updateRecord).toHaveBeenCalledWith({
      fields: { Id: GIFT_ID, Status__c: 'Cancelled' }
    });
    expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: GIFT_ID }]);
    expect(toast.mock.calls[0][0]).toEqual({
      label: 'c.Giving_QuickStatus_CancelPendingGift_Done',
      variant: 'success'
    });
    expect(closed).toHaveBeenCalled();
  });

  it('says why and offers only Close where the change does not apply', async () => {
    const element = build('cancelPendingGift');
    getRecord.emit(record('Status__c', 'Received'));
    await settle();

    expect(pick(element, 'confirm')).toBeNull();
    expect(pick(element, 'not-applicable').message).toBe(
      'c.Giving_QuickStatus_CancelPendingGift_NotApplicable'
    );
    expect(pick(element, 'dismiss').label).toBe('c.Core_BulkUpdate_Close');
  });

  it('shows the rule that refused the save and stays open', async () => {
    updateRecord.mockRejectedValueOnce({
      body: { message: 'Only a Pending gift can be cancelled.' }
    });
    const element = build('cancelPendingGift');
    const closed = jest.fn();
    element.addEventListener('lightning__closeactionscreen', closed);
    getRecord.emit(record('Status__c', 'Pending'));
    await settle();

    pick(element, 'confirm').click();
    await settle();

    expect(pick(element, 'error').message).toBe('Only a Pending gift can be cancelled.');
    expect(closed).not.toHaveBeenCalled();
  });

  it('closes without saving on Cancel', async () => {
    const element = build('reopenAsk');
    const closed = jest.fn();
    element.addEventListener('lightning__closeactionscreen', closed);
    getRecord.emit(record('Outcome__c', 'Declined'));
    await settle();

    expect(pick(element, 'dismiss').label).toBe('c.Core_CmdtManager_CancelButton');
    pick(element, 'dismiss').click();

    expect(updateRecord).not.toHaveBeenCalled();
    expect(closed).toHaveBeenCalled();
  });

  it('is opened by the thin quick action with its own action name', async () => {
    const element = createElement('c-gift-cancel-pending', { is: GiftCancelPending });
    element.recordId = GIFT_ID;
    document.body.appendChild(element);
    await settle();

    const inner = element.shadowRoot.querySelector('c-giving-quick-status');
    expect(inner.action).toBe('cancelPendingGift');
    expect(inner.recordId).toBe(GIFT_ID);
  });
});

describe('quickStatusActions', () => {
  it('offers each change only from the values where it makes sense', () => {
    expect(QUICK_STATUS.cancelPendingGift.appliesFrom('Pending')).toBe(true);
    expect(QUICK_STATUS.cancelPendingGift.appliesFrom('Received')).toBe(false);
    expect(QUICK_STATUS.thankAgain.appliesFrom('Acknowledged')).toBe(true);
    expect(QUICK_STATUS.thankAgain.appliesFrom('Do not acknowledge')).toBe(true);
    expect(QUICK_STATUS.thankAgain.appliesFrom('To acknowledge')).toBe(false);
    expect(QUICK_STATUS.doNotThank.appliesFrom('To acknowledge')).toBe(true);
    expect(QUICK_STATUS.doNotThank.appliesFrom('Acknowledged')).toBe(false);
    expect(QUICK_STATUS.reopenAsk.appliesFrom('Won')).toBe(true);
    expect(QUICK_STATUS.reopenAsk.appliesFrom('Open')).toBe(false);
    expect(QUICK_STATUS.markPlanComplete.appliesFrom('Running')).toBe(true);
    expect(QUICK_STATUS.markPlanComplete.appliesFrom('Cancelled')).toBe(false);
  });

  it('names the field it reads and the one-field update it saves', () => {
    const definition = quickStatus('markPlanComplete');
    expect(fieldId(definition)).toBe('Stewardship_Plan__c.Status__c');
    expect(updateInput(definition, 'a02')).toEqual({
      fields: { Id: 'a02', Status__c: 'Complete' }
    });
    expect(quickStatus('toString')).toBeUndefined();
  });
});
