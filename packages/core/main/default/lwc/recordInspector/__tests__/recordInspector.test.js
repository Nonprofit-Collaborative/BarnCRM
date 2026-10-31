import { createElement } from 'lwc';
import RecordInspector from 'c/recordInspector';
import inspect from '@salesforce/apex/RecordInspectorController.inspect';
import { filterRows, normalize } from '../inspectorRows';

jest.mock('@salesforce/apex/RecordInspectorController.inspect', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/label/c.Core_RecordInspector_Count', () => ({ default: '{0} fields' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_RecordInspector_CountFiltered',
  () => ({ default: '{0} of {1} fields' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_RecordInspector_Copied', () => ({ default: 'Copied {0}' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_RecordInspector_Copy', () => ({ default: 'Copy' }), {
  virtual: true
});

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});

const INSPECTION = {
  recordId: '003000000000001AAA',
  objectApiName: 'Contact',
  objectLabel: 'Contact',
  fieldsCut: false,
  fields: [
    { label: 'Last Name', apiName: 'LastName', type: 'STRING', isCustom: false, value: 'Garcia' },
    { label: 'Email', apiName: 'Email', type: 'EMAIL', isCustom: false, value: 'a@b.example' },
    { label: 'Fax', apiName: 'Fax', type: 'PHONE', isCustom: false, value: null },
    {
      label: 'Notes',
      apiName: 'Notes__c',
      type: 'TEXTAREA',
      isCustom: true,
      value: 'x'.repeat(10),
      truncated: true
    }
  ]
};

const flush = () => Promise.resolve();

function mount() {
  const element = createElement('c-record-inspector', { is: RecordInspector });
  element.recordId = INSPECTION.recordId;
  document.body.appendChild(element);
  return element;
}

const q = (element, selector) => element.shadowRoot.querySelector(selector);
const rowNames = (element) =>
  Array.from(element.shadowRoot.querySelectorAll('tr[data-row]')).map((r) => r.dataset.row);

async function open(element) {
  q(element, '[data-id="inspect-button"]').click();
  await flush();
  await flush();
}

describe('c-record-inspector', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('reads nothing until asked, then lists every field', async () => {
    inspect.mockResolvedValue(INSPECTION);
    const element = mount();
    expect(inspect).not.toHaveBeenCalled();
    expect(q(element, '[data-id="intro"]')).not.toBeNull();

    await open(element);

    expect(inspect).toHaveBeenCalledWith({ recordId: INSPECTION.recordId });
    expect(rowNames(element)).toEqual(['LastName', 'Email', 'Fax', 'Notes__c']);
    expect(q(element, '[data-id="count"]').textContent).toBe('4 fields');
    expect(q(element, '[data-id="intro"]')).toBeNull();
  });

  it('shows an empty field as empty and marks a shortened value', async () => {
    inspect.mockResolvedValue(INSPECTION);
    const element = mount();
    await open(element);

    const fax = q(element, 'tr[data-row="Fax"]');
    expect(fax.querySelector('[data-id="value"]')).toBeNull();
    const notes = q(element, 'tr[data-row="Notes__c"]');
    expect(notes.querySelector('lightning-badge')).not.toBeNull();
  });

  it('narrows the list by label, API name, type or value', async () => {
    inspect.mockResolvedValue(INSPECTION);
    const element = mount();
    await open(element);

    const search = q(element, '[data-id="search"]');
    search.dispatchEvent(new CustomEvent('change', { detail: { value: 'EMAIL' } }));
    await flush();
    expect(rowNames(element)).toEqual(['Email']);
    expect(q(element, '[data-id="count"]').textContent).toBe('1 of 4 fields');

    search.dispatchEvent(new CustomEvent('change', { detail: { value: 'nothing here' } }));
    await flush();
    expect(q(element, '[data-id="no-match"]')).not.toBeNull();
    expect(q(element, '[data-id="field-table"]')).toBeNull();
  });

  it('copies the API name', async () => {
    inspect.mockResolvedValue(INSPECTION);
    const writeText = jest.fn().mockResolvedValue();
    Object.defineProperty(global.navigator, 'clipboard', {
      value: { writeText },
      configurable: true
    });
    const element = mount();
    await open(element);

    q(element, 'tr[data-row="LastName"] .copy-button').click();
    await flush();
    await flush();

    expect(writeText).toHaveBeenCalledWith('LastName');
    expect(q(element, '[data-id="copied"]').textContent.trim()).toBe('Copied LastName');
  });

  it('says so when copying is refused', async () => {
    inspect.mockResolvedValue(INSPECTION);
    Object.defineProperty(global.navigator, 'clipboard', {
      value: { writeText: jest.fn().mockRejectedValue(new Error('no')) },
      configurable: true
    });
    const element = mount();
    await open(element);

    q(element, 'tr[data-row="LastName"] .copy-button').click();
    await flush();
    await flush();
    await flush();
    await flush();
    await flush();

    expect(q(element, '[data-id="error-message"]')).not.toBeNull();
  });

  it('shows the refusal Apex gives', async () => {
    inspect.mockRejectedValue({ body: { message: 'Not for you.' } });
    const element = mount();
    await open(element);

    expect(q(element, '[data-id="error-message"]').textContent).toBe('Not for you.');
    expect(q(element, '[data-id="field-table"]')).toBeNull();
  });
});

describe('inspectorRows', () => {
  const rows = INSPECTION.fields;

  it('keeps every row for an empty term', () => {
    expect(filterRows(rows, '  ')).toHaveLength(4);
    expect(filterRows(null, 'a')).toEqual([]);
  });

  it('matches case-insensitively across label, API name, type and value', () => {
    expect(filterRows(rows, 'lastname').map((r) => r.apiName)).toEqual(['LastName']);
    expect(filterRows(rows, 'phone').map((r) => r.apiName)).toEqual(['Fax']);
    expect(filterRows(rows, 'garcia').map((r) => r.apiName)).toEqual(['LastName']);
  });

  it('normalizes input', () => {
    expect(normalize('  AbC ')).toBe('abc');
    expect(normalize(undefined)).toBe('');
  });
});
