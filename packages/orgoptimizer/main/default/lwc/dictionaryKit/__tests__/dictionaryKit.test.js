import getPlan from '@salesforce/apex/FieldUtilizationController.getPlan';
import countFields from '@salesforce/apex/FieldUtilizationController.countFields';
import {
  automationCsv,
  dictionaryCsv,
  readFillRates,
  sharesFrom,
  toAutomationRow,
  toRow
} from 'c/dictionaryKit';

jest.mock('@salesforce/apex/FieldUtilizationController.getPlan', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/FieldUtilizationController.countFields',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const OBJECT = { objectName: 'Gift__c', objectLabel: 'Gift' };

describe('c/dictionaryKit', () => {
  afterEach(() => jest.clearAllMocks());

  it('builds a field row with yes and no words and blanks for what is missing', () => {
    const row = toRow(
      OBJECT,
      { fieldLabel: 'Amount', fieldName: 'Amount__c', dataType: 'Currency', required: true },
      undefined
    );
    expect(row).toMatchObject({
      key: 'Gift__c|Amount__c',
      objectLabel: 'Gift',
      length: null,
      precision: '',
      required: 'c.Core_AccessExplorer_Yes',
      isUnique: 'c.Core_DataDictionary_No',
      picklistValues: '',
      fillRate: null
    });
    expect(toRow(OBJECT, { fieldName: 'X__c', length: 0 }, 0.5)).toMatchObject({
      length: 0,
      fillRate: 0.5
    });
  });

  it('writes the CSV, with the fill rate as a percent only when asked', () => {
    const rows = [toRow(OBJECT, { fieldLabel: 'Amount', fieldName: 'Amount__c' }, 0.1234)];
    const withRates = dictionaryCsv(rows, true);
    expect(withRates).toContain('Gift__c');
    expect(withRates).toContain('12.3%');
    expect(dictionaryCsv(rows, false)).not.toContain('12.3%');
  });

  it('names a trigger or flow row and writes the automation CSV', () => {
    const trigger = toAutomationRow({ automationType: 'ApexTrigger', name: 'GiftTrigger' });
    expect(trigger).toMatchObject({
      typeLabel: 'c.Core_DataDictionary_TypeApexTrigger',
      detail: '',
      apiVersion: null
    });
    const flow = toAutomationRow({ automationType: 'Flow', apiVersion: 67, detail: 'After save' });
    expect(flow.typeLabel).toBe('c.Core_DataDictionary_TypeFlow');
    expect(flow.apiVersion).toBe(67);
    const csv = automationCsv([{ ...trigger, objectLabel: 'Gift', objectName: 'Gift__c' }]);
    expect(csv).toContain('GiftTrigger');
    expect(csv).toContain('Gift__c');
  });

  it('sums fill counts across record types and skips fields with no records', () => {
    const shares = sharesFrom([
      { fieldName: 'A__c', filled: 1, total: 4 },
      { fieldName: 'A__c', filled: 1, total: 4 },
      { fieldName: 'B__c', filled: 0, total: 0 },
      { fieldName: 'C__c' }
    ]);
    expect(shares.get('A__c')).toBe(0.25);
    expect(shares.has('B__c')).toBe(false);
    expect(shares.has('C__c')).toBe(false);
  });

  it('counts fill rates one chunk at a time from the plan', async () => {
    getPlan.mockResolvedValue({
      chunkSize: 1,
      fields: [{ fieldName: 'A__c' }, { fieldName: 'B__c' }]
    });
    countFields
      .mockResolvedValueOnce({ rows: [{ fieldName: 'A__c', filled: 2, total: 2 }] })
      .mockResolvedValueOnce({});
    const shares = await readFillRates('Gift__c');
    expect(countFields).toHaveBeenCalledTimes(2);
    expect(countFields).toHaveBeenNthCalledWith(2, { objectName: 'Gift__c', fieldNames: ['B__c'] });
    expect(shares.get('A__c')).toBe(1);
  });

  it('gives null for an object too large to count, and stops when no longer current', async () => {
    getPlan.mockResolvedValueOnce({ tooLarge: true });
    expect(await readFillRates('Gift__c')).toBeNull();
    getPlan.mockResolvedValueOnce({ fields: [{ fieldName: 'A__c' }] });
    const shares = await readFillRates('Gift__c', () => false);
    expect(countFields).not.toHaveBeenCalled();
    expect(shares.size).toBe(0);
  });
});
