/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import GrantAwardModal from 'c/grantAwardModal';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { updateRecord } from 'lightning/uiRecordApi';

const GRANT = {
  id: 'a01000000000002AAA',
  name: 'Youth Grant',
  amountRequested: 25000,
  awardStartDate: null,
  awardEndDate: null,
  restricted: false
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function render(grant = GRANT) {
  const element = createElement('c-grant-award-modal', { is: GrantAwardModal });
  element.grant = grant;
  element.label = 'Record the Award: Youth Grant';
  document.body.appendChild(element);
  return element;
}

const one = (element, selector) => element.shadowRoot.querySelector(selector);
const change = (input, detail) => input.dispatchEvent(new CustomEvent('change', { detail }));

describe('c-grant-award-modal', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('asks the amount, the award period and Restricted, and saves them', async () => {
    const element = render();
    getObjectInfo.emit({
      fields: {
        Award_Start_Date__c: { label: 'Award Start Date' },
        Award_End_Date__c: { label: 'Award End Date' },
        Restricted__c: { label: 'Restricted' }
      }
    });
    await flush();
    const closed = jest.fn();
    element.addEventListener('close', closed);

    expect(one(element, '[data-id="award-amount"]').value).toBe(25000);
    expect(one(element, '[data-id="award-start"]').label).toBe('Award Start Date');
    expect(one(element, '[data-id="award-restricted"]').label).toBe('Restricted');
    change(one(element, '[data-id="award-amount"]'), { value: '24000' });
    change(one(element, '[data-id="award-start"]'), { value: '2027-01-01' });
    change(one(element, '[data-id="award-end"]'), { value: '2027-12-31' });
    change(one(element, '[data-id="award-restricted"]'), { checked: true });
    await flush();
    one(element, '[data-id="award-save"]').click();
    await flush();

    expect(updateRecord).toHaveBeenCalledWith({
      fields: {
        Id: 'a01000000000002AAA',
        Stage__c: 'Awarded',
        Amount_Awarded__c: 24000,
        Award_Start_Date__c: '2027-01-01',
        Award_End_Date__c: '2027-12-31',
        Restricted__c: true
      }
    });
    expect(closed.mock.calls[0][0].detail).toEqual({ saved: true });
  });

  it('stays open with the reason when the save is refused, and closes on Cancel', async () => {
    updateRecord.mockRejectedValueOnce({
      body: { message: 'An error occurred.', output: { errors: [{ message: 'End before start' }] } }
    });
    const element = render({ ...GRANT, amountRequested: null });
    const closed = jest.fn();
    element.addEventListener('close', closed);
    await flush();
    one(element, '[data-id="award-save"]').click();
    await flush();

    // A blank amount leaves the grant's own amount as it is.
    expect(updateRecord.mock.calls[0][0].fields).not.toHaveProperty('Amount_Awarded__c');
    expect(one(element, '[data-id="award-error"]').message).toBe('End before start');
    expect(closed).not.toHaveBeenCalled();
    one(element, '[data-id="award-cancel"]').click();
    expect(closed).toHaveBeenCalled();
    expect(closed.mock.calls[0][0].detail).toBeFalsy();
  });
});
