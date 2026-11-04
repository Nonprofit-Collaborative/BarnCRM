import { createElement } from 'lwc';
import PicklistUsage from 'c/picklistUsage';
import getPicklistPlan from '@salesforce/apex/FieldUtilizationController.getPicklistPlan';
import getPicklistUsage from '@salesforce/apex/FieldUtilizationController.getPicklistUsage';
import getPicklistLastUsed from '@salesforce/apex/FieldUtilizationController.getPicklistLastUsed';

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
jest.mock(
  '@salesforce/apex/FieldUtilizationController.getPicklistLastUsed',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_PicklistUsage_Progress', () => ({ default: '{0} of {1}' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_PicklistUsage_DatesProgress',
  () => ({ default: 'Dates {0} of {1}' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_PicklistUsage_DatesStopped',
  () => ({ default: 'Stopped {0} of {1}: {2}' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_PicklistUsage_Truncated', () => ({ default: 'Cut: {0}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_PicklistUsage_NotChecked', () => ({ default: 'Failed: {0}' }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
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

  describe('Last Used on a large kind of record', () => {
    const plan = { fields: [{ fieldName: 'A__c' }], chunkSize: 20, total: 3, tooLarge: false };
    const counts = {
      rows: [
        {
          key: 'A__c|x',
          fieldName: 'A__c',
          fieldLabel: 'A',
          value: 'x',
          status: 'Active',
          records: 2
        },
        {
          key: 'A__c|',
          fieldName: 'A__c',
          fieldLabel: 'A',
          value: '',
          status: 'NoValue',
          records: 1
        }
      ],
      failed: [],
      truncated: [],
      datesPending: ['A__c']
    };
    const settle = async () => {
      for (let i = 0; i < 8; i++) {
        // eslint-disable-next-line no-await-in-loop
        await flush();
      }
    };

    it('reads the dates in chunks of records and keeps the newest per value', async () => {
      getPicklistPlan.mockResolvedValue(plan);
      getPicklistUsage.mockResolvedValue(counts);
      getPicklistLastUsed
        .mockResolvedValueOnce({
          dates: [{ fieldName: 'A__c', value: 'x', lastUsed: '2024-01-01T00:00:00.000Z' }],
          cut: [],
          lastId: 'id2',
          read: 2,
          done: false
        })
        .mockResolvedValueOnce({
          dates: [
            { fieldName: 'A__c', value: 'x', lastUsed: '2025-01-01T00:00:00.000Z' },
            { fieldName: 'A__c', value: '', lastUsed: '2023-01-01T00:00:00.000Z' }
          ],
          cut: [],
          lastId: 'id3',
          read: 1,
          done: true
        });
      const element = mount();
      query(element, 'show').click();
      await settle();
      expect(getPicklistLastUsed).toHaveBeenCalledTimes(2);
      expect(getPicklistLastUsed.mock.calls[0][0].afterId).toBeNull();
      expect(getPicklistLastUsed.mock.calls[1][0].afterId).toBe('id2');
      const data = query(element, 'results').data;
      expect(data.find((row) => row.value === 'x').lastUsed).toBe('2025-01-01T00:00:00.000Z');
      expect(data.find((row) => row.value === '').lastUsed).toBe('2023-01-01T00:00:00.000Z');
      expect(query(element, 'dates-stopped')).toBeNull();
    });

    it('keeps what was read when a chunk fails and retries from there', async () => {
      getPicklistPlan.mockResolvedValue(plan);
      getPicklistUsage.mockResolvedValue(counts);
      getPicklistLastUsed
        .mockResolvedValueOnce({
          dates: [{ fieldName: 'A__c', value: 'x', lastUsed: '2024-01-01T00:00:00.000Z' }],
          cut: [],
          lastId: 'id2',
          read: 2,
          done: false
        })
        .mockRejectedValueOnce({ body: { message: 'Timed out.' } })
        .mockResolvedValueOnce({ dates: [], cut: [], lastId: 'id3', read: 1, done: true });
      const element = mount();
      query(element, 'show').click();
      await settle();
      expect(query(element, 'dates-stopped').textContent).toContain('Stopped 2 of 3: A');
      query(element, 'retry').click();
      await settle();
      expect(getPicklistLastUsed.mock.calls[2][0].afterId).toBe('id2');
      expect(query(element, 'dates-stopped')).toBeNull();
      const data = query(element, 'results').data;
      expect(data.find((row) => row.value === 'x').lastUsed).toBe('2024-01-01T00:00:00.000Z');
    });

    it('stops after the chunk in flight when Cancel is pressed', async () => {
      getPicklistPlan.mockResolvedValue(plan);
      getPicklistUsage.mockResolvedValue(counts);
      let release;
      getPicklistLastUsed.mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            release = () => resolve({ dates: [], cut: [], lastId: 'id1', read: 1, done: false });
          })
      );
      const element = mount();
      query(element, 'show').click();
      await settle();
      expect(query(element, 'dates-progress').textContent).toContain('Dates 0 of 3');
      query(element, 'cancel').click();
      release();
      await settle();
      expect(getPicklistLastUsed).toHaveBeenCalledTimes(1);
      expect(query(element, 'dates-stopped').textContent).toContain('Stopped 1 of 3');
      expect(query(element, 'retry')).not.toBeNull();
    });
  });
});
