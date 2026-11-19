import { LightningElement, api } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import runReport from '@salesforce/apex/ReportingQueryService.run';
import readPage from '@salesforce/apex/ReportingQueryService.page';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { format, recordHref } from 'c/barnFormat';
import { downloadCsv, messageFrom, zonedParts } from 'c/findCsv';
import {
  EXPORT_PAGE_SIZE,
  MAX_EXPORT_ROWS,
  MAX_SCAN_ROWS,
  PAGE_SIZE,
  arrangeGroups,
  csvValue,
  formatValue,
  groupTable,
  isTotals,
  makeClock,
  newScan,
  normalizeReport,
  pageRequest,
  reportProblems,
  runRequest,
  scanPage,
  scanResult,
  tableRows
} from 'c/reportingModel';
import { chartModel } from 'c/reportingChartModel';

const ROWS_STEP = 50;

// Scans run one at a time across every view on the page, so a dashboard's large widgets never
// read pages in parallel; aggregate runs are not queued.
let scanQueue = Promise.resolve();
function oneScanAtATime(task) {
  const run = scanQueue.then(task, task);
  scanQueue = run.catch(() => undefined);
  return run;
}

/** The person's calendar for one run: their Salesforce time zone and locale, now. */
function personClock() {
  return makeClock({ now: new Date(), timeZone: TIME_ZONE, locale: LOCALE, zonedParts });
}

/**
 * Runs one Advanced Reporting report as the person and shows it: a list as a table, totals as a
 * chart (with Show Table beside it), a group table or a metric tile. A totals report too large
 * for one aggregate query is read in pages and totalled here, with progress and Stop. Used by
 * the report builder for its preview and by each dashboard widget.
 */
export default class ReportingView extends LightningElement {
  /** Turns off the Export CSV button (Salesforce's Export Reports permission decides). */
  @api canExport = false;

  /** A widget's title, shown above the result; empty in the builder, whose page has one. */
  @api heading = '';

  /** The dashboard filters with a value this widget is not bound to, by label. */
  @api unfiltered = [];

  helpReady = isHelpLoaded(['Reporting', 'Core']);
  loading = false;
  error = '';
  result;
  /** The result's groups in order, worked out once when the result is set (setResult). */
  arranged = null;
  /** The calendar the current result was run on, reused for its pages and its export. */
  clock;
  scanned = 0;
  stopRequested = false;
  stoppedAt = null;
  tableShown = false;
  rowsShown = ROWS_STEP;
  exporting = false;
  exportStatus = '';
  _report;
  token = 0;

  /** The report to run (a saved definition, a template widget's, or the builder's draft). */
  @api
  get report() {
    return this._report;
  }
  set report(value) {
    this._report = normalizeReport(value);
    if (this.isConnected) {
      this.refresh();
    }
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(['Reporting', 'Core']).then(() => {
        this.helpReady = true;
        // Group names use words from the help catalog (Blank, Yes, No).
        this.setResult(this.result);
      });
    }
    this.refresh();
  }

  /** Sets the result and arranges its groups once, rather than on every read. */
  setResult(result) {
    this.result = result;
    this.arranged =
      result && this.totals ? arrangeGroups(this._report, result, this.words, LOCALE) : null;
  }

  disconnectedCallback() {
    this.token++;
  }

  /** Runs the report again (Run, a dashboard's filter change or Refresh). */
  @api
  refresh() {
    this.token++;
    this.setResult(undefined);
    this.error = '';
    this.stoppedAt = null;
    this.rowsShown = ROWS_STEP;
    if (!this._report || this.problems.length) {
      this.loading = false;
      return Promise.resolve();
    }
    return this.load(this.token);
  }

  async load(token) {
    this.loading = true;
    this.scanned = 0;
    this.stopRequested = false;
    this.clock = personClock();
    try {
      const result = await runReport({
        requestJson: JSON.stringify(runRequest(this._report, this.clock))
      });
      if (token !== this.token) {
        return;
      }
      if (result && result.scan) {
        await oneScanAtATime(() => this.scan(token));
      } else {
        this.setResult(result || {});
      }
    } catch (error) {
      if (token === this.token) {
        this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
      }
    } finally {
      if (token === this.token) {
        this.loading = false;
      }
    }
  }

  /**
   * Reads every record in pages of 5,000 and totals them here (ADR-0231, large volumes), on the
   * run's calendar. Waits its turn behind any other view's scan (oneScanAtATime).
   */
  async scan(token) {
    if (token !== this.token) {
      return;
    }
    const scan = newScan();
    const clock = this.clock;
    const requestJson = JSON.stringify(pageRequest(this._report, clock));
    let afterId = null;
    for (;;) {
      // eslint-disable-next-line no-await-in-loop
      const page = await readPage({ requestJson, afterId, pageSize: PAGE_SIZE, forExport: false });
      if (token !== this.token) {
        return;
      }
      scanPage(this._report, scan, page.rows, clock);
      this.scanned = scan.rows;
      if (page.done || this.stopRequested || scan.rows >= MAX_SCAN_ROWS) {
        break;
      }
      afterId = page.lastId;
    }
    this.stoppedAt = this.stopRequested ? scan.rows : null;
    this.setResult(scanResult(this._report, scan));
  }

  handleStop() {
    this.stopRequested = true;
  }

  get problems() {
    return this._report ? reportProblems(this._report) : [];
  }

  get problemText() {
    const problem = this.problems[0];
    if (!problem) {
      return '';
    }
    const texts = {
      object: helpText('Reporting', 'Reporting_Problem_Object'),
      columns: helpText('Reporting', 'Reporting_Problem_Columns'),
      measure: helpText('Reporting', 'Reporting_Problem_Measure'),
      chart: helpText('Reporting', 'Reporting_Problem_Chart'),
      metric: helpText('Reporting', 'Reporting_Problem_Metric')
    };
    return texts[problem];
  }

  get options() {
    return {
      locale: LOCALE,
      currency: CURRENCY,
      timeZone: TIME_ZONE,
      yes: helpText('Reporting', 'Reporting_Yes'),
      no: helpText('Reporting', 'Reporting_No')
    };
  }

  get words() {
    return {
      blank: helpText('Reporting', 'Reporting_Blank'),
      yes: helpText('Reporting', 'Reporting_Yes'),
      no: helpText('Reporting', 'Reporting_No'),
      other: helpText('Reporting', 'Reporting_Other'),
      picklists: this._report ? this._report.groups.map((group) => group.picklist) : []
    };
  }

  get totals() {
    return isTotals(this._report);
  }

  get isMetric() {
    return !!this.result && this.totals && this._report.view.type === 'metric';
  }

  get metricValue() {
    const arranged = this.arranged;
    const first = arranged && arranged.items[0];
    return first && first.values[0] !== null ? first.values[0] : 0;
  }

  get metricLabel() {
    return this._report.measures[0].label;
  }

  get metricStyle() {
    const type = this._report.measures[0].type;
    return type === 'currency' ? 'currency' : 'decimal';
  }

  get currencyCode() {
    return CURRENCY;
  }

  get isChart() {
    return (
      !!this.result &&
      this.totals &&
      ['bar', 'column', 'line', 'donut'].includes(this._report.view.type)
    );
  }

  get chart() {
    const report = this._report;
    const options = this.options;
    return chartModel(
      report,
      this.arranged,
      (value, measureIndex) =>
        formatValue(value, (report.measures[measureIndex] || report.measures[0]).type, options),
      this.words
    );
  }

  get chartSummary() {
    const chart = this.chart;
    return format(
      helpText('Reporting', 'Reporting_ChartSummary'),
      this.heading || this._report.title || this._report.measures[0].label,
      chart.categories,
      chart.largest
    );
  }

  get showChart() {
    return this.isChart && !this.tableShown;
  }

  get showTable() {
    return !!this.result && !this.isMetric && (!this.isChart || this.tableShown);
  }

  get toggleLabel() {
    return this.tableShown
      ? helpText('Reporting', 'Reporting_ShowChart')
      : helpText('Reporting', 'Reporting_ShowTable');
  }

  handleToggle() {
    this.tableShown = !this.tableShown;
  }

  get table() {
    if (!this.result) {
      return { headers: [], rows: [] };
    }
    if (this.totals) {
      return groupTable(this._report, this.arranged, this.options);
    }
    const table = tableRows(this._report, this.result, this.options, this.clock);
    return {
      headers: table.headers,
      rows: table.rows.map((row) => ({
        ...row,
        cells: row.cells.map((cell, index) => ({
          ...cell,
          href: index === 0 && row.id ? recordHref(row.id) : null
        }))
      }))
    };
  }

  get shownRows() {
    const rows = this.table.rows;
    const headers = this.table.headers;
    return rows.slice(0, this.rowsShown).map((row) => ({
      ...row,
      cells: row.cells.map((cell, index) => ({ ...cell, label: headers[index].label }))
    }));
  }

  get hasRows() {
    return this.table.rows.length > 0;
  }

  get canShowMore() {
    return this.table.rows.length > this.rowsShown;
  }

  get rowsNote() {
    const total = this.table.rows.length;
    return total > ROWS_STEP
      ? format(helpText('Reporting', 'Reporting_RowsShown'), Math.min(this.rowsShown, total), total)
      : '';
  }

  handleShowMore() {
    this.rowsShown += ROWS_STEP;
  }

  get notes() {
    const notes = [];
    const result = this.result || {};
    const arranged = this.arranged;
    if (arranged && arranged.trimmed) {
      notes.push(format(helpText('Reporting', 'Reporting_Trimmed'), this._report.limit));
    }
    if (result.more) {
      notes.push(helpText('Reporting', 'Reporting_MoreGroups'));
    }
    if (result.partial) {
      notes.push(
        format(helpText('Reporting', 'Reporting_Partial'), MAX_SCAN_ROWS.toLocaleString(LOCALE))
      );
    }
    if (this.stoppedAt !== null) {
      notes.push(
        format(helpText('Reporting', 'Reporting_Stopped'), this.stoppedAt.toLocaleString(LOCALE))
      );
    }
    if (this.isChart && this.chart.cut) {
      notes.push(helpText('Reporting', 'Reporting_CutCategories'));
    }
    return notes.map((text, index) => ({ key: `n${index}`, text }));
  }

  get unfilteredText() {
    const labels = this.unfiltered || [];
    return labels.length
      ? format(helpText('Reporting', 'Reporting_NotFiltered'), labels.join(', '))
      : '';
  }

  get scanText() {
    return this.scanned
      ? format(helpText('Reporting', 'Reporting_Scanning'), this.scanned.toLocaleString(LOCALE))
      : '';
  }

  get showExport() {
    return this.canExport && !!this.result && !this.isMetric;
  }

  get exportLabel() {
    return helpText('Reporting', 'Reporting_Export');
  }

  /**
   * CSV of every record (a list, read again in pages of 2,000, at most 100,000 rows) or of the
   * groups shown (totals). The server checks Export Reports on every page.
   */
  async handleExport() {
    if (this.exporting) {
      return;
    }
    this.exporting = true;
    this.exportStatus = '';
    const base = this._report.title || this._report.object;
    let capped = false;
    try {
      let table;
      if (this.totals) {
        table = this.table;
      } else {
        table = { headers: this.table.headers, rows: [] };
        const clock = this.clock;
        const requestJson = JSON.stringify(pageRequest(this._report, clock));
        let afterId = null;
        for (;;) {
          // eslint-disable-next-line no-await-in-loop
          const page = await readPage({
            requestJson,
            afterId,
            pageSize: EXPORT_PAGE_SIZE,
            forExport: true
          });
          table.rows.push(...tableRows(this._report, page, this.options, clock).rows);
          this.exportStatus = format(
            helpText('Reporting', 'Reporting_Exporting'),
            table.rows.length.toLocaleString(LOCALE)
          );
          if (page.done) {
            break;
          }
          if (table.rows.length >= MAX_EXPORT_ROWS) {
            capped = true;
            table.rows.length = MAX_EXPORT_ROWS;
            break;
          }
          afterId = page.lastId;
        }
      }
      const columns = table.headers.map((header, index) => ({
        label: header.label,
        path: `c${index}`
      }));
      const rows = table.rows.map((row) => {
        const flat = {};
        row.cells.forEach((cell, index) => {
          flat[`c${index}`] = csvValue(cell);
        });
        return flat;
      });
      downloadCsv(base, columns, rows);
      this.exportStatus = format(
        helpText('Reporting', capped ? 'Reporting_ExportCapped' : 'Reporting_Exported'),
        rows.length.toLocaleString(LOCALE)
      );
    } catch (error) {
      this.exportStatus = '';
      this.error = messageFrom(error, helpText('Reporting', 'Reporting_Error_Generic'));
    } finally {
      this.exporting = false;
    }
  }

  get labels() {
    return {
      loading: helpText('Reporting', 'Reporting_Loading'),
      stop: helpText('Reporting', 'Reporting_Stop'),
      noRows: helpText('Reporting', 'Reporting_NoRows'),
      showMore: helpText('Reporting', 'Reporting_ShowMore')
    };
  }
}
