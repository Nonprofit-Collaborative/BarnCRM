/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import GrantAwardModal from 'c/grantAwardModal';
import recordAward from '@salesforce/apex/GrantPipelineController.recordAward';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

jest.mock('@salesforce/apex/GrantPipelineController.recordAward', () => ({ default: jest.fn() }), {
  virtual: true
});

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
    recordAward.mockResolvedValue();
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

    expect(recordAward).toHaveBeenCalledWith({
      grantId: 'a01000000000002AAA',
      amountAwarded: 24000,
      startDate: '2027-01-01',
      endDate: '2027-12-31',
      restricted: true
    });
    expect(closed.mock.calls[0][0].detail).toEqual({ saved: true });
  });

  it('stays open with the reason when the save is refused, and closes on Cancel', async () => {
    recordAward.mockRejectedValue({ body: { message: 'End before start' } });
    const element = render({ ...GRANT, amountRequested: null });
    const closed = jest.fn();
    element.addEventListener('close', closed);
    await flush();
    one(element, '[data-id="award-save"]').click();
    await flush();

    expect(recordAward.mock.calls[0][0].amountAwarded).toBeNull();
    expect(one(element, '[data-id="award-error"]').message).toBe('End before start');
    expect(closed).not.toHaveBeenCalled();
    one(element, '[data-id="award-cancel"]').click();
    expect(closed).toHaveBeenCalled();
    expect(closed.mock.calls[0][0].detail).toBeFalsy();
  });
});
