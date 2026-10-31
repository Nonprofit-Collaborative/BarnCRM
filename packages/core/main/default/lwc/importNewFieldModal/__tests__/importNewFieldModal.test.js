import { createElement } from 'lwc';
import ImportNewFieldModal from 'c/importNewFieldModal';
import getConnection from '@salesforce/apex/ImportNewFieldController.getConnection';
import getPermissionSets from '@salesforce/apex/ImportNewFieldController.getPermissionSets';
import createField from '@salesforce/apex/ImportNewFieldController.createField';
import checkField from '@salesforce/apex/ImportNewFieldController.checkField';
import findField from '@salesforce/apex/ImportNewFieldController.findField';
import { apiNameFrom, suggestField } from '../fieldSuggestions';

jest.mock(
  '@salesforce/apex/ImportNewFieldController.getConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ImportNewFieldController.getPermissionSets',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/ImportNewFieldController.createField', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportNewFieldController.checkField', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportNewFieldController.findField', () => ({ default: jest.fn() }), {
  virtual: true
});

async function flush() {
  for (let i = 0; i < 10; i++) {
    // eslint-disable-next-line no-await-in-loop
    await Promise.resolve();
  }
}
const OBJECTS = [
  { label: 'Person (Contact)', value: 'Contact', prefix: 'Contact1' },
  { label: 'Organization (Account)', value: 'Account', prefix: 'Organization' }
];

async function render(values, connection = { canCreate: true, connected: true }) {
  getConnection.mockResolvedValue(connection);
  getPermissionSets.mockResolvedValue([{ label: 'Volunteers', value: '0PS000000000001' }]);
  const element = createElement('c-import-new-field-modal', { is: ImportNewFieldModal });
  element.label = 'Create New Field';
  element.objects = OBJECTS;
  element.heading = 'T-Shirt Size';
  element.values = values;
  const closed = jest.fn();
  element.addEventListener('close', (event) => closed(event.detail));
  document.body.appendChild(element);
  await flush();
  return { element, closed };
}

const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const change = (element, id, value) =>
  one(element, id).dispatchEvent(new CustomEvent('change', { detail: { value } }));

describe('fieldSuggestions', () => {
  it('derives an API name from a heading', () => {
    expect(apiNameFrom('T-Shirt Size')).toBe('T_Shirt_Size');
    expect(apiNameFrom('2025 Gift  Total!')).toBe('Field_2025_Gift_Total');
    expect(apiNameFrom('Café')).toBe('Cafe');
    expect(apiNameFrom('')).toBe('New_Field');
    expect(apiNameFrom('x'.repeat(50))).toHaveLength(40);
  });

  it('suggests a type from the values', () => {
    expect(suggestField(['yes', 'No', '']).type).toBe('Checkbox');
    expect(suggestField(['a@example.org', 'b@example.org']).type).toBe('Email');
    expect(suggestField(['https://example.org', 'www.example.org']).type).toBe('Url');
    expect(suggestField(['$1,200.50', '$3'])).toMatchObject({ type: 'Currency', scale: 2 });
    expect(suggestField(['12.5%', '3%'])).toMatchObject({ type: 'Percent', scale: 1 });
    expect(suggestField(['1,234', '7.125'])).toMatchObject({ type: 'Number', scale: 3 });
    expect(suggestField(['2026-10-30', '1/2/2025']).type).toBe('Date');
    expect(suggestField(['2026-10-30T09:15:00Z']).type).toBe('DateTime');
    expect(suggestField(['555-0201', '(555) 020-1234']).type).toBe('Phone');
    expect(suggestField(['x'.repeat(300)]).type).toBe('LongTextArea');
    expect(suggestField(['S', 'M', 'S', 'm', 'L', 'l'])).toMatchObject({
      type: 'Picklist',
      values: ['S', 'M', 'L']
    });
    expect(suggestField(['Ann', 'Bo', 'Cy']).type).toBe('Text');
  });
});

describe('c-import-new-field-modal', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('prefills the field, creates it and closes with it once it is in describe', async () => {
    createField.mockResolvedValue('707000000000001');
    checkField.mockResolvedValue({
      state: 'Created',
      fieldValue: 'T_Shirt_Size__c',
      fieldLabel: 'T-Shirt Size'
    });
    const { element, closed } = await render(['S', 'M', 'S', 'L', 'M', 'L']);

    expect(one(element, 'label').value).toBe('T-Shirt Size');
    expect(one(element, 'api-name').value).toBe('T_Shirt_Size');
    expect(one(element, 'type').value).toBe('Picklist');
    expect(one(element, 'values').value).toBe('S\nM\nL');
    expect(one(element, 'permission-set').options).toHaveLength(2);
    expect(one(element, 'guidance')).toBeNull();
    change(element, 'object', 'Account');
    change(element, 'permission-set', '0PS000000000001');
    await flush();
    one(element, 'create').click();
    await flush();

    expect(JSON.parse(createField.mock.calls[0][0].requestJson)).toEqual({
      objectApiName: 'Account',
      label: 'T-Shirt Size',
      apiName: 'T_Shirt_Size',
      type: 'Picklist',
      length: 255,
      scale: 0,
      values: ['S', 'M', 'L'],
      permissionSetId: '0PS000000000001'
    });
    expect(checkField).toHaveBeenCalledWith({
      jobId: '707000000000001',
      objectApiName: 'Account',
      apiName: 'T_Shirt_Size'
    });
    expect(closed).toHaveBeenCalledWith({
      objectApiName: 'Account',
      prefix: 'Organization',
      fieldValue: 'T_Shirt_Size__c',
      fieldLabel: 'T-Shirt Size'
    });
  });

  it('keeps the form when the request is refused, so the name can be fixed', async () => {
    createField.mockRejectedValue({ body: { message: 'This API name is already used.' } });
    const { element, closed } = await render(['a', 'b']);
    one(element, 'create').click();
    await flush();

    expect(one(element, 'error').textContent).toContain('already used');
    expect(one(element, 'guidance')).toBeNull();
    expect(one(element, 'create').disabled).toBe(false);
    expect(checkField).not.toHaveBeenCalled();
    expect(closed).not.toHaveBeenCalled();
  });

  it('turns to the Setup details when Salesforce refuses the field', async () => {
    createField.mockResolvedValue('707000000000001');
    checkField.mockResolvedValue({ state: 'Failed', message: 'Salesforce refused the field.' });
    const { element } = await render(['a', 'b']);
    one(element, 'create').click();
    await flush();

    expect(one(element, 'error').textContent).toContain('refused');
    expect(one(element, 'guidance')).not.toBeNull();
    expect(one(element, 'refresh')).not.toBeNull();
  });

  it('without a connection shows the details to copy and picks the field up on Refresh', async () => {
    findField.mockResolvedValueOnce({ state: 'Running' }).mockResolvedValueOnce({
      state: 'Created',
      fieldValue: 'T_Shirt_Size__c',
      fieldLabel: 'T-Shirt Size'
    });
    const { element, closed } = await render(['12', '7.5'], { canCreate: true, connected: false });

    expect(getPermissionSets).not.toHaveBeenCalled();
    expect(one(element, 'create')).toBeNull();
    const details = one(element, 'details').value;
    expect(details).toContain('Contact');
    expect(details).toContain('T_Shirt_Size__c');
    expect(details).toContain('Number');
    one(element, 'refresh').click();
    await flush();
    expect(one(element, 'error')).not.toBeNull();
    expect(closed).not.toHaveBeenCalled();
    one(element, 'refresh').click();
    await flush();
    expect(findField).toHaveBeenCalledWith({ objectApiName: 'Contact', apiName: 'T_Shirt_Size' });
    expect(closed).toHaveBeenCalledWith(
      expect.objectContaining({ prefix: 'Contact1', fieldValue: 'T_Shirt_Size__c' })
    );
  });
});
