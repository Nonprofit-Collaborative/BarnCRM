import { createElement } from 'lwc';
import PicklistUsage from 'c/picklistUsage';
import getPicklistPlan from '@salesforce/apex/FieldUtilizationController.getPicklistPlan';
import getPicklistUsage from '@salesforce/apex/FieldUtilizationController.getPicklistUsage';

jest.mock(
  '@salesforce/apex/FieldUtilizationController.getPicklistPlan',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/FieldUtilizationController.getPicklistUsage',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_PicklistUsage_Progress', () => ({ default: '{0} of {1}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_PicklistUsage_Truncated', () => ({ default: 'Cut: {0}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_PicklistUsage_NotChecked', () => ({ default: 'Failed: {0}' }), {
  virtual: true
});

const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function mount(objectName = 'Account') {
  const element = createElement('c-picklist-usage', { is: PicklistUsage });
  element.objectName = objectName;
  document.body.appendChild(element);
  return element;
}

const query = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

afterEach(() => {
  while (document.body.firstChild) {
    document.body.removeChild(document.body.firstChild);
  }
  jest.clearAllMocks();
});

describe('c-picklist-usage', () => {
  it('reads nothing until the button is pressed', async () => {
    mount();
    await flush();
    expect(getPicklistPlan).not.toHaveBeenCalled();
  });

  it('asks the fields in chunks and lists every value with its status', async () => {
    getPicklistPlan.mockResolvedValue({
      fields: [{ fieldName: 'A__c' }, { fieldName: 'B__c' }, { fieldName: 'C__c' }],
      chunkSize: 2,
      tooLarge: false
    });
    getPicklistUsage
      .mockResolvedValueOnce({
        rows: [
          {
            key: 'A__c|x',
            fieldLabel: 'A',
            valueLabel: 'X',
            status: 'Inactive',
            records: 4,
            lastUsed: '2026-01-01T00:00:00Z'
          }
        ],
        failed: [],
        truncated: ['A']
      })
      .mockResolvedValueOnce({
        rows: [
          { key: 'C__c|y', fieldLabel: 'C', valueLabel: 'Y', status: 'NeverUsed', records: 0 }
        ],
        failed: ['B'],
        truncated: []
      });
    const element = mount();
    query(element, 'show').click();
    await flush();
    await flush();
    expect(getPicklistUsage).toHaveBeenCalledTimes(2);
    expect(getPicklistUsage.mock.calls[0][0].fieldNames).toEqual(['A__c', 'B__c']);
    expect(getPicklistUsage.mock.calls[1][0].fieldNames).toEqual(['C__c']);
    const table = query(element, 'results');
    expect(table.data).toHaveLength(2);
    expect(table.data[0].statusLabel).toBe('c.Core_PicklistUsage_StatusInactive');
    expect(query(element, 'truncated').textContent).toBe('Cut: A');
    expect(query(element, 'not-checked').textContent).toBe('Failed: B');
  });

  it('says so when there are no picklist fields', async () => {
    getPicklistPlan.mockResolvedValue({ fields: [], chunkSize: 20, tooLarge: false });
    const element = mount();
    query(element, 'show').click();
    await flush();
    await flush();
    expect(query(element, 'no-fields')).not.toBeNull();
    expect(getPicklistUsage).not.toHaveBeenCalled();
  });

  it('shows the server message when the call fails', async () => {
    getPicklistPlan.mockRejectedValue({ body: { message: 'Refused.' } });
    const element = mount();
    query(element, 'show').click();
    await flush();
    await flush();
    expect(query(element, 'error').textContent).toBe('Refused.');
  });

  it('clears the table when another object is chosen', async () => {
    getPicklistPlan.mockResolvedValue({ fields: [{ fieldName: 'A__c' }], chunkSize: 20 });
    getPicklistUsage.mockResolvedValue({
      rows: [{ key: 'k', fieldLabel: 'A', valueLabel: 'X', status: 'Active', records: 1 }],
      failed: [],
      truncated: []
    });
    const element = mount();
    query(element, 'show').click();
    await flush();
    await flush();
    expect(query(element, 'results')).not.toBeNull();
    element.objectName = 'Contact';
    await flush();
    expect(query(element, 'results')).toBeNull();
  });
});
