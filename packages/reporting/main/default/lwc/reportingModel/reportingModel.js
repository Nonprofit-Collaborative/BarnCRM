/**
 * Advanced Reporting's definition model (ADR-0231 advanced reporting, canonical model 29AR):
 * what a saved report and dashboard hold, how a report becomes the run request
 * ReportingQueryService checks, how dashboard-wide filters reach each widget, how records read
 * in pages are totalled when a report is too large for one aggregate query, and how groups are
 * labelled, sorted and cut to the top N.
 *
 * Framework free (plan 9.9): no Lightning or Salesforce import, so the same file runs in the
 * browser, in Jest and in BarnCRM for WordPress. Words a person reads come from the caller.
 */
import { OPERATORS, parseDocument, serializeDocument } from 'c/filterDocument';

export const VERSION = 1;
export const MAX_COLUMNS = 20;
export const MAX_GROUPS = 2;
export const MAX_MEASURES = 4;
export const MAX_SUMMARIES = 3;
export const MAX_RELATED = 2;
export const MAX_ROWS = 2000;
export const DEFAULT_ROWS = 200;
export const PAGE_SIZE = 5000;
export const EXPORT_PAGE_SIZE = 2000;
export const MAX_SCAN_ROWS = 1000000;
export const MAX_EXPORT_ROWS = 100000;
export const MAX_WIDGETS = 12;
export const MAX_FILTERS = 4;

export const VIEWS = ['table', 'bar', 'column', 'line', 'donut', 'metric'];
export const FUNCTIONS = ['count', 'sum', 'avg', 'min', 'max', 'countDistinct'];
export const BUCKETS = ['day', 'week', 'month', 'quarter', 'year'];
export const SIZES = ['small', 'medium', 'large'];
export const RANGES = [
  'TODAY',
  'YESTERDAY',
  'THIS_WEEK',
  'LAST_WEEK',
  'THIS_MONTH',
  'LAST_MONTH',
  'THIS_QUARTER',
  'LAST_QUARTER',
  'THIS_YEAR',
  'LAST_YEAR',
  'LAST_N_DAYS',
  'NEXT_N_DAYS',
  'LAST_N_MONTHS',
  'BETWEEN_DAYS_AGO',
  'CUSTOM'
];
/** The ranges that take a number of days or months (`n`), and the one that takes two. */
export const COUNTED_RANGES = ['LAST_N_DAYS', 'NEXT_N_DAYS', 'LAST_N_MONTHS', 'BETWEEN_DAYS_AGO'];

export const NUMBER_TYPES = new Set(['currency', 'double', 'integer', 'long', 'percent', 'int']);
export const DATE_TYPES = new Set(['date', 'datetime']);

const pad = (value) => String(value).padStart(2, '0');
const clone = (value) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)));
const asArray = (value) => (Array.isArray(value) ? value : []);
const clamp = (value, low, high, fallback) => {
  const number = Math.floor(Number(value));
  return Number.isFinite(number) ? Math.min(high, Math.max(low, number)) : fallback;
};

/** The value at a field path such as `Fund__r.Name` in a record read from the server. */
export function valueAt(row, path) {
  return String(path || '')
    .split('.')
    .reduce(
      (current, name) => (current === undefined || current === null ? undefined : current[name]),
      row
    );
}

/**
 * For a lookup field path such as `Gift__r.Fund__c`, the path to its record's Name
 * (`Gift__r.Fund__r.Name`), given the field's relationship name from describe; else null.
 */
export function namePath(path, relationshipName) {
  if (!relationshipName) {
    return null;
  }
  const parts = String(path).split('.');
  parts[parts.length - 1] = relationshipName;
  return parts.join('.') + '.Name';
}

// ---------------------------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------------------------

/** A new, empty report on an object. */
export function newReport(objectName) {
  return normalizeReport({ object: objectName || '' });
}

/** A report read from storage or a template, with every part present and within limits. */
export function normalizeReport(raw) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const view = source.view && typeof source.view === 'object' ? source.view : {};
  const sort = source.sort && typeof source.sort === 'object' ? source.sort : null;
  return {
    version: VERSION,
    title: String(source.title || ''),
    object: String(source.object || ''),
    columns: asArray(source.columns)
      .filter((column) => column && column.path)
      .slice(0, MAX_COLUMNS)
      .map((column) => ({
        path: String(column.path),
        label: String(column.label || column.path),
        type: String(column.type || 'string'),
        ...(column.show === 'age' ? { show: 'age' } : {})
      })),
    filter: source.filter || '',
    related: asArray(source.related)
      .filter((entry) => entry && entry.object && entry.field)
      .slice(0, MAX_RELATED)
      .map((entry) => ({
        object: String(entry.object),
        field: String(entry.field),
        label: String(entry.label || entry.object),
        has: entry.has !== false,
        ...(entry.filter ? { filter: entry.filter } : {})
      })),
    dateRange: normalizeRange(source.dateRange),
    groups: asArray(source.groups)
      .filter((group) => group && group.field)
      .slice(0, MAX_GROUPS)
      .map((group) => ({
        field: String(group.field),
        label: String(group.label || group.field),
        type: String(group.type || 'string'),
        ...(group.bucket && BUCKETS.includes(group.bucket) ? { bucket: group.bucket } : {}),
        ...(group.labelPath ? { labelPath: String(group.labelPath) } : {}),
        ...(group.picklist &&
        typeof group.picklist === 'object' &&
        Object.keys(group.picklist).length
          ? { picklist: { ...group.picklist } }
          : {})
      })),
    measures: asArray(source.measures)
      .filter((measure) => measure && FUNCTIONS.includes(measure.fn))
      .filter((measure) => measure.fn === 'count' || measure.path)
      .slice(0, MAX_MEASURES)
      .map((measure) => ({
        fn: measure.fn,
        ...(measure.fn === 'count' ? {} : { path: String(measure.path) }),
        label: String(measure.label || measure.fn),
        type:
          measure.fn === 'count' || measure.fn === 'countDistinct'
            ? 'integer'
            : String(measure.type || 'double')
      })),
    summaries: asArray(source.summaries)
      .filter((entry) => entry && entry.object && entry.field && FUNCTIONS.includes(entry.fn))
      .slice(0, MAX_SUMMARIES)
      .map((entry) => ({
        object: String(entry.object),
        field: String(entry.field),
        fn: entry.fn,
        ...(entry.fn === 'count' ? {} : { path: String(entry.path || '') }),
        label: String(entry.label || entry.object),
        type: entry.fn === 'count' ? 'integer' : String(entry.type || 'double'),
        ...(entry.filter ? { filter: entry.filter } : {})
      })),
    sort:
      sort && sort.by
        ? { by: String(sort.by), direction: sort.direction === 'desc' ? 'desc' : 'asc' }
        : null,
    limit: clamp(source.limit, 1, MAX_ROWS, DEFAULT_ROWS),
    view: {
      type: VIEWS.includes(view.type) ? view.type : 'table',
      stacked: view.stacked === true
    }
  };
}

/** True when the report totals (groups or a single total), false when it lists records. */
export function isTotals(report) {
  return asArray(report && report.measures).length > 0;
}

/**
 * What stops a report from running, as problem codes the screen turns into words:
 * `object`, `columns` (a list with no column), `measure` (groups with no total), `chart` (a
 * chart with no grouping), `metric` (a metric tile with a grouping).
 */
export function reportProblems(report) {
  const problems = [];
  if (!report || !report.object) {
    return ['object'];
  }
  const totals = isTotals(report);
  if (!totals && report.groups.length > 0) {
    problems.push('measure');
  }
  if (!totals && report.columns.length === 0) {
    problems.push('columns');
  }
  const type = report.view.type;
  if (['bar', 'column', 'line', 'donut'].includes(type) && report.groups.length === 0) {
    problems.push('chart');
  }
  if (type === 'metric' && (!totals || report.groups.length > 0)) {
    problems.push('metric');
  }
  return problems;
}

// ---------------------------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------------------------

/** A date range read from storage: `{ range, n, m, from, to }` plus a field when it has one. */
export function normalizeRange(raw) {
  if (!raw || typeof raw !== 'object' || !RANGES.includes(raw.range)) {
    return null;
  }
  const range = { range: raw.range };
  if (raw.field) {
    range.field = String(raw.field);
    range.type = raw.type === 'datetime' ? 'datetime' : 'date';
    if (raw.label) {
      range.label = String(raw.label);
    }
  }
  if (COUNTED_RANGES.includes(raw.range)) {
    range.n = clamp(raw.n, 1, 3650, 30);
  }
  if (raw.range === 'BETWEEN_DAYS_AGO') {
    range.m = clamp(raw.m, 0, 3650, 0);
  }
  if (raw.range === 'CUSTOM') {
    range.from = isIsoDate(raw.from) ? raw.from : '';
    range.to = isIsoDate(raw.to) ? raw.to : '';
  }
  return range;
}

function isIsoDate(value) {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
}

// Calendar days are held as UTC midnights, so day arithmetic never meets a daylight saving
// change; the person's own time zone only decides which day it is (makeClock).
function iso(date) {
  return `${date.getUTCFullYear()}-${pad(date.getUTCMonth() + 1)}-${pad(date.getUTCDate())}`;
}

function day(year, month, date) {
  return new Date(Date.UTC(year, month, date));
}

function fromIso(text) {
  const [year, month, date] = text.split('-').map(Number);
  return day(year, month - 1, date);
}

function shift(date, days) {
  return day(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate() + days);
}

function localParts(value) {
  const moment = new Date(value);
  if (Number.isNaN(moment.getTime())) {
    return null;
  }
  return {
    year: moment.getFullYear(),
    month: moment.getMonth() + 1,
    day: moment.getDate(),
    hour: moment.getHours(),
    minute: moment.getMinutes(),
    second: moment.getSeconds()
  };
}

/** Regions whose week starts on Sunday, for a browser without Intl week information. */
const SUNDAY_REGIONS = new Set(['US', 'CA', 'MX', 'BR', 'JP', 'KR', 'IL', 'PH', 'IN', 'ZA', 'TW']);

/** The first day of the week in a locale such as `en_US`: 0 for Sunday to 6 for Saturday. */
export function weekStartOf(locale) {
  const tag = String(locale || 'en_US').replace(/_/g, '-');
  try {
    const parsed = new Intl.Locale(tag);
    const week = typeof parsed.getWeekInfo === 'function' ? parsed.getWeekInfo() : parsed.weekInfo;
    if (week && week.firstDay) {
      return week.firstDay % 7;
    }
  } catch {
    // An unknown tag falls back to the region list below.
  }
  const region = (tag.split('-')[1] || 'US').toUpperCase();
  return SUNDAY_REGIONS.has(region) ? 0 : 1;
}

/**
 * The person's calendar for one run, made once and reused for every page: `now`, today in
 * their Salesforce time zone, their locale's first day of the week, and `partsOf(value)`, a
 * date and time's calendar parts in that zone. `zonedParts` is Core's (c/findCsv), passed in so
 * this file stays framework free; without it (or a zone) the browser's own zone is used.
 */
export function makeClock({ now = new Date(), timeZone, locale, zonedParts } = {}) {
  const partsOf = zonedParts && timeZone ? (value) => zonedParts(value, timeZone) : localParts;
  const parts = partsOf(now);
  return {
    now,
    partsOf,
    today: day(parts.year, parts.month - 1, parts.day),
    weekStart: weekStartOf(locale)
  };
}

/** A clock from `makeClock`, or one made from a plain Date (or now) in the browser's zone. */
function toClock(value) {
  if (value && value.today && value.partsOf) {
    return value;
  }
  return makeClock({ now: value instanceof Date ? value : new Date() });
}

/** The instant a calendar day starts in the clock's time zone, as an ISO date and time. */
function zonedMidnight(clock, date) {
  const target = date.getTime();
  let guess = target;
  // Two corrections settle the zone's offset, including on a daylight saving change day.
  for (let pass = 0; pass < 2; pass++) {
    const parts = clock.partsOf(guess);
    const shown = Date.UTC(
      parts.year,
      parts.month - 1,
      parts.day,
      parts.hour % 24,
      parts.minute,
      parts.second
    );
    guess += target - shown;
  }
  return new Date(guess).toISOString();
}

/** The named ranges Core's filter writes as the platform's own date literals. */
const LITERAL_OPERATORS = {
  THIS_YEAR: OPERATORS.THIS_YEAR,
  LAST_YEAR: OPERATORS.LAST_YEAR,
  LAST_N_DAYS: OPERATORS.LAST_N_DAYS
};

/**
 * The first and last day of a range, as YYYY-MM-DD, on the person's calendar (`clock`, from
 * makeClock; a plain Date is read in the browser's zone). Either end may be empty for a custom
 * range left open. Null when the range is unknown.
 */
export function dateBounds(spec, clock) {
  const range = normalizeRange(spec);
  if (!range) {
    return null;
  }
  const { today, weekStart: firstDay } = toClock(clock);
  const year = today.getUTCFullYear();
  const month = today.getUTCMonth();
  const quarter = Math.floor(month / 3) * 3;
  const weekStart = shift(today, -((today.getUTCDay() - firstDay + 7) % 7));
  const span = (from, to) => ({ from: from ? iso(from) : '', to: to ? iso(to) : '' });
  switch (range.range) {
    case 'TODAY':
      return span(today, today);
    case 'YESTERDAY':
      return span(shift(today, -1), shift(today, -1));
    case 'THIS_WEEK':
      return span(weekStart, shift(weekStart, 6));
    case 'LAST_WEEK':
      return span(shift(weekStart, -7), shift(weekStart, -1));
    case 'THIS_MONTH':
      return span(day(year, month, 1), day(year, month + 1, 0));
    case 'LAST_MONTH':
      return span(day(year, month - 1, 1), day(year, month, 0));
    case 'THIS_QUARTER':
      return span(day(year, quarter, 1), day(year, quarter + 3, 0));
    case 'LAST_QUARTER':
      return span(day(year, quarter - 3, 1), day(year, quarter, 0));
    case 'THIS_YEAR':
      return span(day(year, 0, 1), day(year, 11, 31));
    case 'LAST_YEAR':
      return span(day(year - 1, 0, 1), day(year - 1, 11, 31));
    case 'LAST_N_DAYS':
      return span(shift(today, -range.n), today);
    case 'NEXT_N_DAYS':
      return span(today, shift(today, range.n));
    case 'LAST_N_MONTHS':
      return span(day(year, month - range.n + 1, 1), day(year, month + 1, 0));
    case 'BETWEEN_DAYS_AGO':
      return span(
        shift(today, -Math.max(range.n, range.m)),
        shift(today, -Math.min(range.n, range.m))
      );
    default:
      return {
        from: range.from || '',
        to: range.to || ''
      };
  }
}

/**
 * The filter conditions (canonical model R-R2) a date range adds on its field. This year, last
 * year and the last n days go as the platform's date literals, so the server works them out in
 * the person's time zone. Every other range goes from its first day to its last on the person's
 * calendar; a date and time field is compared from midnight at the start to the midnight after
 * the end in the person's time zone, written in UTC.
 */
export function dateConditions(spec, clock) {
  const range = normalizeRange(spec);
  if (!range || !range.field) {
    return [];
  }
  const literal = LITERAL_OPERATORS[range.range];
  if (literal) {
    return [
      {
        field: range.field,
        operator: literal,
        ...(range.range === 'LAST_N_DAYS' ? { value: range.n } : {})
      }
    ];
  }
  const calendar = toClock(clock);
  const bounds = dateBounds(range, calendar);
  const conditions = [];
  if (range.type === 'datetime') {
    if (bounds.from) {
      conditions.push({
        field: range.field,
        operator: 'greater or equal',
        value: zonedMidnight(calendar, fromIso(bounds.from))
      });
    }
    if (bounds.to) {
      conditions.push({
        field: range.field,
        operator: 'less than',
        value: zonedMidnight(calendar, shift(fromIso(bounds.to), 1))
      });
    }
  } else {
    if (bounds.from) {
      conditions.push({ field: range.field, operator: 'greater or equal', value: bounds.from });
    }
    if (bounds.to) {
      conditions.push({ field: range.field, operator: 'less or equal', value: bounds.to });
    }
  }
  return conditions;
}

// ---------------------------------------------------------------------------------------------
// Run requests
// ---------------------------------------------------------------------------------------------

/**
 * A filter document (R-R2) with more conditions joined by AND. Conditions are written as the
 * filter builder writes them; an existing logic string keeps its meaning. Undefined when there
 * is no condition at all.
 */
export function withConditions(filter, extra) {
  const base = parseDocument(
    typeof filter === 'string' ? filter : filter ? JSON.stringify(filter) : ''
  );
  const added = asArray(extra);
  const conditions = [...base.conditions, ...added];
  if (conditions.length === 0) {
    return undefined;
  }
  let logic = base.logic;
  if (logic && added.length) {
    logic =
      `(${logic})` +
      added.map((unused, index) => ` AND ${base.conditions.length + index + 1}`).join('');
  }
  return JSON.parse(serializeDocument(conditions, logic));
}

/**
 * The Find query document (canonical model R-SQ1) for a report: its object, columns (only Id
 * when it totals), filter with its date range, related-record conditions, sort and row limit.
 * `clock` is the run's (makeClock).
 */
export function queryDocument(report, clock) {
  const totals = isTotals(report);
  const paths = [...new Set(report.columns.map((column) => column.path))];
  const document = {
    version: 1,
    object: report.object,
    fields: totals || paths.length === 0 ? ['Id'] : paths
  };
  const filter = withConditions(report.filter, dateConditions(report.dateRange, clock));
  if (filter) {
    document.filter = filter;
  }
  if (report.related.length) {
    document.related = report.related.map((entry) => ({
      object: entry.object,
      field: entry.field,
      has: entry.has,
      ...(entry.filter ? { filter: entry.filter } : {})
    }));
  }
  if (!totals) {
    if (report.sort && paths.includes(report.sort.by)) {
      document.orderBy = [
        { field: report.sort.by, direction: report.sort.direction === 'desc' ? 'DESC' : 'ASC' }
      ];
    }
    document.limit = report.limit;
  }
  return document;
}

/** What `ReportingQueryService.run` takes for a report. */
export function runRequest(report, clock) {
  const totals = isTotals(report);
  return {
    query: queryDocument(report, clock),
    groups: totals ? groupRequests(report) : [],
    measures: totals ? measureRequests(report) : [],
    summaries: totals ? [] : report.summaries.map(summaryRequest)
  };
}

function groupRequests(report) {
  return report.groups.map((group) => ({
    field: group.field,
    ...(group.bucket ? { bucket: group.bucket } : {})
  }));
}

function measureRequests(report) {
  return report.measures.map((measure) => ({
    fn: measure.fn,
    ...(measure.path ? { path: measure.path } : {})
  }));
}

function summaryRequest(entry) {
  return {
    object: entry.object,
    field: entry.field,
    fn: entry.fn,
    ...(entry.path ? { path: entry.path } : {}),
    ...(entry.filter ? { filter: entry.filter } : {})
  };
}

/**
 * What `ReportingQueryService.page` takes. For a list's export: the columns, each once whatever
 * its case and never Id, with the related totals. For a scan of a totals report: its groupings
 * and totals, from which the server works out the fields to read.
 */
export function pageRequest(report, clock) {
  const query = queryDocument(report, clock);
  if (isTotals(report)) {
    return { query, groups: groupRequests(report), measures: measureRequests(report) };
  }
  const fields = new Map();
  for (const column of report.columns) {
    const key = column.path.toLowerCase();
    if (key !== 'id' && !fields.has(key)) {
      fields.set(key, column.path);
    }
  }
  return { query, fields: [...fields.values()], summaries: report.summaries.map(summaryRequest) };
}

// ---------------------------------------------------------------------------------------------
// Totals read in pages (scan)
// ---------------------------------------------------------------------------------------------

/** The week of the year as SOQL's WEEK_IN_YEAR counts it: days 1 to 7 are week 1. */
function weekInYear(date) {
  const start = day(date.getUTCFullYear(), 0, 1);
  const dayOfYear = Math.round((date - start) / 86400000) + 1;
  return Math.ceil(dayOfYear / 7);
}

/** A date or date and time as its calendar day; a date and time on the clock's calendar. */
function calendarDay(value, type, clock) {
  if (type !== 'datetime') {
    return fromIso(String(value).slice(0, 10));
  }
  const parts = toClock(clock).partsOf(value);
  return parts ? day(parts.year, parts.month - 1, parts.day) : null;
}

/**
 * A grouping value as the server groups it: a date in its bucket (day `YYYY-MM-DD`; week,
 * month and quarter as [year, number]; year as [year]), anything else as it is. A date and time
 * falls on its day in the person's time zone (`clock`), as the server's convertTimezone does.
 */
export function bucketParts(value, group, clock) {
  const bucket = group.bucket || 'day';
  if (!DATE_TYPES.has(group.type)) {
    return [value === undefined ? null : value];
  }
  const width = bucket === 'day' || bucket === 'year' ? 1 : 2;
  const date =
    value === null || value === undefined || value === ''
      ? null
      : calendarDay(value, group.type, clock);
  if (!date) {
    return new Array(width).fill(null);
  }
  const year = date.getUTCFullYear();
  switch (bucket) {
    case 'week':
      return [year, weekInYear(date)];
    case 'month':
      return [year, date.getUTCMonth() + 1];
    case 'quarter':
      return [year, Math.floor(date.getUTCMonth() / 3) + 1];
    case 'year':
      return [year];
    default:
      return [iso(date)];
  }
}

/** A running total for a scan; feed it pages with `scanPage`, read it with `scanResult`. */
export function newScan() {
  return { rows: 0, groups: new Map() };
}

/** Adds one page of records to a scan, dates bucketed on the run's `clock` (makeClock). */
export function scanPage(report, scan, rows, clock) {
  const calendar = toClock(clock);
  for (const row of asArray(rows)) {
    scan.rows++;
    const keys = report.groups.map((group) =>
      bucketParts(valueAt(row, group.field), group, calendar)
    );
    const id = JSON.stringify(keys);
    let entry = scan.groups.get(id);
    if (!entry) {
      entry = {
        keys,
        labels: report.groups.map((group) => {
          const label = group.labelPath ? valueAt(row, group.labelPath) : undefined;
          return label === undefined ? null : label;
        }),
        totals: report.measures.map(() => ({
          sum: 0,
          count: 0,
          min: undefined,
          max: undefined,
          seen: new Set()
        }))
      };
      scan.groups.set(id, entry);
    }
    report.measures.forEach((measure, index) => {
      const total = entry.totals[index];
      if (measure.fn === 'count') {
        total.count++;
        return;
      }
      const value = valueAt(row, measure.path);
      if (value === null || value === undefined || value === '') {
        return;
      }
      if (measure.fn === 'countDistinct') {
        total.seen.add(String(value));
        return;
      }
      total.count++;
      if (typeof value === 'number') {
        total.sum += value;
      }
      if (total.min === undefined || value < total.min) {
        total.min = value;
      }
      if (total.max === undefined || value > total.max) {
        total.max = value;
      }
    });
  }
  return scan;
}

/** A scan's groups in the shape the server returns: `{ groups: [{ keys, labels, values }] }`. */
export function scanResult(report, scan) {
  const groups = [...scan.groups.values()].map((entry) => ({
    keys: entry.keys,
    labels: entry.labels,
    values: report.measures.map((measure, index) => {
      const total = entry.totals[index];
      switch (measure.fn) {
        case 'count':
          return total.count;
        case 'countDistinct':
          return total.seen.size;
        case 'sum':
          return total.count ? total.sum : null;
        case 'avg':
          return total.count ? total.sum / total.count : null;
        case 'min':
          return total.min === undefined ? null : total.min;
        default:
          return total.max === undefined ? null : total.max;
      }
    })
  }));
  return { groups, more: false, partial: scan.rows >= MAX_SCAN_ROWS };
}

// ---------------------------------------------------------------------------------------------
// Groups: labels, order, top N
// ---------------------------------------------------------------------------------------------

const MONTH_FORMATS = new Map();

function monthName(year, month, locale) {
  const key = locale || '';
  if (!MONTH_FORMATS.has(key)) {
    MONTH_FORMATS.set(
      key,
      new Intl.DateTimeFormat(locale || undefined, {
        month: 'short',
        year: 'numeric',
        timeZone: 'UTC'
      })
    );
  }
  return MONTH_FORMATS.get(key).format(day(year, month - 1, 1));
}

/**
 * One grouping value as a person reads it and as it sorts. `words` gives `blank`, `yes`, `no`
 * and `picklist` (API value to label, per group index) from the caller.
 */
export function groupText(group, keys, label, words = {}, locale) {
  const first = keys[0];
  if (label !== null && label !== undefined && label !== '') {
    return { text: String(label), sort: String(label).toLowerCase() };
  }
  if (first === null || first === undefined || first === '') {
    return { text: words.blank || '', sort: '￿' };
  }
  if (DATE_TYPES.has(group.type)) {
    const bucket = group.bucket || 'day';
    if (bucket === 'day') {
      return { text: formatDay(String(first), locale), sort: String(first) };
    }
    if (bucket === 'year') {
      return { text: String(first), sort: String(first) };
    }
    const second = keys[1];
    const sort = `${first}-${pad(second)}`;
    if (bucket === 'month') {
      return { text: monthName(first, second, locale), sort };
    }
    return {
      text: bucket === 'quarter' ? `Q${second} ${first}` : `${first} W${pad(second)}`,
      sort
    };
  }
  if (group.type === 'boolean') {
    return {
      text: first === true || first === 'true' ? words.yes || 'true' : words.no || 'false',
      sort: String(first)
    };
  }
  if (NUMBER_TYPES.has(group.type)) {
    return { text: String(first), sort: Number(first) };
  }
  const picklist = words.picklist || {};
  const text = Object.prototype.hasOwnProperty.call(picklist, first)
    ? picklist[first]
    : String(first);
  return { text, sort: text.toLowerCase() };
}

function formatDay(text, locale) {
  if (!isIsoDate(text)) {
    return text;
  }
  try {
    return new Intl.DateTimeFormat(locale || undefined, {
      dateStyle: 'medium',
      timeZone: 'UTC'
    }).format(fromIso(text));
  } catch {
    return text;
  }
}

const compare = (left, right) => {
  if (typeof left === 'number' && typeof right === 'number') {
    return left - right;
  }
  return String(left).localeCompare(String(right));
};

/**
 * The groups of a result in the report's order, cut to its top N: `{ items, trimmed }`. Each
 * item is `{ key, keys: [first, second], texts: [..], values: [..] }`. The default order is by
 * date for a date grouping, otherwise by the first total, largest first. With two groupings,
 * the top N applies to the first, ranked by its total across the second.
 */
export function arrangeGroups(report, result, words = {}, locale) {
  const groups = report.groups;
  const items = asArray(result && result.groups).map((row, index) => {
    const parts = groups.map((group, g) =>
      groupText(
        group,
        asArray(row.keys[g]),
        row.labels ? row.labels[g] : null,
        { ...words, picklist: (words.picklists || [])[g] },
        locale
      )
    );
    return {
      key: `r${index}`,
      keys: parts.map((part) => part.sort),
      texts: parts.map((part) => part.text),
      values: asArray(row.values).map((value) => (value === undefined ? null : value))
    };
  });
  const sort = report.sort || {
    by: groups.length && DATE_TYPES.has(groups[0].type) ? 'g0' : 'm0',
    direction: groups.length && DATE_TYPES.has(groups[0].type) ? 'asc' : 'desc'
  };
  const sign = sort.direction === 'desc' ? -1 : 1;
  const firstKey = (item) => (groups.length ? item.keys[0] : '');
  const firstOrder = new Map();
  for (const item of items) {
    const first = firstKey(item);
    const current = firstOrder.get(first) || { key: first, measure: 0 };
    const index = sort.by.startsWith('m') ? Number(sort.by.slice(1)) : 0;
    current.measure += Number(item.values[index]) || 0;
    firstOrder.set(first, current);
  }
  const ranked = [...firstOrder.values()].sort((left, right) => {
    if (sort.by === 'g1') {
      return 0;
    }
    return sort.by.startsWith('m')
      ? sign * (left.measure - right.measure)
      : sign * compare(left.key, right.key);
  });
  const kept = ranked.slice(0, report.limit);
  const position = new Map(kept.map((entry, index) => [entry.key, index]));
  const arranged = items
    .filter((item) => position.has(firstKey(item)))
    .sort((left, right) => {
      const first = position.get(firstKey(left)) - position.get(firstKey(right));
      if (first !== 0 || groups.length < 2) {
        return first;
      }
      return (sort.by === 'g1' ? sign : 1) * compare(left.keys[1], right.keys[1]);
    });
  return { items: arranged, trimmed: ranked.length > kept.length };
}

// ---------------------------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------------------------

/**
 * Whole days from a date or date and time to today on the run's `clock` (makeClock), counted
 * on the person's calendar (Days Waiting, a column shown as age).
 */
export function daysSince(value, clock) {
  if (!value) {
    return null;
  }
  const calendar = toClock(clock);
  const start = calendarDay(value, isIsoDate(String(value)) ? 'date' : 'datetime', calendar);
  return start ? Math.round((calendar.today - start) / 86400000) : null;
}

/**
 * A value as a person reads it, by field type: numbers and money in the locale, dates in the
 * medium style, date and time in the person's time zone. `options` gives `locale`, `currency`,
 * `timeZone`, `yes` and `no`.
 */
export function formatValue(value, type, options = {}) {
  if (value === null || value === undefined || value === '') {
    return '';
  }
  const locale = options.locale || undefined;
  try {
    if (type === 'currency') {
      return new Intl.NumberFormat(locale, {
        style: 'currency',
        currency: options.currency || 'USD'
      }).format(value);
    }
    if (type === 'percent') {
      return new Intl.NumberFormat(locale, { maximumFractionDigits: 2 }).format(value) + '%';
    }
    if (NUMBER_TYPES.has(type)) {
      return new Intl.NumberFormat(locale, { maximumFractionDigits: 2 }).format(value);
    }
    if (type === 'date') {
      return formatDay(String(value).slice(0, 10), locale);
    }
    if (type === 'datetime') {
      return new Intl.DateTimeFormat(locale, {
        dateStyle: 'medium',
        timeStyle: 'short',
        ...(options.timeZone ? { timeZone: options.timeZone } : {})
      }).format(new Date(value));
    }
  } catch {
    return String(value);
  }
  if (type === 'boolean') {
    return value === true ? options.yes || 'true' : options.no || 'false';
  }
  return String(value);
}

/**
 * A list report's rows for the table and for CSV: `{ headers, rows }`, each row
 * `{ key, id, cells: [{ key, text, raw }] }`. Related totals follow the columns.
 */
export function tableRows(report, result, options = {}, clock) {
  const calendar = toClock(clock);
  const headers = [
    ...report.columns.map((column, index) => ({
      key: `c${index}`,
      label: column.label,
      type: column.show === 'age' ? 'integer' : column.type
    })),
    ...report.summaries.map((entry, index) => ({
      key: `s${index}`,
      label: entry.label,
      type: entry.type
    }))
  ];
  const summaries = asArray(result && result.summaries);
  const rows = asArray(result && result.rows).map((row, index) => {
    const raws = [
      ...report.columns.map((column) => {
        const value = valueAt(row, column.path);
        return column.show === 'age' ? daysSince(value, calendar) : value;
      }),
      ...report.summaries.map((entry, s) => {
        const value = (summaries[s] || {})[row.Id];
        return value === undefined || value === null ? (entry.fn === 'count' ? 0 : null) : value;
      })
    ];
    return {
      key: `row${index}`,
      id: row.Id,
      cells: raws.map((raw, c) => ({
        key: `row${index}c${c}`,
        raw: raw === undefined ? null : raw,
        text: formatValue(raw, headers[c].type, options)
      }))
    };
  });
  return { headers, rows };
}

/** A totals report's groups as a table: group columns, then total columns. */
export function groupTable(report, arranged, options = {}) {
  const headers = [
    ...report.groups.map((group, index) => ({
      key: `g${index}`,
      label: group.label,
      type: 'string'
    })),
    ...report.measures.map((measure, index) => ({
      key: `m${index}`,
      label: measure.label,
      type: measure.type
    }))
  ];
  const rows = arranged.items.map((item) => ({
    key: item.key,
    cells: [
      ...item.texts.map((text, index) => ({ key: `${item.key}g${index}`, raw: text, text })),
      ...item.values.map((value, index) => ({
        key: `${item.key}m${index}`,
        raw: value,
        text: formatValue(value, report.measures[index].type, options)
      }))
    ]
  }));
  return { headers, rows };
}

/** One CSV cell value from a table cell: numbers as numbers, everything else as shown. */
export function csvValue(cell) {
  return typeof cell.raw === 'number' ? cell.raw : cell.text;
}

// ---------------------------------------------------------------------------------------------
// Dashboards
// ---------------------------------------------------------------------------------------------

/** A dashboard read from storage or a template, with every part present and within limits. */
export function normalizeDashboard(raw) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const keys = new Set();
  return {
    version: VERSION,
    title: String(source.title || ''),
    description: String(source.description || ''),
    filters: asArray(source.filters)
      .filter(
        (filter) =>
          filter &&
          filter.key &&
          (filter.kind === 'date' || (filter.kind === 'record' && filter.object))
      )
      .slice(0, MAX_FILTERS)
      .map((filter) => ({
        key: String(filter.key),
        kind: filter.kind,
        label: String(filter.label || filter.key),
        ...(filter.object ? { object: String(filter.object) } : {})
      })),
    widgets: asArray(source.widgets)
      .filter((widget) => widget && widget.report)
      .slice(0, MAX_WIDGETS)
      .map((widget, index) => {
        let key = String(widget.key || `w${index + 1}`);
        while (keys.has(key)) {
          key = `${key}x`;
        }
        keys.add(key);
        const report = normalizeReport(widget.report);
        return {
          key,
          title: String(widget.title || report.title || ''),
          size: SIZES.includes(widget.size) ? widget.size : 'medium',
          report,
          bindings: normalizeBindings(widget.bindings)
        };
      })
  };
}

function normalizeBindings(raw) {
  const bindings = {};
  if (!raw || typeof raw !== 'object') {
    return bindings;
  }
  for (const [key, binding] of Object.entries(raw)) {
    if (binding && binding.field) {
      bindings[key] = {
        field: String(binding.field),
        ...(binding.type ? { type: binding.type === 'datetime' ? 'datetime' : 'date' } : {}),
        ...(binding.related && binding.related.object && binding.related.field
          ? {
              related: {
                object: String(binding.related.object),
                field: String(binding.related.field)
              }
            }
          : {})
      };
    }
  }
  return bindings;
}

/** A new dashboard, empty. */
export function newDashboard() {
  return normalizeDashboard({});
}

/** A copy of the list with the entry at the index replaced by update(entry). */
export function replaceAt(list, index, update) {
  return asArray(list).map((entry, position) => (position === index ? update(entry) : entry));
}

/** A key no widget of the dashboard uses yet. */
export function nextWidgetKey(dashboard) {
  const used = new Set(asArray(dashboard && dashboard.widgets).map((widget) => widget.key));
  let index = used.size + 1;
  while (used.has(`w${index}`)) {
    index++;
  }
  return `w${index}`;
}

/**
 * A widget's report with the dashboard's filter values applied: a date range replaces the
 * widget's own on the bound field; a record choice adds a condition on the bound field, or a
 * related-records condition when the binding goes through a related object (a gift's fund
 * through its allocations). Returns `{ report, unfiltered }`: the labels of the filters with a
 * value that this widget is not bound to, so the screen can say so.
 */
export function applyFilters(widget, filters, values = {}) {
  const report = clone(widget.report);
  const unfiltered = [];
  for (const filter of asArray(filters)) {
    const value = values[filter.key];
    const chosen = filter.kind === 'date' ? value && RANGES.includes(value.range) : !!value;
    if (!chosen) {
      continue;
    }
    const binding = (widget.bindings || {})[filter.key];
    if (!binding) {
      unfiltered.push(filter.label);
      continue;
    }
    if (filter.kind === 'date') {
      report.dateRange = normalizeRange({
        ...value,
        field: binding.field,
        type: binding.type || 'date'
      });
    } else if (binding.related) {
      if (report.related.length >= MAX_RELATED) {
        unfiltered.push(filter.label);
        continue;
      }
      report.related.push({
        object: binding.related.object,
        field: binding.related.field,
        label: filter.label,
        has: true,
        filter: {
          version: 1,
          conditions: [{ id: 1, field: binding.field, operator: 'equals', value }]
        }
      });
    } else {
      report.filter =
        withConditions(report.filter, [{ field: binding.field, operator: 'equals', value }]) || '';
    }
  }
  return { report, unfiltered };
}

/**
 * Every object a dashboard needs: each widget's object, related objects and related-total
 * objects, and each record filter's object.
 */
export function objectsUsed(dashboard) {
  const names = new Set();
  for (const filter of dashboard.filters) {
    if (filter.object) {
      names.add(filter.object);
    }
  }
  for (const widget of dashboard.widgets) {
    for (const name of reportObjects(widget.report)) {
      names.add(name);
    }
  }
  return names;
}

function reportObjects(report) {
  return [
    report.object,
    ...report.related.map((entry) => entry.object),
    ...report.summaries.map((entry) => entry.object)
  ];
}

/**
 * The shipped templates this org can show: a template whose `requires` objects are not all
 * offered is left out (its module is not installed, or the person cannot read it), and within a
 * kept template each widget and record filter whose objects are not offered is dropped.
 */
export function availableTemplates(templates, offered) {
  const has = (name) => offered.has(name);
  return asArray(templates)
    .filter((template) => template && asArray(template.requires).every(has))
    .map((template) => {
      const dashboard = normalizeDashboard(template);
      dashboard.filters = dashboard.filters.filter(
        (filter) => !filter.object || has(filter.object)
      );
      dashboard.widgets = dashboard.widgets.filter((widget) =>
        reportObjects(widget.report).every(has)
      );
      return { key: String(template.key), dashboard };
    })
    .filter((template) => template.dashboard.widgets.length > 0);
}

/** A list with one entry moved, for Move Up and Move Down. */
export function moved(list, from, to) {
  const copy = [...asArray(list)];
  if (to < 0 || to >= copy.length || from === to) {
    return copy;
  }
  const [item] = copy.splice(from, 1);
  copy.splice(to, 0, item);
  return copy;
}
