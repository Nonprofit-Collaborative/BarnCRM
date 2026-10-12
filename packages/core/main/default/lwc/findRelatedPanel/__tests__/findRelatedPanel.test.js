import { createElement } from 'lwc';
import FindRelatedPanel from 'c/findRelatedPanel';
import listChildRelationships from '@salesforce/apex/FindController.listChildRelationships';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';

jest.mock(
  '@salesforce/apex/FindController.listChildRelationships',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/QueryFieldCatalog.getObjectInfo', () => ({ default: jest.fn() }), {
  virtual: true
});

const OPTIONS = [
  {
    label: 'Contacts (Account)',
    relationshipName: 'Contacts',
    objectName: 'Contact',
    field: 'AccountId',
    filterable: true
  },
  {
    label: 'Gifts (Household)',
    relationshipName: 'Gifts__r',
    objectName: 'Gift__c',
    field: 'Household__c',
    filterable: true
  }
];
const CONTACT = {
  apiName: 'Contact',
  fields: [
    { apiName: 'Email', label: 'Email', dataType: 'email', filterable: true },
    { apiName: 'Name', label: 'Full Name', dataType: 'string', filterable: true },
    { apiName: 'MailingAddress', label: 'Mailing Address', dataType: 'address' }
  ]
};

// A macrotask, because the panel awaits Apex before it renders its choices.
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount(setup) {
  const element = createElement('c-find-related-panel', { is: FindRelatedPanel });
  if (setup) {
    setup(element);
  }
  element.objectApiName = 'Account';
  document.body.appendChild(element);
  await flush();
  return element;
}

function query(element, dataId) {
  return element.shadowRoot.querySelector(`[data-id="${dataId}"]`);
}

function change(target, detail) {
  target.dispatchEvent(new CustomEvent('change', { detail }));
}

describe('c-find-related-panel', () => {
  beforeEach(() => {
    listChildRelationships.mockResolvedValue(OPTIONS);
    getObjectInfo.mockResolvedValue(CONTACT);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('builds a has-no-related-records condition with its own filter', async () => {
    const changed = jest.fn();
    const element = await mount();
    element.addEventListener('change', changed);
    expect(listChildRelationships).toHaveBeenCalledWith({ objectApiName: 'Account' });

    query(element, 'add-condition').click();
    await flush();
    change(query(element, 'kind'), { value: 'Gift__c.Household__c' });
    change(query(element, 'has'), { value: 'no' });
    await flush();
    const builder = element.shadowRoot.querySelector('c-filter-builder');
    expect(builder.objectApiName).toBe('Gift__c');
    const filter = {
      version: 1,
      conditions: [{ id: 1, field: 'Amount__c', operator: 'greater than', value: 100 }]
    };
    change(builder, { value: JSON.stringify(filter), valid: true });

    expect(changed.mock.calls.pop()[0].detail).toEqual({
      related: [{ object: 'Gift__c', field: 'Household__c', has: false, filter }],
      children: [],
      valid: true
    });
  });

  it('builds a related record column from the related object fields', async () => {
    const changed = jest.fn();
    const element = await mount();
    element.addEventListener('change', changed);

    query(element, 'add-column').click();
    await flush();
    change(query(element, 'column-kind'), { value: 'Contacts' });
    await flush();
    const fields = query(element, 'column-fields');
    expect(getObjectInfo).toHaveBeenCalledWith({ objectApiName: 'Contact' });
    expect(fields.options.map((option) => option.value)).toEqual(['Email', 'Name']);
    expect(fields.max).toBe('5');
    change(fields, { value: ['Name', 'Email'] });

    expect(changed.mock.calls.pop()[0].detail.children).toEqual([
      { relationship: 'Contacts', fields: ['Name', 'Email'], limit: 10 }
    ]);
  });

  it('opens a saved query with its entries and allows two of each', async () => {
    const element = await mount((panel) => {
      panel.related = [{ object: 'Contact', field: 'AccountId', has: true }];
      panel.children = [{ relationship: 'Contacts', fields: ['Email'], limit: 3 }];
    });
    expect(query(element, 'kind').value).toBe('Contact.AccountId');
    expect(query(element, 'column-rows').value).toBe(3);
    query(element, 'add-condition').click();
    await flush();
    expect(query(element, 'add-condition').disabled).toBe(true);
    query(element, 'remove-condition').click();
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="condition"]')).toHaveLength(1);
    expect(query(element, 'add-condition').disabled).toBe(false);
  });
});
