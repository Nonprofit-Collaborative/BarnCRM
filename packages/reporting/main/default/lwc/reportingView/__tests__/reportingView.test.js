import { createElement } from 'lwc';
import ReportingView from 'c/reportingView';
import runReport from '@salesforce/apex/ReportingQueryService.run';
import readPage from '@salesforce/apex/ReportingQueryService.page';
import { downloadCsv } from 'c/findCsv';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/ReportingQueryService.run', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ReportingQueryService.page', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('c/findCsv', () => ({ ...jest.requireActual('c/findCsv'), downloadCsv: jest.fn() }));
// A cap of two rows stands in for the 100,000 one export holds.
jest.mock('c/reportingModel', () => ({
  ...jest.requireActual('c/reportingModel'),
  MAX_EXPORT_ROWS: 2
}));

const LIST = {
  title: 'Donors',
  object: 'Contact',
  columns: [
    { path: 'Name', label: 'Name' },
    { path: 'Email', label: 'Email' }
  ]
};

const TOTALS = {
  title: 'By Fund',
  object: 'Gift__c',
  groups: [{ field: 'Fund__c', label: 'Fund', type: 'reference', labelPath: 'Fund__r.Name' }],
  measures: [{ fn: 'sum', path: 'Amount__c', label: 'Amount', type: 'currency' }],
  view: { type: 'bar' }
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function mount(props) {
  const element = createElement('c-reporting-view', { is: ReportingView });
  Object.assign(element, props);
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-reporting-view', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists records in a table that links each record and exports every page', async () => {
    runReport.mockResolvedValue({
      rows: [{ Id: '003000000000001AAA', Name: 'Ana', Email: 'ana@example.org' }],
      summaries: []
    });
    readPage
      .mockResolvedValueOnce({
        rows: [{ Id: '003000000000001AAA', Name: 'Ana', Email: 'a@x.org' }],
        lastId: '003000000000001AAA',
        done: false
      })
      .mockResolvedValueOnce({
        rows: [{ Id: '003000000000002AAA', Name: 'Ben', Email: 'b@x.org' }],
        done: true
      });
    const element = await mount({ report: LIST, canExport: true });

    const request = JSON.parse(runReport.mock.calls[0][0].requestJson);
    expect(request.query.fields).toEqual(['Name', 'Email']);
    const cells = element.shadowRoot.querySelectorAll('[data-id="table"] td');
    expect(cells[0].querySelector('a').textContent).toBe('Ana');
    expect(cells[1].textContent).toBe('ana@example.org');
    expect(cells[1].getAttribute('data-label')).toBe('Email');
    await expectAccessible(element);

    find(element, 'export').click();
    await flush();
    await flush();
    expect(readPage).toHaveBeenCalledTimes(2);
    expect(readPage.mock.calls[1][0].afterId).toBe('003000000000001AAA');
    // An export says so, for the server's Export Reports check, in pages of 2,000.
    expect(readPage.mock.calls[0][0]).toMatchObject({ forExport: true, pageSize: 2000 });
    const [base, columns, rows] = downloadCsv.mock.calls[0];
    expect(base).toBe('Donors');
    expect(columns.map((column) => column.label)).toEqual(['Name', 'Email']);
    expect(rows).toEqual([
      { c0: 'Ana', c1: 'a@x.org' },
      { c0: 'Ben', c1: 'b@x.org' }
    ]);
    expect(find(element, 'export-status').textContent).toBe('c.Reporting_Exported');
  });

  it('charts totals, switches to a table and exports the groups', async () => {
    runReport.mockResolvedValue({
      groups: [
        { keys: [['a01']], labels: ['General'], values: [100] },
        { keys: [['a02']], labels: ['Building'], values: [250] }
      ],
      more: true
    });
    const element = await mount({ report: TOTALS, canExport: true, heading: 'By Fund' });
    expect(find(element, 'heading').textContent).toContain('By Fund');
    const chart = find(element, 'chart');
    expect(chart.chart.rects).toHaveLength(2);
    expect(chart.summary).toBe('c.Reporting_ChartSummary');
    const notes = [...element.shadowRoot.querySelectorAll('[data-id="note"]')].map((note) =>
      note.textContent.trim()
    );
    expect(notes).toContain('c.Reporting_MoreGroups');
    await expectAccessible(element);

    find(element, 'toggle').click();
    await flush();
    const rows = element.shadowRoot.querySelectorAll('[data-id="table"] tbody tr');
    expect(rows[0].textContent).toContain('Building');
    expect(rows[0].textContent).toContain('$250.00');

    find(element, 'export').click();
    await flush();
    expect(readPage).not.toHaveBeenCalled();
    expect(downloadCsv.mock.calls[0][2]).toEqual([
      { c0: 'Building', c1: 250 },
      { c0: 'General', c1: 100 }
    ]);
  });

  it('shows a metric tile for a single total', async () => {
    runReport.mockResolvedValue({ groups: [{ keys: [], labels: [], values: [42] }] });
    const element = await mount({ report: { ...TOTALS, groups: [], view: { type: 'metric' } } });
    const metric = find(element, 'metric');
    expect(metric.value).toBe(42);
    expect(metric.formatStyle).toBe('currency');
    expect(find(element, 'export')).toBeNull();
  });

  it('totals a large report in pages when the server asks for a scan', async () => {
    runReport.mockResolvedValue({ scan: true });
    readPage
      .mockResolvedValueOnce({
        rows: [{ Id: '1', Fund__c: 'a01', Fund__r: { Name: 'General' }, Amount__c: 5 }],
        lastId: '1',
        done: false
      })
      .mockResolvedValueOnce({
        rows: [{ Id: '2', Fund__c: 'a01', Fund__r: { Name: 'General' }, Amount__c: 7 }],
        lastId: '2',
        done: true
      });
    const element = await mount({ report: { ...TOTALS, view: { type: 'table' } } });
    await flush();
    const request = JSON.parse(readPage.mock.calls[0][0].requestJson);
    expect(request.groups).toEqual([{ field: 'Fund__c' }]);
    expect(request.fields).toBeUndefined();
    expect(readPage.mock.calls[0][0]).toMatchObject({ forExport: false, pageSize: 5000 });
    const cells = element.shadowRoot.querySelectorAll('[data-id="table"] td');
    expect(cells[0].textContent).toBe('General');
    expect(cells[1].textContent).toBe('$12.00');
  });

  it('stops an export at the most one export holds and says so', async () => {
    runReport.mockResolvedValue({ rows: [{ Id: '003000000000001AAA', Name: 'Ana' }] });
    const page = (index) => ({
      rows: [{ Id: `00300000000000${index}AAA`, Name: `P${index}` }],
      lastId: `00300000000000${index}AAA`,
      done: false
    });
    readPage.mockResolvedValueOnce(page(1)).mockResolvedValueOnce(page(2));
    const element = await mount({ report: LIST, canExport: true });
    find(element, 'export').click();
    await flush();
    await flush();
    expect(readPage).toHaveBeenCalledTimes(2);
    expect(downloadCsv.mock.calls[0][2]).toHaveLength(2);
    expect(find(element, 'export-status').textContent).toBe('c.Reporting_ExportCapped');
  });

  it('runs one scan at a time across views', async () => {
    runReport.mockResolvedValue({ scan: true });
    let finishFirst;
    readPage
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            finishFirst = resolve;
          })
      )
      .mockResolvedValue({ rows: [], lastId: null, done: true });
    await mount({ report: { ...TOTALS, view: { type: 'table' } } });
    await mount({ report: { ...TOTALS, view: { type: 'table' } } });
    expect(readPage).toHaveBeenCalledTimes(1);
    finishFirst({ rows: [], lastId: null, done: true });
    await flush();
    await flush();
    expect(readPage).toHaveBeenCalledTimes(2);
  });

  it('says what stops the report and what a dashboard filter does not narrow', async () => {
    const element = await mount({ report: { object: 'Contact' }, unfiltered: ['Fund'] });
    expect(runReport).not.toHaveBeenCalled();
    expect(find(element, 'problem').message).toBe('c.Reporting_Problem_Columns');
    expect(find(element, 'unfiltered').textContent).toContain('c.Reporting_NotFiltered');
  });

  it('shows the error when the run fails and an empty state when nothing matches', async () => {
    runReport.mockRejectedValueOnce({ body: { message: 'You cannot report on that object.' } });
    const element = await mount({ report: LIST });
    expect(find(element, 'error').message).toBe('You cannot report on that object.');

    runReport.mockResolvedValueOnce({ rows: [] });
    await element.refresh();
    await flush();
    expect(find(element, 'empty')).not.toBeNull();
  });

  it('pages a long table with Show More', async () => {
    const rows = Array.from({ length: 60 }, (unused, index) => ({
      Id: `003${index}`,
      Name: `P${index}`,
      Email: ''
    }));
    runReport.mockResolvedValue({ rows });
    const element = await mount({ report: LIST });
    expect(element.shadowRoot.querySelectorAll('[data-id="table"] tbody tr')).toHaveLength(50);
    expect(find(element, 'rows-note').textContent).toBe('c.Reporting_RowsShown');
    find(element, 'show-more').click();
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="table"] tbody tr')).toHaveLength(60);
  });
});
