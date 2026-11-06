import { createElement } from 'lwc';
import RecordInspector from 'c/recordInspector';
import WhereUsedModal from 'c/whereUsedModal';
import inspect from '@salesforce/apex/RecordInspectorController.inspect';
import findToolStateKey from '@salesforce/apex/DataManagerController.findToolStateKey';
import pageLink from '@salesforce/apex/RecordInspectorController.pageLink';
import * as navigation from 'lightning/navigation';
import { filterRows, normalize, parseRecordId } from '../inspectorRows';

jest.mock('@salesforce/apex/RecordInspectorController.inspect', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/RecordInspectorController.pageLink',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/DataManagerController.findToolStateKey',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return {
      NavigationMixin,
      CurrentPageReference: createTestWireAdapter(jest.fn()),
      __esModule: true
    };
  },
  { virtual: true }
);

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
    expect(notes.querySelector('c-barn-status-badge')).not.toBeNull();
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

  it('opens Find on the record object', async () => {
    inspect.mockResolvedValue({ ...INSPECTION, objectApiName: 'Error_Log__c' });
    const element = mount();
    findToolStateKey.emit('c__tool');
    await open(element);

    q(element, '[data-id="open-find"]').click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Find' },
      state: { c__object: 'Error_Log__c' }
    });
  });

  it('links each field to its Object Manager page', async () => {
    inspect.mockResolvedValue(INSPECTION);
    const element = mount();
    await open(element);

    const link = q(element, 'tr[data-row="Notes__c"] a.setup-link');
    expect(link.getAttribute('href')).toBe(
      '/lightning/setup/ObjectManager/Contact/FieldsAndRelationships/Notes__c/view'
    );
    expect(link.getAttribute('target')).toBe('_blank');

    q(element, 'tr[data-row="Notes__c"] .where-used-button').click();
    expect(WhereUsedModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ objectName: 'Contact', fieldName: 'Notes__c', fieldLabel: 'Notes' })
    );
  });

  it('shows the refusal Apex gives', async () => {
    inspect.mockRejectedValue({ body: { message: 'Not for you.' } });
    const element = mount();
    await open(element);

    expect(q(element, '[data-id="error-message"]').message).toBe('Not for you.');
    expect(q(element, '[data-id="field-table"]')).toBeNull();
  });

  it('on a record page ignores the page state and shows no ID box', async () => {
    const element = mount();
    navigation.CurrentPageReference.emit({ state: { c__recordId: '001000000000009AAA' } });
    await flush();

    expect(inspect).not.toHaveBeenCalled();
    expect(q(element, '[data-id="record-input"]')).toBeNull();
    expect(q(element, '[data-id="record-heading"]')).toBeNull();
  });
});

describe('c-record-inspector on the Record Inspector page', () => {
  const LINK = { tabApiName: 'Record_Inspector', recordIdKey: 'c__recordId' };

  function mountPage() {
    const element = createElement('c-record-inspector', { is: RecordInspector });
    document.body.appendChild(element);
    pageLink.emit(LINK);
    return element;
  }

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('reads the record the page state names at once and shows which record it is', async () => {
    inspect.mockResolvedValue({ ...INSPECTION, recordName: 'Ana Garcia' });
    const element = mountPage();
    navigation.CurrentPageReference.emit({ state: { c__recordId: INSPECTION.recordId } });
    await flush();
    await flush();

    expect(inspect).toHaveBeenCalledWith({ recordId: INSPECTION.recordId });
    expect(rowNames(element)).toEqual(['LastName', 'Email', 'Fax', 'Notes__c']);
    const link = q(element, '[data-id="record-link"]');
    expect(link.textContent).toBe('Ana Garcia');
    expect(link.getAttribute('href')).toBe(`/lightning/r/${INSPECTION.recordId}/view`);
    expect(q(element, '[data-id="record-object"]').textContent).toBe('Contact');
    expect(q(element, '[data-id="record-input"]').value).toBe(INSPECTION.recordId);
    expect(q(element, '[data-id="inspect-button"]')).not.toBeNull();
  });

  it('with no ID offers a box for an ID or link and reads nothing', async () => {
    const element = mountPage();
    navigation.CurrentPageReference.emit({ state: {} });
    await flush();

    expect(inspect).not.toHaveBeenCalled();
    expect(q(element, '[data-id="record-input"]')).not.toBeNull();
    expect(q(element, '[data-id="intro"]')).not.toBeNull();
    expect(q(element, '[data-id="inspect-button"]')).toBeNull();
  });

  it('opens the page on a pasted record link through the page state', async () => {
    const element = mountPage();
    navigation.CurrentPageReference.emit({ state: {} });
    await flush();

    const input = q(element, '[data-id="record-input"]');
    input.value = 'https://example.lightning.force.com/lightning/r/Contact/003000000000002AAA/view';
    input.dispatchEvent(new CustomEvent('change', { detail: { value: input.value } }));
    q(element, '[data-id="go-button"]').click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Record_Inspector' },
      state: { c__recordId: '003000000000002AAA' }
    });
  });

  it('says so when the pasted text holds no record ID', async () => {
    const element = mountPage();
    navigation.CurrentPageReference.emit({ state: {} });
    await flush();

    const input = q(element, '[data-id="record-input"]');
    input.dispatchEvent(new CustomEvent('change', { detail: { value: 'not a record' } }));
    q(element, '[data-id="go-button"]').click();
    await flush();

    expect(mockNavigate).not.toHaveBeenCalled();
    expect(inspect).not.toHaveBeenCalled();
    expect(q(element, '[data-id="error-message"]').message).toMatch(
      /Core_RecordInspector_BadInput/
    );
  });

  it('says so when the page state names no record', async () => {
    const element = mountPage();
    navigation.CurrentPageReference.emit({ state: { c__recordId: 'nonsense' } });
    await flush();

    expect(inspect).not.toHaveBeenCalled();
    expect(q(element, '[data-id="error-message"]').message).toMatch(
      /Core_RecordInspector_BadInput/
    );
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

  it('finds the record ID in an ID or a record link', () => {
    const id = '003000000000002AAA';
    expect(parseRecordId(` ${id} `)).toBe(id);
    expect(parseRecordId('003000000000002')).toBe('003000000000002');
    expect(parseRecordId(`https://x.lightning.force.com/lightning/r/Contact/${id}/view`)).toBe(id);
    expect(parseRecordId(`https://x.my.salesforce.com/${id}?srPos=0`)).toBe(id);
    expect(
      parseRecordId(`https://x.lightning.force.com/lightning/n/Record_Inspector?c__recordId=${id}`)
    ).toBe(id);
    expect(parseRecordId('https://x.lightning.force.com/lightning/o/Contact/list')).toBeUndefined();
    expect(parseRecordId('AccountSettings')).toBeUndefined();
    expect(parseRecordId('')).toBeUndefined();
    expect(parseRecordId(undefined)).toBeUndefined();
  });
});
