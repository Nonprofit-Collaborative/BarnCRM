import { createElement } from 'lwc';
import FilterBuilder from 'c/filterBuilder';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';

jest.mock('@salesforce/apex/QueryFieldCatalog.getObjectInfo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_Filter_SummaryAll', () => ({ default: 'All of these: {0}' }), {
  virtual: true
});

const GIFT = {
  apiName: 'Gift__c',
  label: 'Gift',
  labelPlural: 'Gifts',
  fields: [
    { apiName: 'Amount__c', label: 'Amount', dataType: 'currency', filterable: true },
    {
      apiName: 'Donor_Contact__c',
      label: 'Donor',
      dataType: 'reference',
      filterable: true,
      referenceTo: 'Contact',
      relationshipName: 'Donor_Contact__r'
    },
    { apiName: 'Gift_Date__c', label: 'Gift Date', dataType: 'date', filterable: true },
    { apiName: 'Notes__c', label: 'Notes', dataType: 'textarea', filterable: false },
    {
      apiName: 'Status__c',
      label: 'Status',
      dataType: 'picklist',
      filterable: true,
      picklistValues: [
        { label: 'Received', value: 'Received' },
        { label: 'Pledged', value: 'Pledged' }
      ]
    }
  ]
};

const CONTACT = {
  apiName: 'Contact',
  label: 'Contact',
  labelPlural: 'Contacts',
  fields: [{ apiName: 'LastName', label: 'Last Name', dataType: 'string', filterable: true }]
};

// A macrotask, because loading a saved filter awaits several describes in a row.
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(props = {}) {
  const element = createElement('c-filter-builder', { is: FilterBuilder });
  Object.assign(element, { objectApiName: 'Gift__c', ...props });
  const changes = [];
  element.addEventListener('change', (event) => changes.push(event.detail));
  document.body.appendChild(element);
  await flush();
  await flush();
  return { element, changes };
}

const all = (element, id) => [...element.shadowRoot.querySelectorAll(`[data-id="${id}"]`)];
const one = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function choose(target, value) {
  target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
  await flush();
}

describe('c-filter-builder', () => {
  beforeEach(() => {
    getObjectInfo.mockImplementation(({ objectApiName }) => {
      return Promise.resolve(objectApiName === 'Contact' ? CONTACT : GIFT);
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('starts empty, saying every record matches', async () => {
    const { element } = await render();
    expect(one(element, 'empty')).not.toBeNull();
    expect(all(element, 'condition')).toHaveLength(0);
    expect(element.value).toBe('');
    expect(element.validate()).toEqual({ valid: true, message: '' });
  });

  it('offers filterable fields and lookups to open, never a field it cannot filter on', async () => {
    const { element } = await render();
    one(element, 'add').click();
    await flush();
    const values = one(element, 'field').options.map((option) => option.value);
    expect(values).toEqual(
      expect.arrayContaining(['f:Amount__c', 'f:Status__c', 'r:Donor_Contact__r'])
    );
    expect(values).not.toContain('f:Notes__c');
  });

  it('builds a picklist condition with is one of and reports it', async () => {
    const { element, changes } = await render();
    one(element, 'add').click();
    await flush();
    await choose(one(element, 'field'), 'f:Status__c');
    const operators = one(element, 'operator').options.map((option) => option.value);
    expect(operators).not.toContain('contains');
    await choose(one(element, 'operator'), 'in');
    const listbox = element.shadowRoot.querySelector('lightning-dual-listbox');
    expect(listbox).not.toBeNull();
    await choose(listbox, ['Received', 'Pledged']);

    const last = changes[changes.length - 1];
    expect(last.valid).toBe(true);
    expect(JSON.parse(last.value)).toEqual({
      version: 1,
      conditions: [{ id: 1, field: 'Status__c', operator: 'in', value: ['Received', 'Pledged'] }]
    });
    expect(last.summary).toBe('All of these: Status c.Core_Filter_OpIn Received, Pledged');
  });

  it('writes a number as a number', async () => {
    const { element, changes } = await render();
    one(element, 'add').click();
    await flush();
    await choose(one(element, 'field'), 'f:Amount__c');
    await choose(one(element, 'operator'), 'greater than');
    await choose(one(element, 'value'), '0');
    expect(JSON.parse(changes[changes.length - 1].value).conditions[0].value).toBe(0);
  });

  it('refuses a day count out of range and shows why next to the condition', async () => {
    const { element } = await render();
    one(element, 'add').click();
    await flush();
    await choose(one(element, 'field'), 'f:Gift_Date__c');
    await choose(one(element, 'operator'), 'last n days');
    await choose(one(element, 'value'), '0');

    expect(element.reportValidity()).toBe(false);
    await flush();
    expect(one(element, 'row-error').textContent).toBe('c.Core_Filter_ErrorDays');
    expect(one(element, 'error-summary')).not.toBeNull();

    await choose(one(element, 'value'), '30');
    expect(element.validate().valid).toBe(true);
    expect(JSON.parse(element.value).conditions[0]).toEqual({
      id: 1,
      field: 'Gift_Date__c',
      operator: 'last n days',
      value: 30
    });
  });

  it('hides the relative date operators when asked', async () => {
    const { element } = await render({ hideRelativeDates: true });
    one(element, 'add').click();
    await flush();
    await choose(one(element, 'field'), 'f:Gift_Date__c');
    const operators = one(element, 'operator').options.map((option) => option.value);
    expect(operators).not.toContain('this year');
  });

  it('follows a lookup to a field on the parent', async () => {
    const { element, changes } = await render();
    one(element, 'add').click();
    await flush();
    await choose(one(element, 'field'), 'r:Donor_Contact__r');
    expect(getObjectInfo).toHaveBeenCalledWith({ objectApiName: 'Contact' });
    const pickers = all(element, 'field');
    expect(pickers).toHaveLength(2);
    await choose(pickers[1], 'f:LastName');
    await choose(one(element, 'operator'), 'starts with');
    await choose(one(element, 'value'), 'Sm');
    expect(JSON.parse(changes[changes.length - 1].value).conditions[0]).toEqual({
      id: 1,
      field: 'Donor_Contact__r.LastName',
      operator: 'starts with',
      value: 'Sm'
    });
  });

  it('offers no lookup to open when parent fields are switched off', async () => {
    const { element } = await render({ parentDepth: 0 });
    one(element, 'add').click();
    await flush();
    const values = one(element, 'field').options.map((option) => option.value);
    expect(values).not.toContain('r:Donor_Contact__r');
  });

  it('reads a saved document back into rows, parent paths and logic included', async () => {
    const saved = JSON.stringify({
      version: 1,
      logic: '1 OR 2',
      conditions: [
        { id: 1, field: 'Status__c', operator: 'equals', value: 'Received' },
        { id: 2, field: 'Donor_Contact__r.LastName', operator: 'equals', value: 'Smith' }
      ]
    });
    const { element } = await render({ value: saved });

    expect(all(element, 'condition')).toHaveLength(2);
    expect(all(element, 'field')).toHaveLength(3);
    expect(one(element, 'logic').value).toBe('1 OR 2');
    expect(element.validate().valid).toBe(true);
    expect(JSON.parse(element.value)).toEqual(JSON.parse(saved));
  });

  it('keeps a saved condition on a field the user cannot see, and says so', async () => {
    const saved = JSON.stringify({
      version: 1,
      conditions: [{ id: 1, field: 'Secret__c', operator: 'equals', value: 'x' }]
    });
    const { element } = await render({ value: saved });

    expect(one(element, 'row-error').textContent).toBe('c.Core_Filter_ErrorFieldUnavailable');
    expect(element.validate().valid).toBe(false);
    expect(JSON.parse(element.value).conditions[0].field).toBe('Secret__c');
  });

  it('checks the condition logic against the conditions', async () => {
    const { element } = await render();
    one(element, 'add').click();
    await flush();
    one(element, 'add').click();
    await flush();
    const toggle = one(element, 'logic-toggle');
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(one(element, 'logic').value).toBe('1 AND 2');

    const logic = one(element, 'logic');
    logic.value = '1 OR 3';
    logic.dispatchEvent(new CustomEvent('change'));
    await flush();
    element.reportValidity();
    await flush();
    // Both rows still need a field, which is reported first; the logic says its own problem.
    expect(one(element, 'logic-error').textContent.trim()).toBe('c.Core_Filter_ErrorLogicUnknown');
  });

  it('renumbers the conditions when one is removed', async () => {
    const { element } = await render();
    one(element, 'add').click();
    await flush();
    one(element, 'add').click();
    await flush();
    all(element, 'remove')[0].click();
    await flush();
    expect(all(element, 'condition')).toHaveLength(1);
    expect(all(element, 'remove')[0].alternativeText).toBe('c.Core_Filter_RemoveCondition');
  });

  it('says so when a saved filter cannot be read', async () => {
    const { element } = await render({ value: '{"version": 9}' });
    expect(one(element, 'load-error').textContent).toBe('c.Core_Filter_ErrorInvalidDocument');
    expect(element.validate().valid).toBe(false);
  });

  it('shows the refusal when the object is not available', async () => {
    getObjectInfo.mockImplementation(() =>
      Promise.reject({ body: { message: 'This object is not available to you: Secret__c.' } })
    );
    const { element } = await render({ objectApiName: 'Secret__c' });
    expect(one(element, 'load-error').textContent).toBe(
      'This object is not available to you: Secret__c.'
    );
    expect(one(element, 'add').disabled).toBe(true);
  });
});
