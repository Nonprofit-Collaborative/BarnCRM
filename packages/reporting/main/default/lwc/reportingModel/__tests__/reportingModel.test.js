import {
  MAX_SCAN_ROWS,
  applyFilters,
  arrangeGroups,
  availableTemplates,
  bucketParts,
  csvValue,
  dateBounds,
  dateConditions,
  daysSince,
  formatValue,
  groupTable,
  groupText,
  isTotals,
  moved,
  namePath,
  newDashboard,
  newReport,
  newScan,
  nextWidgetKey,
  normalizeDashboard,
  normalizeRange,
  normalizeReport,
  objectsUsed,
  pageRequest,
  queryDocument,
  replaceAt,
  reportProblems,
  runRequest,
  scanPage,
  scanResult,
  makeClock,
  tableRows,
  valueAt,
  weekStartOf,
  withConditions
} from 'c/reportingModel';
import { zonedParts } from 'c/findCsv';

// A Wednesday, 15 May 2026, at noon local time.
const NOW = new Date(2026, 4, 13, 12, 0, 0);

const totalsReport = (extra = {}) =>
  normalizeReport({
    object: 'Gift__c',
    groups: [{ field: 'Fund__c', label: 'Fund', type: 'reference', labelPath: 'Fund__r.Name' }],
    measures: [{ fn: 'sum', path: 'Amount__c', label: 'Amount', type: 'currency' }],
    view: { type: 'bar' },
    ...extra
  });

describe('reportingModel: reports', () => {
  it('reads a path and a lookup name path', () => {
    expect(valueAt({ Fund__r: { Name: 'General' } }, 'Fund__r.Name')).toBe('General');
    expect(valueAt({ Fund__r: null }, 'Fund__r.Name')).toBeUndefined();
    expect(namePath('Gift__r.Fund__c', 'Fund__r')).toBe('Gift__r.Fund__r.Name');
    expect(namePath('Fund__c', null)).toBeNull();
  });

  it('normalizes a report within limits and drops what is not valid', () => {
    const report = normalizeReport({
      object: 'Gift__c',
      columns: [{ path: 'Name' }, {}, { path: 'Gift_Date__c', type: 'date', show: 'age' }],
      groups: [{ field: 'A' }, { field: 'B', type: 'date', bucket: 'nonsense' }, { field: 'C' }],
      measures: [
        { fn: 'drop' },
        { fn: 'sum' },
        { fn: 'count' },
        { fn: 'countDistinct', path: 'X__c' }
      ],
      summaries: [{ object: 'Gift_Allocation__c', field: 'Gift__c', fn: 'sum', path: 'Amount__c' }],
      related: [{ object: 'A__c', field: 'B__c', has: false }, { object: 'C' }],
      sort: { by: 'Name', direction: 'sideways' },
      limit: 999999,
      view: { type: 'radar' }
    });
    expect(report.columns).toEqual([
      { path: 'Name', label: 'Name', type: 'string' },
      { path: 'Gift_Date__c', label: 'Gift_Date__c', type: 'date', show: 'age' }
    ]);
    expect(report.groups).toHaveLength(2);
    expect(report.groups[1].bucket).toBeUndefined();
    expect(report.measures.map((measure) => measure.fn)).toEqual(['count', 'countDistinct']);
    expect(report.measures[1].type).toBe('integer');
    expect(report.related).toEqual([{ object: 'A__c', field: 'B__c', label: 'A__c', has: false }]);
    expect(report.summaries[0].type).toBe('double');
    expect(report.sort).toEqual({ by: 'Name', direction: 'asc' });
    expect(report.limit).toBe(2000);
    expect(report.view).toEqual({ type: 'table', stacked: false });
    expect(normalizeReport(null).object).toBe('');
    expect(newReport('Contact').object).toBe('Contact');
  });

  it('keeps a grouping picklist map for labels', () => {
    const report = normalizeReport({
      object: 'A',
      groups: [
        { field: 'S', picklist: { a: 'Apple' } },
        { field: 'T', picklist: {} }
      ]
    });
    expect(report.groups[0].picklist).toEqual({ a: 'Apple' });
    expect(report.groups[1].picklist).toBeUndefined();
  });

  it('names what stops a report from running', () => {
    expect(reportProblems(null)).toEqual(['object']);
    expect(reportProblems(newReport('A'))).toEqual(['columns']);
    expect(
      reportProblems(
        normalizeReport({ object: 'A', groups: [{ field: 'B' }], view: { type: 'bar' } })
      )
    ).toEqual(['measure', 'columns']);
    expect(reportProblems(totalsReport({ groups: [], view: { type: 'donut' } }))).toEqual([
      'chart'
    ]);
    expect(reportProblems(totalsReport({ view: { type: 'metric' } }))).toEqual(['metric']);
    expect(reportProblems(totalsReport())).toEqual([]);
    expect(isTotals(totalsReport())).toBe(true);
  });
});

describe('reportingModel: dates', () => {
  it('normalizes ranges', () => {
    expect(normalizeRange({ range: 'NOPE' })).toBeNull();
    expect(normalizeRange({ range: 'LAST_N_DAYS', n: 'x' })).toEqual({
      range: 'LAST_N_DAYS',
      n: 30
    });
    expect(
      normalizeRange({
        range: 'BETWEEN_DAYS_AGO',
        n: 365,
        m: 182,
        field: 'D',
        type: 'datetime',
        label: 'L'
      })
    ).toEqual({
      range: 'BETWEEN_DAYS_AGO',
      field: 'D',
      type: 'datetime',
      label: 'L',
      n: 365,
      m: 182
    });
    expect(normalizeRange({ range: 'CUSTOM', from: '2026-01-01', to: 'bad' })).toEqual({
      range: 'CUSTOM',
      from: '2026-01-01',
      to: ''
    });
  });

  it.each([
    ['TODAY', {}, '2026-05-13', '2026-05-13'],
    ['YESTERDAY', {}, '2026-05-12', '2026-05-12'],
    ['THIS_WEEK', {}, '2026-05-10', '2026-05-16'],
    ['LAST_WEEK', {}, '2026-05-03', '2026-05-09'],
    ['THIS_MONTH', {}, '2026-05-01', '2026-05-31'],
    ['LAST_MONTH', {}, '2026-04-01', '2026-04-30'],
    ['THIS_QUARTER', {}, '2026-04-01', '2026-06-30'],
    ['LAST_QUARTER', {}, '2026-01-01', '2026-03-31'],
    ['THIS_YEAR', {}, '2026-01-01', '2026-12-31'],
    ['LAST_YEAR', {}, '2025-01-01', '2025-12-31'],
    ['LAST_N_DAYS', { n: 7 }, '2026-05-06', '2026-05-13'],
    ['NEXT_N_DAYS', { n: 14 }, '2026-05-13', '2026-05-27'],
    ['LAST_N_MONTHS', { n: 12 }, '2025-06-01', '2026-05-31'],
    ['BETWEEN_DAYS_AGO', { n: 10, m: 3 }, '2026-05-03', '2026-05-10'],
    ['CUSTOM', { from: '2026-02-01' }, '2026-02-01', '']
  ])('bounds %s', (range, extra, from, to) => {
    expect(dateBounds({ range, ...extra }, NOW)).toEqual({ from, to });
  });

  it('turns a range into conditions on its field', () => {
    expect(dateBounds(null, NOW)).toBeNull();
    expect(dateConditions({ range: 'THIS_MONTH' }, NOW)).toEqual([]);
    expect(dateConditions({ range: 'THIS_MONTH', field: 'Gift_Date__c' }, NOW)).toEqual([
      { field: 'Gift_Date__c', operator: 'greater or equal', value: '2026-05-01' },
      { field: 'Gift_Date__c', operator: 'less or equal', value: '2026-05-31' }
    ]);
    const timed = dateConditions({ range: 'TODAY', field: 'Start__c', type: 'datetime' }, NOW);
    expect(timed.map((condition) => condition.operator)).toEqual(['greater or equal', 'less than']);
    expect(new Date(timed[1].value) - new Date(timed[0].value)).toBe(86400000);
    expect(dateConditions({ range: 'CUSTOM', to: '2026-01-31', field: 'D' }, NOW)).toEqual([
      { field: 'D', operator: 'less or equal', value: '2026-01-31' }
    ]);
  });

  it('sends this year, last year and the last n days as date literals', () => {
    expect(dateConditions({ range: 'THIS_YEAR', field: 'D' }, NOW)).toEqual([
      { field: 'D', operator: 'this year' }
    ]);
    expect(dateConditions({ range: 'LAST_YEAR', field: 'D', type: 'datetime' }, NOW)).toEqual([
      { field: 'D', operator: 'last year' }
    ]);
    expect(dateConditions({ range: 'LAST_N_DAYS', n: 7, field: 'D' }, NOW)).toEqual([
      { field: 'D', operator: 'last n days', value: 7 }
    ]);
  });

  it("works on the person's time zone and week, not the browser's", () => {
    // 03:00 UTC on 13 May is still 12 May in Los Angeles.
    const clock = makeClock({
      now: new Date(Date.UTC(2026, 4, 13, 3)),
      timeZone: 'America/Los_Angeles',
      locale: 'en_US',
      zonedParts
    });
    expect(dateBounds({ range: 'TODAY' }, clock)).toEqual({ from: '2026-05-12', to: '2026-05-12' });
    const timed = dateConditions({ range: 'TODAY', field: 'S', type: 'datetime' }, clock);
    expect(timed[0].value).toBe('2026-05-12T07:00:00.000Z');
    expect(timed[1].value).toBe('2026-05-13T07:00:00.000Z');
    // A day that ends with the clocks going back an hour is 25 hours long.
    const autumn = dateConditions(
      { range: 'CUSTOM', from: '2026-11-01', to: '2026-11-01', field: 'S', type: 'datetime' },
      clock
    );
    expect(autumn.map((condition) => condition.value)).toEqual([
      '2026-11-01T07:00:00.000Z',
      '2026-11-02T08:00:00.000Z'
    ]);
    expect(
      bucketParts('2026-05-13T03:00:00.000Z', { type: 'datetime', bucket: 'day' }, clock)
    ).toEqual(['2026-05-12']);
    expect(daysSince('2026-05-11T20:00:00.000Z', clock)).toBe(1);

    expect(weekStartOf('en_US')).toBe(0);
    expect(weekStartOf('en_GB')).toBe(1);
    expect(weekStartOf('de-DE')).toBe(1);
    const london = makeClock({ now: NOW, timeZone: 'Europe/London', locale: 'en_GB', zonedParts });
    expect(london.weekStart).toBe(1);
    // Wednesday 13 May: a Monday week runs 11 to 17 May.
    expect(dateBounds({ range: 'THIS_WEEK' }, london)).toEqual({
      from: '2026-05-11',
      to: '2026-05-17'
    });
  });
});

describe('reportingModel: requests', () => {
  it('joins conditions with AND and keeps existing logic', () => {
    expect(withConditions('', [])).toBeUndefined();
    const filter = {
      version: 1,
      logic: '1 OR 2',
      conditions: [
        { id: 1, field: 'A', operator: 'equals', value: 1 },
        { id: 2, field: 'B', operator: 'equals', value: 2 }
      ]
    };
    const joined = withConditions(JSON.stringify(filter), [{ field: 'C', operator: 'is null' }]);
    expect(joined.logic).toBe('(1 OR 2) AND 3');
    expect(joined.conditions).toHaveLength(3);
    expect(withConditions(filter, []).conditions).toHaveLength(2);
  });

  it('builds the query document of a list report', () => {
    const report = normalizeReport({
      object: 'Contact',
      columns: [{ path: 'Name' }, { path: 'Email' }],
      related: [
        {
          object: 'Gift__c',
          field: 'Donor_Contact__c',
          has: false,
          filter: { version: 1, conditions: [] }
        }
      ],
      dateRange: { range: 'THIS_YEAR', field: 'CreatedDate', type: 'datetime' },
      sort: { by: 'Email', direction: 'desc' },
      limit: 50
    });
    const document = queryDocument(report, NOW);
    expect(document.fields).toEqual(['Name', 'Email']);
    expect(document.orderBy).toEqual([{ field: 'Email', direction: 'DESC' }]);
    expect(document.limit).toBe(50);
    expect(document.related[0].has).toBe(false);
    // This year goes as the platform's date literal, worked out on the server.
    expect(document.filter.conditions).toEqual([
      { id: 1, field: 'CreatedDate', operator: 'this year' }
    ]);
    const request = runRequest(report, NOW);
    expect(request.groups).toEqual([]);
    expect(request.measures).toEqual([]);
  });

  it('builds a totals request and a page request', () => {
    const report = totalsReport({
      groups: [
        { field: 'Fund__c', type: 'reference', labelPath: 'Fund__r.Name' },
        { field: 'Gift_Date__c', type: 'date', bucket: 'month' }
      ],
      measures: [{ fn: 'count' }, { fn: 'sum', path: 'Amount__c' }],
      summaries: [{ object: 'X__c', field: 'Y__c', fn: 'count' }]
    });
    const request = runRequest(report, NOW);
    expect(request.query.fields).toEqual(['Id']);
    expect(request.query.limit).toBeUndefined();
    expect(request.groups).toEqual([
      { field: 'Fund__c' },
      { field: 'Gift_Date__c', bucket: 'month' }
    ]);
    expect(request.measures).toEqual([{ fn: 'count' }, { fn: 'sum', path: 'Amount__c' }]);
    expect(request.summaries).toEqual([]);
    // A scan sends its groupings and totals; the server works out the fields to read.
    const scan = pageRequest(report, NOW);
    expect(scan.fields).toBeUndefined();
    expect(scan.groups).toEqual(request.groups);
    expect(scan.measures).toEqual(request.measures);

    const list = normalizeReport({
      object: 'A',
      columns: [{ path: 'Id' }, { path: 'Name' }, { path: 'NAME' }, { path: 'ID' }],
      summaries: [{ object: 'X__c', field: 'Y__c', fn: 'sum', path: 'Z__c', filter: 'f' }]
    });
    const page = pageRequest(list, NOW);
    expect(page.fields).toEqual(['Name']);
    expect(page.summaries).toEqual([
      { object: 'X__c', field: 'Y__c', fn: 'sum', path: 'Z__c', filter: 'f' }
    ]);
  });
});

describe('reportingModel: scans', () => {
  it('buckets dates as the server groups them', () => {
    const date = { type: 'date' };
    expect(bucketParts('2026-05-13', { ...date })).toEqual(['2026-05-13']);
    expect(bucketParts('2026-05-13', { ...date, bucket: 'month' })).toEqual([2026, 5]);
    expect(bucketParts('2026-05-13', { ...date, bucket: 'quarter' })).toEqual([2026, 2]);
    expect(bucketParts('2026-05-13', { ...date, bucket: 'year' })).toEqual([2026]);
    expect(bucketParts('2026-01-08', { ...date, bucket: 'week' })).toEqual([2026, 2]);
    expect(bucketParts(null, { ...date, bucket: 'month' })).toEqual([null, null]);
    expect(bucketParts(new Date(2026, 4, 13, 9).toISOString(), { type: 'datetime' })).toEqual([
      '2026-05-13'
    ]);
    expect(bucketParts('Gold', { type: 'picklist' })).toEqual(['Gold']);
    expect(bucketParts(undefined, { type: 'picklist' })).toEqual([null]);
  });

  it('totals pages of records', () => {
    const report = totalsReport({
      measures: [
        { fn: 'count' },
        { fn: 'sum', path: 'Amount__c' },
        { fn: 'avg', path: 'Amount__c' },
        { fn: 'min', path: 'Amount__c' }
      ]
    });
    const highest = totalsReport({ measures: [{ fn: 'max', path: 'Amount__c' }] });
    const scan = newScan();
    scanPage(report, scan, [
      { Fund__c: 'f1', Fund__r: { Name: 'General' }, Amount__c: 10 },
      { Fund__c: 'f1', Fund__r: { Name: 'General' }, Amount__c: 30 },
      { Fund__c: 'f2', Fund__r: { Name: 'Building' }, Amount__c: null }
    ]);
    const result = scanResult(report, scan);
    expect(result.partial).toBe(false);
    expect(result.groups[0]).toEqual({
      keys: [['f1']],
      labels: ['General'],
      values: [2, 40, 20, 10]
    });
    expect(result.groups[1].values).toEqual([1, null, null, null]);
    const top = newScan();
    scanPage(highest, top, [
      { Fund__c: 'f1', Amount__c: 10 },
      { Fund__c: 'f1', Amount__c: 30 },
      { Fund__c: 'f2' }
    ]);
    expect(scanResult(highest, top).groups.map((group) => group.values[0])).toEqual([30, null]);

    const distinct = totalsReport({
      groups: [],
      measures: [{ fn: 'countDistinct', path: 'Donor__c' }],
      view: { type: 'metric' }
    });
    const second = newScan();
    scanPage(distinct, second, [
      { Donor__c: 'a' },
      { Donor__c: 'a' },
      { Donor__c: 'b' },
      { Donor__c: '' }
    ]);
    expect(scanResult(distinct, second).groups[0].values).toEqual([2]);
    second.rows = MAX_SCAN_ROWS;
    expect(scanResult(distinct, second).partial).toBe(true);
  });
});

describe('reportingModel: groups and values', () => {
  const words = { blank: '(Blank)', yes: 'Yes', no: 'No', picklist: { a: 'Apple' } };

  it('labels a grouping value', () => {
    expect(groupText({ type: 'reference' }, ['id'], 'General', words)).toEqual({
      text: 'General',
      sort: 'general'
    });
    expect(groupText({ type: 'string' }, [null], null, words)).toEqual({
      text: '(Blank)',
      sort: '￿'
    });
    expect(groupText({ type: 'date', bucket: 'year' }, [2026], null, words).text).toBe('2026');
    expect(groupText({ type: 'date', bucket: 'quarter' }, [2026, 2], null, words)).toEqual({
      text: 'Q2 2026',
      sort: '2026-02'
    });
    expect(groupText({ type: 'date', bucket: 'week' }, [2026, 3], null, words).text).toBe(
      '2026 W03'
    );
    expect(groupText({ type: 'date', bucket: 'month' }, [2026, 5], null, words, 'en-US').text).toBe(
      'May 2026'
    );
    expect(groupText({ type: 'date' }, ['2026-05-13'], null, words, 'en-US').text).toBe(
      'May 13, 2026'
    );
    expect(groupText({ type: 'boolean' }, [true], null, words).text).toBe('Yes');
    expect(groupText({ type: 'boolean' }, [false], null, words).text).toBe('No');
    expect(groupText({ type: 'double' }, [4], null, words)).toEqual({ text: '4', sort: 4 });
    expect(groupText({ type: 'picklist' }, ['a'], null, words).text).toBe('Apple');
  });

  it('orders groups by total, largest first, and cuts to the top N', () => {
    const report = totalsReport({ limit: 2 });
    const result = {
      groups: [
        { keys: [['a']], labels: ['A'], values: [5] },
        { keys: [['b']], labels: ['B'], values: [50] },
        { keys: [['c']], labels: ['C'], values: [20] }
      ]
    };
    const arranged = arrangeGroups(report, result, words);
    expect(arranged.items.map((item) => item.texts[0])).toEqual(['B', 'C']);
    expect(arranged.trimmed).toBe(true);
    const ascending = arrangeGroups(
      totalsReport({ sort: { by: 'g0', direction: 'asc' } }),
      result,
      words
    );
    expect(ascending.items.map((item) => item.texts[0])).toEqual(['A', 'B', 'C']);
  });

  it('orders a date grouping by date and ranks the first of two groupings by its total', () => {
    const report = totalsReport({
      groups: [
        { field: 'Fund__c', type: 'reference' },
        { field: 'Status__c', type: 'picklist' }
      ],
      limit: 1
    });
    const result = {
      groups: [
        { keys: [['f1'], ['Paid']], labels: ['One', null], values: [5] },
        { keys: [['f2'], ['Paid']], labels: ['Two', null], values: [3] },
        { keys: [['f2'], ['Open']], labels: ['Two', null], values: [4] }
      ]
    };
    const arranged = arrangeGroups(report, result, words);
    expect(arranged.items.map((item) => item.texts.join('/'))).toEqual(['Two/Open', 'Two/Paid']);
    const byDate = totalsReport({ groups: [{ field: 'D', type: 'date', bucket: 'month' }] });
    const dated = arrangeGroups(
      byDate,
      {
        groups: [
          { keys: [[2026, 2]], values: [1] },
          { keys: [[2026, 1]], values: [9] }
        ]
      },
      words
    );
    expect(dated.items.map((item) => item.keys[0])).toEqual(['2026-01', '2026-02']);
    expect(arrangeGroups(byDate, null, words).items).toEqual([]);
  });

  it('formats values by type', () => {
    const options = { locale: 'en-US', currency: 'USD', timeZone: 'UTC', yes: 'Yes', no: 'No' };
    expect(formatValue(null, 'string', options)).toBe('');
    expect(formatValue(1234.5, 'currency', options)).toBe('$1,234.50');
    expect(formatValue(12.5, 'percent', options)).toBe('12.5%');
    expect(formatValue(1234.567, 'double', options)).toBe('1,234.57');
    expect(formatValue('2026-05-13', 'date', options)).toBe('May 13, 2026');
    expect(formatValue('2026-05-13T15:00:00.000Z', 'datetime', options)).toMatch(/May 13, 2026/);
    expect(formatValue(true, 'boolean', options)).toBe('Yes');
    expect(formatValue(false, 'boolean', {})).toBe('false');
    expect(formatValue('x', 'string', options)).toBe('x');
    expect(formatValue(5, 'currency', { currency: 'NOPE' })).toBe('5');
  });

  it('counts days since a date', () => {
    expect(daysSince('2026-05-10', NOW)).toBe(3);
    expect(daysSince(new Date(2026, 4, 1, 23).toISOString(), NOW)).toBe(12);
    expect(daysSince('', NOW)).toBeNull();
    expect(daysSince('not a date', NOW)).toBeNull();
  });

  it('lays out list rows with related totals, and group tables', () => {
    const report = normalizeReport({
      object: 'Account',
      columns: [
        { path: 'Name', label: 'Name' },
        { path: 'CreatedDate', label: 'Age', type: 'datetime', show: 'age' }
      ],
      summaries: [
        { object: 'Gift__c', field: 'Household__c', fn: 'count', label: 'Gifts' },
        {
          object: 'Gift__c',
          field: 'Household__c',
          fn: 'sum',
          path: 'Amount__c',
          label: 'Total',
          type: 'currency'
        }
      ]
    });
    const table = tableRows(
      report,
      {
        rows: [{ Id: 'a1', Name: 'Ames', CreatedDate: new Date(2026, 4, 11, 8).toISOString() }],
        summaries: [{}, { a1: 25 }]
      },
      { locale: 'en-US', currency: 'USD' },
      NOW
    );
    expect(table.headers.map((header) => header.label)).toEqual(['Name', 'Age', 'Gifts', 'Total']);
    expect(table.rows[0].id).toBe('a1');
    expect(table.rows[0].cells.map((cell) => cell.text)).toEqual(['Ames', '2', '0', '$25.00']);
    expect(csvValue(table.rows[0].cells[3])).toBe(25);
    expect(csvValue(table.rows[0].cells[0])).toBe('Ames');
    expect(tableRows(report, null).rows).toEqual([]);

    const totals = totalsReport();
    const arranged = arrangeGroups(
      totals,
      { groups: [{ keys: [['f']], labels: ['General'], values: [10] }] },
      words
    );
    const grouped = groupTable(totals, arranged, { locale: 'en-US', currency: 'USD' });
    expect(grouped.headers.map((header) => header.key)).toEqual(['g0', 'm0']);
    expect(grouped.rows[0].cells.map((cell) => cell.text)).toEqual(['General', '$10.00']);
  });
});

describe('reportingModel: dashboards', () => {
  const dashboard = normalizeDashboard({
    title: 'Giving',
    filters: [
      { key: 'dates', kind: 'date', label: 'Gift Date' },
      { key: 'fund', kind: 'record', label: 'Fund', object: 'Fund__c' },
      { key: 'appeal', kind: 'record', label: 'Appeal', object: 'Appeal__c' },
      { key: 'bad', kind: 'record' }
    ],
    widgets: [
      {
        key: 'w1',
        size: 'huge',
        report: totalsReport({ title: 'By Fund' }),
        bindings: {
          dates: { field: 'Gift_Date__c', type: 'date' },
          fund: { field: 'Fund__c', related: { object: 'Gift_Allocation__c', field: 'Gift__c' } },
          ignored: { nothing: true }
        }
      },
      {
        key: 'w1',
        report: { object: 'Contact', columns: [{ path: 'Name' }] },
        bindings: { fund: { field: 'Fund__c' } }
      },
      { title: 'No report' }
    ],
    sharing: { users: [] }
  });

  it('normalizes a dashboard', () => {
    expect(dashboard.filters.map((filter) => filter.key)).toEqual(['dates', 'fund', 'appeal']);
    expect(dashboard.widgets.map((widget) => widget.key)).toEqual(['w1', 'w1x']);
    expect(dashboard.widgets[0].size).toBe('medium');
    expect(dashboard.widgets[0].title).toBe('By Fund');
    expect(Object.keys(dashboard.widgets[0].bindings)).toEqual(['dates', 'fund']);
    // Sharing never travels in a definition; only Share changes it.
    expect(dashboard.sharing).toBeUndefined();
    expect(newDashboard().widgets).toEqual([]);
    expect(nextWidgetKey(dashboard)).toBe('w3');
    expect(nextWidgetKey(normalizeDashboard({ widgets: [{ key: 'w2', report: {} }] }))).toBe('w3');
    expect(nextWidgetKey(null)).toBe('w1');
  });

  it('replaces one entry of a list without changing the original', () => {
    const list = [{ n: 1 }, { n: 2 }];
    const next = replaceAt(list, 1, (entry) => ({ ...entry, n: 5 }));
    expect(next).toEqual([{ n: 1 }, { n: 5 }]);
    expect(list[1].n).toBe(2);
    expect(next[0]).toBe(list[0]);
    expect(replaceAt(list, -1, () => ({}))).toEqual(list);
    expect(replaceAt(null, 0, () => ({}))).toEqual([]);
  });

  it('applies dashboard filters to a widget and says which do not apply', () => {
    const values = { dates: { range: 'LAST_YEAR' }, fund: 'a01', appeal: 'a02' };
    const first = applyFilters(dashboard.widgets[0], dashboard.filters, values);
    expect(first.report.dateRange).toEqual({
      range: 'LAST_YEAR',
      field: 'Gift_Date__c',
      type: 'date'
    });
    expect(first.report.related).toEqual([
      {
        object: 'Gift_Allocation__c',
        field: 'Gift__c',
        label: 'Fund',
        has: true,
        filter: {
          version: 1,
          conditions: [{ id: 1, field: 'Fund__c', operator: 'equals', value: 'a01' }]
        }
      }
    ]);
    expect(first.unfiltered).toEqual(['Appeal']);
    expect(dashboard.widgets[0].report.related).toEqual([]);

    const second = applyFilters(dashboard.widgets[1], dashboard.filters, { fund: 'a01' });
    expect(second.report.filter.conditions).toEqual([
      { id: 1, field: 'Fund__c', operator: 'equals', value: 'a01' }
    ]);
    expect(applyFilters(dashboard.widgets[1], dashboard.filters, {}).unfiltered).toEqual([]);

    const full = {
      ...dashboard.widgets[0],
      report: { ...dashboard.widgets[0].report, related: [{}, {}] }
    };
    expect(applyFilters(full, dashboard.filters, { fund: 'a01' }).unfiltered).toEqual(['Fund']);
  });

  it('lists the objects a dashboard needs and offers only installed templates', () => {
    expect([...objectsUsed(dashboard)].sort()).toEqual([
      'Appeal__c',
      'Contact',
      'Fund__c',
      'Gift__c'
    ]);
    const templates = [
      { key: 'giving', requires: ['Gift__c'], ...dashboard },
      {
        key: 'board',
        requires: ['Board_Member__c'],
        widgets: [{ report: { object: 'Board_Member__c' } }]
      },
      { key: 'empty', requires: [], widgets: [{ report: { object: 'Missing__c' } }] }
    ];
    const offered = new Set(['Gift__c', 'Fund__c']);
    const kept = availableTemplates(templates, offered);
    expect(kept.map((template) => template.key)).toEqual(['giving']);
    expect(kept[0].dashboard.filters.map((filter) => filter.key)).toEqual(['dates', 'fund']);
    expect(kept[0].dashboard.widgets.map((widget) => widget.key)).toEqual(['w1']);
    expect(availableTemplates(undefined, offered)).toEqual([]);
  });

  it('moves entries', () => {
    expect(moved(['a', 'b', 'c'], 0, 1)).toEqual(['b', 'a', 'c']);
    expect(moved(['a', 'b'], 0, -1)).toEqual(['a', 'b']);
    expect(moved(undefined, 0, 1)).toEqual([]);
  });
});
