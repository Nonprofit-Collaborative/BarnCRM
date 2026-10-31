import { createElement } from 'lwc';
import AiReadinessExport from 'c/aiReadinessExport';
import listObjects from '@salesforce/apex/DataDictionaryController.listObjects';
import describeObject from '@salesforce/apex/DataDictionaryController.describeObject';
import getFindPage from '@salesforce/apex/FindController.getPage';
import exportPage from '@salesforce/apex/FindController.exportPage';
import getChecks from '@salesforce/apex/DataHygieneController.getChecks';
import getPlan from '@salesforce/apex/FieldUtilizationController.getPlan';
import countFields from '@salesforce/apex/FieldUtilizationController.countFields';
import { writeZip } from 'c/xlsxWriter';

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
jest.mock('@salesforce/apex/FindController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.exportPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/DataHygieneController.getChecks', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FieldUtilizationController.getPlan', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/FieldUtilizationController.countFields',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/customPermission/Find_And_Export_Records', () => ({ default: true }), {
  virtual: true
});
jest.mock('c/xlsxWriter', () => ({ writeZip: jest.fn(async () => new Uint8Array([1])) }));
jest.mock(
  '@salesforce/label/c.Core_AiExport_Done',
  () => ({ default: 'Downloaded the pack: {0} kinds of record and {1} records.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_AiExport_Stopped',
  () => ({ default: 'Records stopped at the limit ({0}) for: {1}.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_AiExport_RecordsFailed',
  () => ({ default: 'Records could not be read for: {0}.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_AiExport_ChecksFailed',
  () => ({ default: 'Checks could not be read.' }),
  { virtual: true }
);

const OPTIONS = [
  { value: 'Account', label: 'Account', isDefault: false },
  { value: 'Contact', label: 'Contact', isDefault: true }
];

const CONTACT = {
  objectName: 'Contact',
  objectLabel: 'Contact',
  isCustom: false,
  fields: [
    { fieldName: 'Id', fieldLabel: 'Contact ID', dataType: 'id' },
    { fieldName: 'Birthdate', fieldLabel: 'Birthdate', dataType: 'date' },
    { fieldName: 'Email', fieldLabel: 'Email', dataType: 'email' },
    { fieldName: 'LastName', fieldLabel: 'Last Name', dataType: 'string' },
    { fieldName: 'Level__c', fieldLabel: 'Level', dataType: 'picklist' }
  ]
};

const ROWS = [
  {
    Id: '003A',
    Birthdate: '1980-01-01',
    Email: 'a@example.org',
    LastName: 'Smith',
    Level__c: 'Gold'
  },
  { Id: '003B', Email: 'b@example.org', LastName: 'Smith' }
];

/** Lets every pending promise settle, then renders. */
const flush = async (turns = 30) => {
  if (turns > 0) {
    await Promise.resolve();
    await flush(turns - 1);
  }
};

async function render() {
  const element = createElement('c-ai-readiness-export', { is: AiReadinessExport });
  document.body.appendChild(element);
  listObjects.emit(OPTIONS);
  await flush();
  return element;
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function click(element, id) {
  one(element, id).click();
  await flush(300);
}

function filesOf(call = 0) {
  return Object.fromEntries(writeZip.mock.calls[call][0]);
}

describe('c-ai-readiness-export', () => {
  beforeEach(() => {
    describeObject.mockResolvedValue(CONTACT);
    getFindPage.mockResolvedValue({ exportLimit: 50000 });
    exportPage.mockResolvedValue({ rows: ROWS, done: true, lastId: '003B' });
    getChecks.mockResolvedValue([{ key: 'k', title: 'People Without an Email', count: 2 }]);
    getPlan.mockResolvedValue({ tooLarge: false, chunkSize: 10, fields: [{ fieldName: 'Email' }] });
    countFields.mockResolvedValue({ rows: [{ fieldName: 'Email', filled: 1, total: 2 }] });
    global.URL.createObjectURL = jest.fn(() => 'blob:pack');
    global.URL.revokeObjectURL = jest.fn();
    // jsdom cannot follow a download link.
    jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    global.crypto = global.crypto || {};
    global.crypto.subtle = {
      generateKey: jest.fn(async () => 'key'),
      sign: jest.fn(async (algorithm, key, bytes) => Uint8Array.from(bytes).buffer)
    };
    global.TextEncoder = global.TextEncoder || require('util').TextEncoder;
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.restoreAllMocks();
  });

  it('starts with the default objects chosen and downloads only after review', async () => {
    const element = await render();
    expect(one(element, 'objects').value).toEqual(['Contact']);
    expect(one(element, 'include-records').checked).toBe(true);
    expect(one(element, 'include-checks').checked).toBe(true);
    expect(one(element, 'download').disabled).toBe(true);
    expect(one(element, 'review-first')).not.toBeNull();
    expect(one(element, 'needs-find')).toBeNull();

    await click(element, 'review');

    expect(describeObject).toHaveBeenCalledWith({ objectName: 'Contact' });
    expect(one(element, 'download').disabled).toBe(false);
    const rows = element.shadowRoot.querySelectorAll('tbody tr');
    expect(Array.from(rows).map((row) => row.dataset.key)).toEqual([
      'Contact.Birthdate',
      'Contact.Email',
      'Contact.LastName'
    ]);
    element.shadowRoot
      .querySelectorAll('lightning-combobox')
      .forEach((box) => expect(box.value).toBe('leaveOut'));
  });

  it('builds a pack with the choices applied: kept, masked and left-out fields', async () => {
    const element = await render();
    one(element, 'include-fill-rates').checked = true;
    one(element, 'include-fill-rates').dispatchEvent(new CustomEvent('change'));
    await click(element, 'review');
    const boxes = element.shadowRoot.querySelectorAll('lightning-combobox');
    boxes[1].dispatchEvent(new CustomEvent('change', { detail: { value: 'keep' } }));
    boxes[2].dispatchEvent(new CustomEvent('change', { detail: { value: 'mask' } }));
    await flush();

    await click(element, 'download');

    expect(exportPage).toHaveBeenCalledWith({
      queryJson: JSON.stringify({
        object: 'Contact',
        fields: ['Id', 'Email', 'LastName', 'Level__c']
      }),
      afterId: null
    });
    const files = filesOf();
    expect(Object.keys(files)).toEqual([
      'README.md',
      'schema.json',
      'data-dictionary.csv',
      'data/Contact.csv'
    ]);
    const lines = files['data/Contact.csv']
      .replace(/^\uFEFF/, '')
      .trim()
      .split('\r\n');
    expect(lines[0]).toBe('Id,Email,LastName,Level__c');
    const [first, second] = lines.slice(1).map((line) => line.split(','));
    expect(first.slice(0, 2)).toEqual(['003A', 'a@example.org']);
    expect(first[2]).toMatch(/^masked-[0-9a-f]{10}$/);
    expect(second[2]).toBe(first[2]);
    expect(files['data/Contact.csv']).not.toContain('1980-01-01');
    expect(files['data/Contact.csv']).not.toContain('Smith');

    const schema = JSON.parse(files['schema.json']);
    const email = schema.objects[0].fields.find((field) => field.apiName === 'Email');
    expect(email).toMatchObject({ handling: 'keep', fillRate: 0.5, inRecordFile: true });
    expect(schema.objects[0]).toMatchObject({ recordFile: 'data/Contact.csv', recordCount: 2 });
    expect(schema.dataQuality.checks).toHaveLength(1);
    expect(files['data-dictionary.csv']).toContain('50%');
    expect(one(element, 'notice').textContent).toBe(
      'Downloaded the pack: 1 kinds of record and 2 records.'
    );
    expect(URL.createObjectURL).toHaveBeenCalled();
  });

  it('stops at the Find export limit, and notes records and checks it could not read', async () => {
    getFindPage.mockResolvedValue({ exportLimit: 1 });
    exportPage.mockResolvedValue({ rows: ROWS, done: false, lastId: '003B' });
    getChecks.mockRejectedValue({ body: { message: 'No access' } });
    const element = await render();
    await click(element, 'review');

    await click(element, 'download');

    expect(exportPage).toHaveBeenCalledTimes(1);
    const schema = JSON.parse(filesOf()['schema.json']);
    expect(schema.objects[0]).toMatchObject({ recordCount: 1, recordsStoppedAtLimit: true });
    expect(schema.dataQuality.checks).toEqual([]);
    const notice = one(element, 'notice').textContent;
    expect(notice).toContain('Records stopped at the limit (1) for: Contact.');
    expect(notice).toContain('Checks could not be read.');

    exportPage.mockRejectedValue({ body: { message: 'Refused' } });
    await click(element, 'download');

    expect(Object.keys(filesOf(1))).not.toContain('data/Contact.csv');
    expect(JSON.parse(filesOf(1)['schema.json']).objects[0].recordFile).toBeNull();
    expect(one(element, 'notice').textContent).toContain('Records could not be read for: Contact.');
  });

  it('asks for a new review when the choice of objects changes', async () => {
    const element = await render();
    await click(element, 'review');
    expect(one(element, 'download').disabled).toBe(false);

    one(element, 'objects').dispatchEvent(
      new CustomEvent('change', { detail: { value: ['Account', 'Contact'] } })
    );
    await flush();

    expect(one(element, 'download').disabled).toBe(true);
    expect(one(element, 'review-first')).not.toBeNull();
  });
});
