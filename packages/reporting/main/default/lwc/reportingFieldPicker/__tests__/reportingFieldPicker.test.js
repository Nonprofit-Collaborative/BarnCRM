import { createElement } from 'lwc';
import ReportingFieldPicker from 'c/reportingFieldPicker';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/QueryFieldCatalog.getObjectInfo', () => ({ default: jest.fn() }), {
  virtual: true
});

const OBJECTS = {
  Gift_Allocation__c: {
    apiName: 'Gift_Allocation__c',
    label: 'Gift Allocation',
    fields: [
      {
        apiName: 'Amount__c',
        label: 'Amount',
        dataType: 'currency',
        aggregatable: true,
        groupable: false,
        filterable: true
      },
      {
        apiName: 'Gift__c',
        label: 'Gift',
        dataType: 'reference',
        referenceTo: 'Gift__c',
        relationshipName: 'Gift__r',
        groupable: true,
        filterable: true
      }
    ]
  },
  Gift__c: {
    apiName: 'Gift__c',
    label: 'Gift',
    fields: [
      {
        apiName: 'Gift_Date__c',
        label: 'Gift Date',
        dataType: 'date',
        groupable: true,
        filterable: true
      },
      {
        apiName: 'Status__c',
        label: 'Status',
        dataType: 'picklist',
        groupable: true,
        filterable: true,
        picklistValues: [{ value: 'Received', label: 'Received Gift' }]
      },
      {
        apiName: 'Fund__c',
        label: 'Fund ID',
        dataType: 'reference',
        referenceTo: 'Fund__c',
        relationshipName: 'Fund__r',
        groupable: true,
        filterable: true
      }
    ]
  },
  Fund__c: {
    apiName: 'Fund__c',
    label: 'Fund',
    fields: [{ apiName: 'Name', label: 'Fund Name', dataType: 'string', groupable: true }]
  }
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function mount(props) {
  const element = createElement('c-reporting-field-picker', { is: ReportingFieldPicker });
  Object.assign(element, props);
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

const steps = (element) => [...element.shadowRoot.querySelectorAll('[data-id="step"]')];

describe('c-reporting-field-picker', () => {
  beforeEach(() => {
    getObjectInfo.mockImplementation(({ objectApiName }) => {
      if (OBJECTS[objectApiName]) {
        return Promise.resolve(OBJECTS[objectApiName]);
      }
      return Promise.reject({ body: { message: 'No access' } });
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers fields of the kind asked for and crosses lookups', async () => {
    const element = await mount({
      objectApiName: 'Gift_Allocation__c',
      label: 'Add Column',
      kind: 'sum'
    });
    const handler = jest.fn();
    element.addEventListener('change', handler);
    const first = steps(element)[0];
    expect(first.label).toBe('Add Column');
    expect(first.options.map((option) => option.value)).toEqual(['Amount__c', '>Gift__c']);
    await expectAccessible(element);

    first.dispatchEvent(new CustomEvent('change', { detail: { value: '>Gift__c' } }));
    await flush();
    await flush();
    const second = steps(element)[1];
    expect(second.label).toBe('c.Reporting_FieldOf');
    expect(second.options.map((option) => option.value)).toEqual(['>Fund__c']);

    second.dispatchEvent(new CustomEvent('change', { detail: { value: '>Fund__c' } }));
    await flush();
    await flush();
    expect(steps(element)).toHaveLength(3);
    expect(steps(element)[2].options).toEqual([]);
    expect(handler).not.toHaveBeenCalled();
  });

  it('reports a chosen field with its label path and picklist labels', async () => {
    const element = await mount({ objectApiName: 'Gift_Allocation__c', kind: 'group' });
    const handler = jest.fn();
    element.addEventListener('change', handler);
    steps(element)[0].dispatchEvent(new CustomEvent('change', { detail: { value: '>Gift__c' } }));
    await flush();
    await flush();
    steps(element)[1].dispatchEvent(new CustomEvent('change', { detail: { value: 'Fund__c' } }));
    expect(handler.mock.calls[0][0].detail).toEqual({
      path: 'Gift__r.Fund__c',
      label: 'Gift: Fund ID',
      type: 'reference',
      referenceTo: 'Fund__c',
      labelPath: 'Gift__r.Fund__r.Name',
      picklist: {}
    });
    steps(element)[1].dispatchEvent(new CustomEvent('change', { detail: { value: 'Status__c' } }));
    expect(handler.mock.calls[1][0].detail.picklist).toEqual({ Received: 'Received Gift' });
    expect(element.value).toBe('Gift__r.Status__c');
  });

  it('opens on a saved path and stays direct when asked', async () => {
    const element = await mount({
      objectApiName: 'Gift_Allocation__c',
      value: 'Gift__r.Gift_Date__c',
      kind: 'date'
    });
    expect(steps(element).map((step) => step.value)).toEqual(['>Gift__c', 'Gift_Date__c']);

    const direct = await mount({ objectApiName: 'Gift__c', kind: 'column', direct: true });
    expect(steps(direct)[0].options.some((option) => option.value.startsWith('>'))).toBe(false);
    direct.clear();
    await flush();
    expect(direct.value).toBe('');
  });

  it('shows why an object cannot be read', async () => {
    const element = await mount({ objectApiName: 'Secret__c' });
    expect(element.shadowRoot.querySelector('[data-id="error"]').message).toBe('No access');
    element.objectApiName = '';
    await flush();
    expect(steps(element)).toHaveLength(0);
  });
});
