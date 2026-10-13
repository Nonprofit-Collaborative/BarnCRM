import { createElement } from 'lwc';
import FindSummaryPanel from 'c/findSummaryPanel';
import summarize from '@salesforce/apex/FindController.summarize';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';

jest.mock('@salesforce/apex/FindController.summarize', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/QueryFieldCatalog.getObjectInfo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_Find_Blank', () => ({ default: '(blank)' }), {
  virtual: true
});

const GIFT = {
  apiName: 'Gift__c',
  fields: [
    { apiName: 'Amount__c', label: 'Amount', dataType: 'currency', filterable: true },
    { apiName: 'Gift_Date__c', label: 'Gift Date', dataType: 'date', filterable: true },
    {
      apiName: 'Status__c',
      label: 'Status',
      dataType: 'picklist',
      filterable: true,
      picklistValues: []
    },
    { apiName: 'Notes__c', label: 'Notes', dataType: 'textarea', filterable: false }
  ]
};
const QUERY = JSON.stringify({ version: 1, object: 'Gift__c', fields: ['Name'] });

// A macrotask, because the panel awaits a describe before it renders its fields.
// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mount(aggregate) {
  const element = createElement('c-find-summary-panel', { is: FindSummaryPanel });
  element.objectApiName = 'Gift__c';
  element.queryJson = QUERY;
  if (aggregate) {
    element.aggregate = aggregate;
  }
  document.body.appendChild(element);
  await flush();
  return element;
}

function choose(element, dataId, value) {
  element.shadowRoot
    .querySelector(`[data-id="${dataId}"]`)
    .dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-find-summary-panel', () => {
  beforeEach(() => {
    getObjectInfo.mockResolvedValue(GIFT);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers number fields for a total, and dates too for lowest and highest', async () => {
    const element = await mount();
    choose(element, 'function', 'sum');
    await flush();
    const field = element.shadowRoot.querySelector('[data-id="field"]');
    expect(field.options.map((option) => option.value)).toEqual(['Amount__c']);
    choose(element, 'function', 'max');
    await flush();
    expect(
      element.shadowRoot.querySelector('[data-id="field"]').options.map((option) => option.value)
    ).toEqual(['Amount__c', 'Gift_Date__c']);
    const groups = element.shadowRoot
      .querySelector('[data-id="group-by"]')
      .options.map((option) => option.value);
    expect(groups).toEqual(['', 'Amount__c', 'Gift_Date__c', 'Status__c']);
  });

  it('sends the query with the summary and shows one line per group', async () => {
    const changed = jest.fn();
    const element = await mount();
    element.addEventListener('change', changed);
    choose(element, 'function', 'sum');
    await flush();
    choose(element, 'field', 'Amount__c');
    choose(element, 'group-by', 'Status__c');
    await flush();
    expect(changed.mock.calls.pop()[0].detail.aggregate).toEqual({
      function: 'sum',
      field: 'Amount__c',
      groupBy: 'Status__c'
    });
    summarize.mockResolvedValue({
      soql: 'SELECT ...',
      capped: false,
      lines: [
        { groupValue: null, groupLabel: null, value: 25 },
        { groupValue: 'Received', groupLabel: 'Received', value: 1200 }
      ]
    });

    element.shadowRoot.querySelector('[data-id="summarize"]').click();
    await flush();

    const sent = JSON.parse(summarize.mock.calls[0][0].queryJson);
    expect(sent.aggregate).toEqual({ function: 'sum', field: 'Amount__c', groupBy: 'Status__c' });
    expect(sent.object).toBe('Gift__c');
    const table = element.shadowRoot.querySelector('[data-id="summary"]');
    expect(table.data.map((row) => [row.group, row.value])).toEqual([
      ['(blank)', 25],
      ['Received', 1200]
    ]);
  });

  it('keeps a saved summary and shows a refusal', async () => {
    const element = await mount({ function: 'MIN', field: 'Gift_Date__c' });
    expect(element.shadowRoot.querySelector('[data-id="function"]').value).toBe('min');
    summarize.mockRejectedValue({ body: { message: 'More than 20,000 records match.' } });
    element.shadowRoot.querySelector('[data-id="summarize"]').click();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="summary-error"]').textContent).toContain(
      'More than 20,000'
    );
    expect(element.shadowRoot.querySelector('[data-id="summary"]')).toBeNull();
  });
});
