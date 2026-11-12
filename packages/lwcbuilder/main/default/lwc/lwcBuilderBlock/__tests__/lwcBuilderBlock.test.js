import { createElement } from 'lwc';
import LwcBuilderBlock from 'c/lwcBuilderBlock';
import loadRecords from '@salesforce/apex/LwcBuilderController.loadRecords';
import loadChart from '@salesforce/apex/LwcBuilderController.loadChart';
const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/LwcBuilderController.loadRecords', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/LwcBuilderController.loadChart', () => ({ default: jest.fn() }), {
  virtual: true
});

const RECORD_ID = '003000000000001AAA';

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function mount(block, props = {}) {
  const element = createElement('c-lwc-builder-block', { is: LwcBuilderBlock });
  Object.assign(element, { recordId: RECORD_ID, objectApiName: 'Contact', ...props, block });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-lwc-builder-block', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the page record fields through Lightning Data Service', () => {
    const element = mount({
      id: 'b1',
      type: 'fields',
      fields: ['Email', 'Phone'],
      title: 'Contact'
    });
    expect(find(element, 'fields').recordId).toBe(RECORD_ID);
    expect(element.shadowRoot.querySelectorAll('lightning-output-field')).toHaveLength(2);
    expect(find(element, 'title').textContent).toBe('Contact');
  });

  it('asks for a record where there is none', () => {
    const element = mount({ id: 'b1', type: 'fields', fields: ['Email'] }, { recordId: undefined });
    expect(find(element, 'needs-record')).not.toBeNull();
  });

  it('loads a related list with the page record and links names', async () => {
    loadRecords.mockResolvedValue({
      columns: [
        { fieldName: 'Name', label: 'Name', type: 'string', isName: true },
        { fieldName: 'Amount__c', label: 'Amount', type: 'currency', isName: false }
      ],
      rows: [{ Id: 'a01000000000001AAA', Name: 'Spring gift', Amount__c: 50 }]
    });
    const element = mount({
      id: 'b2',
      type: 'relatedList',
      object: 'Gift__c',
      parentField: 'Donor__c',
      fields: ['Name', 'Amount__c']
    });
    await flush();

    const request = JSON.parse(loadRecords.mock.calls[0][0].requestJson);
    expect(request).toEqual(
      expect.objectContaining({ object: 'Gift__c', parentField: 'Donor__c', recordId: RECORD_ID })
    );
    const table = find(element, 'list');
    expect(table.columns[0]).toEqual(
      expect.objectContaining({ type: 'url', fieldName: 'recordUrl' })
    );
    expect(table.columns[1].type).toBe('currency');
    expect(table.data[0].recordUrl).toBe('/a01000000000001AAA');
  });

  it('shows a list refusal as a message', async () => {
    loadRecords.mockRejectedValue({ body: { message: 'Nope__c is not a field on Contact.' } });
    const element = mount({ id: 'b2', type: 'recordList', object: 'Contact', fields: ['Nope__c'] });
    await flush();
    expect(find(element, 'error-message').message).toBe('Nope__c is not a field on Contact.');
    expect(find(element, 'no-rows')).toBeNull();
  });

  it('draws report bars relative to the largest value, with a table behind them', async () => {
    loadChart.mockResolvedValue({
      title: 'Gifts by Fund',
      measures: ['Sum of Amount'],
      series: [],
      groups: [
        { label: 'General', cells: [[{ value: 200, label: '$200' }]] },
        { label: 'Building', cells: [[{ value: 50, label: '$50' }]] }
      ]
    });
    const element = mount({ id: 'b3', type: 'chart', report: 'Gifts_By_Fund' });
    await flush();
    expect(loadChart).toHaveBeenCalledWith({ reportName: 'Gifts_By_Fund' });
    expect(find(element, 'chart-title').textContent).toBe('Gifts by Fund: Sum of Amount');
    const bars = element.shadowRoot.querySelectorAll('.segment');
    expect(bars[0].getAttribute('style')).toContain('100%');
    expect(bars[1].getAttribute('style')).toContain('25%');
    expect(find(element, 'chart').getAttribute('aria-hidden')).toBe('true');
    const table = find(element, 'chart-table');
    expect(table.className).toBe('slds-assistive-text');
    expect(table.querySelectorAll('td')[0].textContent).toBe('$200');

    find(element, 'chart-toggle').click();
    await flush();
    expect(find(element, 'chart')).toBeNull();
    expect(find(element, 'chart-table').className).toContain('slds-table');
  });

  it('stacks a second grouping when the block asks for it', async () => {
    loadChart.mockResolvedValue({
      title: 'Asks',
      measures: ['Sum of Amount'],
      series: ['2025', '2026'],
      groups: [{ label: 'Won', cells: [[{ value: 30 }], [{ value: 10 }]] }]
    });
    const element = mount({ id: 'b6', type: 'chart', report: 'Asks', display: 'stacked' });
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="legend"] li')).toHaveLength(2);
    const segments = element.shadowRoot.querySelectorAll('.segment');
    expect(segments).toHaveLength(2);
    expect(segments[0].getAttribute('style')).toContain('75%');
  });

  it('shows only safe images', () => {
    expect(
      find(mount({ id: 'b4', type: 'image', url: '/resource/Logo', altText: 'Logo' }), 'image')
    ).not.toBeNull();
    const scriptUrl = ['javascript', 'alert(1)'].join(':');
    expect(
      find(mount({ id: 'b5', type: 'image', url: scriptUrl, altText: 'x' }), 'image')
    ).toBeNull();
  });

  it('opens a quick action for the page record', () => {
    const element = mount({
      id: 'b6',
      type: 'action',
      kind: 'quickAction',
      label: 'New Task',
      actionName: 'Global.NewTask'
    });
    find(element, 'action').click();
    const [pageReference] = mockNavigate.mock.calls[0];
    expect(pageReference.type).toBe('standard__quickAction');
    expect(pageReference.attributes.apiName).toBe('Global.NewTask');
    expect(pageReference.state.recordId).toBe(RECORD_ID);
  });

  it('runs a flow inside the block with the record Id and closes it when finished', async () => {
    const element = mount({
      id: 'b7',
      type: 'action',
      kind: 'flow',
      label: 'Thank',
      flowName: 'Thank_You',
      passRecordId: true
    });
    find(element, 'action').click();
    await flush();
    const flow = element.shadowRoot.querySelector('lightning-flow');
    expect(flow.flowApiName).toBe('Thank_You');
    expect(flow.flowInputVariables).toEqual([
      { name: 'recordId', type: 'String', value: RECORD_ID }
    ]);
    flow.dispatchEvent(new CustomEvent('statuschange', { detail: { status: 'FINISHED' } }));
    await flush();
    expect(element.shadowRoot.querySelector('lightning-flow')).toBeNull();
  });
});
