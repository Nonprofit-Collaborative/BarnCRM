import { createElement } from 'lwc';
import DataDictionary from 'c/dataDictionary';
import listObjects from '@salesforce/apex/DataDictionaryController.listObjects';
import describeObject from '@salesforce/apex/DataDictionaryController.describeObject';
import getPlan from '@salesforce/apex/FieldUtilizationController.getPlan';
import countFields from '@salesforce/apex/FieldUtilizationController.countFields';

jest.mock(
  '@salesforce/apex/DataDictionaryController.listObjects',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/DataDictionaryController.describeObject',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/FieldUtilizationController.getPlan', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/FieldUtilizationController.countFields',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_DataDictionary_Progress',
  () => ({ default: 'Described {0} of {1} kinds of record.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_DataDictionary_NotCounted',
  () => ({ default: 'Fill rates not counted for: {0}.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_DataDictionary_Downloaded',
  () => ({ default: 'Downloaded {0} fields.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_DataDictionary_Yes', () => ({ default: 'Yes' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_DataDictionary_No', () => ({ default: 'No' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_DataDictionary_ColFillRate', () => ({ default: 'Fill Rate' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_DataDictionary_ColField', () => ({ default: 'Field' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_DataDictionary_ColHelpText', () => ({ default: 'Help Text' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_DataDictionary_ColObject', () => ({ default: 'Object' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_DataDictionary_ColObjectApiName',
  () => ({ default: 'Object API Name' }),
  { virtual: true }
);

const OPTIONS = [
  { value: 'Account', label: 'Account', isDefault: true },
  { value: 'Contact', label: 'Contact', isDefault: true },
  { value: 'Thing__c', label: 'Thing', isDefault: false }
];

const field = (name, extra = {}) => ({
  fieldLabel: name,
  fieldName: name,
  dataType: 'string',
  length: 80,
  precision: null,
  required: false,
  isUnique: false,
  externalId: false,
  isCustom: false,
  picklistValues: null,
  helpText: null,
  formula: null,
  relatedTo: null,
  ...extra
});

const dictionary = (objectName, fields) => ({
  objectName,
  objectLabel: objectName,
  isCustom: false,
  fields
});

const countRow = (fieldName, recordType, filled, total) => ({
  fieldName,
  recordType,
  filled,
  total
});

/** Lets every pending promise settle, then renders. */
const flush = async (turns = 30) => {
  if (turns > 0) {
    await Promise.resolve();
    await flush(turns - 1);
  }
};

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

function render() {
  const element = createElement('c-data-dictionary', { is: DataDictionary });
  document.body.appendChild(element);
  listObjects.emit(OPTIONS);
  return element;
}

function tickFillRates(element) {
  const box = find(element, 'fill-rates');
  box.checked = true;
  box.dispatchEvent(new CustomEvent('change'));
}

async function build(element) {
  find(element, 'build').click();
  await flush();
}

/** Clicks Download CSV and returns the file's text and name. */
async function downloadedCsv(element) {
  let blob;
  let name;
  URL.createObjectURL = jest.fn((made) => {
    blob = made;
    return 'blob:test';
  });
  URL.revokeObjectURL = jest.fn();
  const click = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function () {
    name = this.download;
  });
  find(element, 'download').click();
  await flush();
  click.mockRestore();
  const bytes = await new Promise((resolve) => {
    const reader = new FileReader();
    // Read as bytes: reading as text would drop the byte-order mark.
    reader.onload = () => resolve(Array.from(new Uint8Array(reader.result)));
    reader.readAsArrayBuffer(blob);
  });
  const hasBom = bytes.slice(0, 3).join(',') === '239,187,191';
  // The test text is plain ASCII after the byte-order mark.
  const text = String.fromCharCode(...bytes.slice(hasBom ? 3 : 0));
  return { text, name, hasBom };
}

describe('c-data-dictionary', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.resetAllMocks();
  });

  it('offers every object, starts with the default ones chosen and describes nothing yet', async () => {
    const element = render();
    await flush();

    const picker = find(element, 'objects');
    expect(picker.options.map((option) => option.value)).toEqual([
      'Account',
      'Contact',
      'Thing__c'
    ]);
    expect(picker.options[2].label).toBe('Thing (Thing__c)');
    expect(picker.value).toEqual(['Account', 'Contact']);
    expect(describeObject).not.toHaveBeenCalled();
    expect(find(element, 'empty')).not.toBeNull();
    expect(find(element, 'download').disabled).toBe(true);
    expect(find(element, 'fill-rates').checked).toBe(false);
  });

  it('describes each chosen object in turn and shows a row per field', async () => {
    describeObject
      .mockResolvedValueOnce(
        dictionary('Account', [field('Name', { required: true }), field('Phone')])
      )
      .mockResolvedValueOnce(dictionary('Contact', [field('LastName')]));
    const element = render();
    await build(element);

    expect(describeObject).toHaveBeenNthCalledWith(1, { objectName: 'Account' });
    expect(describeObject).toHaveBeenNthCalledWith(2, { objectName: 'Contact' });
    expect(getPlan).not.toHaveBeenCalled();
    const table = find(element, 'results');
    expect(table.data.map((row) => row.key)).toEqual([
      'Account|Name',
      'Account|Phone',
      'Contact|LastName'
    ]);
    expect(table.data[0]).toMatchObject({ required: 'Yes', isUnique: 'No', length: 80 });
    expect(table.columns.map((column) => column.fieldName)).not.toContain('fillRate');
    expect(find(element, 'empty')).toBeNull();
    expect(find(element, 'download').disabled).toBe(false);
  });

  it('cannot build with nothing chosen', async () => {
    const element = render();
    await flush();
    find(element, 'objects').dispatchEvent(new CustomEvent('change', { detail: { value: [] } }));
    await flush();

    expect(find(element, 'build').disabled).toBe(true);
  });

  it('adds fill rates from Field Utilization across record types, within its limits', async () => {
    describeObject
      .mockResolvedValueOnce(dictionary('Account', [field('Phone'), field('Fax'), field('Id')]))
      .mockResolvedValueOnce(dictionary('Contact', [field('Email')]));
    getPlan
      .mockResolvedValueOnce({
        total: 100,
        tooLarge: false,
        chunkSize: 2,
        fields: [{ fieldName: 'Phone' }, { fieldName: 'Fax' }]
      })
      .mockResolvedValueOnce({ total: 5000000, tooLarge: true, fields: [] });
    countFields.mockResolvedValueOnce({
      rows: [
        countRow('Phone', 'Household', 30, 60),
        countRow('Phone', 'Organization', 30, 40),
        countRow('Fax', '', 0, 100)
      ],
      failed: []
    });
    const element = render();
    tickFillRates(element);
    await flush();
    await build(element);

    expect(getPlan).toHaveBeenCalledWith({ objectName: 'Account' });
    expect(countFields).toHaveBeenCalledTimes(1);
    expect(countFields).toHaveBeenCalledWith({
      objectName: 'Account',
      fieldNames: ['Phone', 'Fax']
    });
    const rows = find(element, 'results').data;
    expect(rows.find((row) => row.key === 'Account|Phone').fillRate).toBeCloseTo(0.6);
    expect(rows.find((row) => row.key === 'Account|Fax').fillRate).toBe(0);
    expect(rows.find((row) => row.key === 'Account|Id').fillRate).toBeNull();
    expect(rows.find((row) => row.key === 'Contact|Email').fillRate).toBeNull();
    expect(find(element, 'results').columns.map((column) => column.fieldName)).toContain(
      'fillRate'
    );
    expect(find(element, 'not-counted').textContent).toBe('Fill rates not counted for: Contact.');
  });

  it('names an object whose fill rates failed and keeps its dictionary rows', async () => {
    describeObject.mockResolvedValueOnce(dictionary('Account', [field('Phone')]));
    getPlan.mockRejectedValueOnce({ body: { message: 'boom' } });
    const element = render();
    find(element, 'objects').dispatchEvent(
      new CustomEvent('change', { detail: { value: ['Account'] } })
    );
    tickFillRates(element);
    await flush();
    await build(element);

    expect(find(element, 'results').data).toHaveLength(1);
    expect(find(element, 'not-counted').textContent).toBe('Fill rates not counted for: Account.');
    expect(find(element, 'error')).toBeNull();
  });

  it('shows the server message when a describe fails', async () => {
    describeObject.mockRejectedValueOnce({ body: { message: 'You need the permission.' } });
    const element = render();
    await build(element);

    expect(find(element, 'error').textContent).toContain('You need the permission.');
    expect(find(element, 'download').disabled).toBe(true);
  });

  it('downloads a CSV that quotes commas, quotes and line breaks and defuses formulas', async () => {
    describeObject.mockResolvedValueOnce(
      dictionary('Account', [
        field('Rating', {
          fieldLabel: 'Rating, "Overall"',
          picklistValues: 'Hot; Warm; Cold',
          helpText: 'Line one\nLine two',
          formula: '=IF(A,"x","y")'
        })
      ])
    );
    const element = render();
    find(element, 'objects').dispatchEvent(
      new CustomEvent('change', { detail: { value: ['Account'] } })
    );
    await flush();
    await build(element);

    const { text, name, hasBom } = await downloadedCsv(element);

    expect(name).toMatch(/^Data_Dictionary-\d{4}-\d{2}-\d{2}\.csv$/);
    expect(hasBom).toBe(true);
    const lines = text.split('\r\n');
    expect(lines[0].startsWith('Object,Object API Name,Field,')).toBe(true);
    expect(lines[0]).not.toContain('Fill Rate');
    expect(text).toContain('"Rating, ""Overall"""');
    expect(text).toContain('"Line one\nLine two"');
    expect(text).toContain('"\'=IF(A,""x"",""y"")"');
    expect(find(element, 'notice').textContent).toBe('Downloaded 1 fields.');
  });

  it('puts fill rates in the CSV as percentages, blank when not counted', async () => {
    describeObject.mockResolvedValueOnce(dictionary('Account', [field('Phone'), field('Fax')]));
    getPlan.mockResolvedValueOnce({
      total: 3,
      tooLarge: false,
      chunkSize: 40,
      fields: [{ fieldName: 'Phone' }]
    });
    countFields.mockResolvedValueOnce({ rows: [countRow('Phone', '', 1, 3)], failed: [] });
    const element = render();
    find(element, 'objects').dispatchEvent(
      new CustomEvent('change', { detail: { value: ['Account'] } })
    );
    tickFillRates(element);
    await flush();
    await build(element);

    const { text } = await downloadedCsv(element);

    const lines = text.split('\r\n');
    expect(lines[0].endsWith(',Fill Rate')).toBe(true);
    expect(lines[1].endsWith(',33.3%')).toBe(true);
    expect(lines[2].endsWith(',')).toBe(true);
  });
});
