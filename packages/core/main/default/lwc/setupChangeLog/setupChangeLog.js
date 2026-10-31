import { LightningElement } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getSummary from '@salesforce/apex/SetupChangeController.getSummary';
import getChanges from '@salesforce/apex/SetupChangeController.getChanges';
import copyNow from '@salesforce/apex/SetupChangeController.copyNow';
import { toCsv, fileName, messageFrom, zonedDateTime } from 'c/findCsv';
import {
  tableColumns,
  csvColumns,
  csvRows,
  keptText,
  copyText,
  sectionOptions,
  filterArgs,
  datesReversed,
  fill,
  countText
} from './setupChangeModel';

import TITLE from '@salesforce/label/c.Core_SetupChanges_Title';
import INTRO from '@salesforce/label/c.Core_SetupChanges_Intro';
import KEPT from '@salesforce/label/c.Core_SetupChanges_Kept';
import NOTHING_KEPT from '@salesforce/label/c.Core_SetupChanges_NothingKept';
import SCHEDULED from '@salesforce/label/c.Core_SetupChanges_Scheduled';
import NOT_SCHEDULED from '@salesforce/label/c.Core_SetupChanges_NotScheduled';
import COPY_RUNNING from '@salesforce/label/c.Core_SetupChanges_CopyRunning';
import COPY_NOW from '@salesforce/label/c.Core_SetupChanges_CopyNow';
import COPY_STARTED from '@salesforce/label/c.Core_SetupChanges_CopyStarted';
import REFRESH from '@salesforce/label/c.Core_SetupChanges_Refresh';
import FROM_DATE from '@salesforce/label/c.Core_SetupChanges_From';
import TO_DATE from '@salesforce/label/c.Core_SetupChanges_To';
import SECTION from '@salesforce/label/c.Core_SetupChanges_Section';
import ALL_SECTIONS from '@salesforce/label/c.Core_SetupChanges_AllSections';
import SEARCH from '@salesforce/label/c.Core_SetupChanges_Search';
import SEARCH_HELP from '@salesforce/label/c.Core_SetupChanges_SearchHelp';
import RUN_SEARCH from '@salesforce/label/c.Core_SetupChanges_RunSearch';
import DOWNLOAD from '@salesforce/label/c.Core_SetupChanges_Download';
import DOWNLOADED from '@salesforce/label/c.Core_SetupChanges_Downloaded';
import MORE from '@salesforce/label/c.Core_SetupChanges_More';
import SCAN_STOPPED from '@salesforce/label/c.Core_SetupChanges_ScanStopped';
import EMPTY from '@salesforce/label/c.Core_SetupChanges_Empty';
import DATES_REVERSED from '@salesforce/label/c.Core_SetupChanges_DatesReversed';
import CHANGED_AT from '@salesforce/label/c.Core_SetupChanges_ColChangedAt';
import CHANGED_BY from '@salesforce/label/c.Core_SetupChanges_ColChangedBy';
import LOGGED_IN_AS from '@salesforce/label/c.Core_SetupChanges_ColLoggedInAs';
import SECTION_COL from '@salesforce/label/c.Core_SetupChanges_ColSection';
import ACTION_COL from '@salesforce/label/c.Core_SetupChanges_ColAction';
import WHAT_CHANGED from '@salesforce/label/c.Core_SetupChanges_ColWhatChanged';

const FILE_BASE = 'Setup_Changes';
const COLUMN_LABELS = {
  changedAt: CHANGED_AT,
  changedBy: CHANGED_BY,
  loggedInAs: LOGGED_IN_AS,
  section: SECTION_COL,
  action: ACTION_COL,
  whatChanged: WHAT_CHANGED
};

/**
 * The Setup Changes section of Org Optimizer (C-56, admin guide setup-changes.md): the kept copy
 * of the Setup Audit Trail with filters, a CSV download and Copy New Changes Now. Read only
 * toward Setup; the controller checks Manage BarnCRM Settings on every call.
 */
export default class SetupChangeLog extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    copyNow: COPY_NOW,
    refresh: REFRESH,
    fromDate: FROM_DATE,
    toDate: TO_DATE,
    section: SECTION,
    search: SEARCH,
    searchHelp: SEARCH_HELP,
    runSearch: RUN_SEARCH,
    download: DOWNLOAD,
    empty: EMPTY
  };

  columns = tableColumns(COLUMN_LABELS);
  summary;
  rows = [];
  more = false;
  scanStopped = false;
  scanCap = 0;
  filters = { fromDate: '', toDate: '', section: '', search: '' };
  loading = false;
  copying = false;
  downloading = false;
  searched = false;
  errorMessage;
  noticeMessage;

  connectedCallback() {
    this.load();
  }

  get keptLine() {
    return this.summary
      ? keptText(this.summary, { kept: KEPT, nothingKept: NOTHING_KEPT }, LOCALE, TIME_ZONE)
      : '';
  }

  get copyLine() {
    return copyText(this.summary, {
      copyRunning: COPY_RUNNING,
      scheduled: SCHEDULED,
      notScheduled: NOT_SCHEDULED
    });
  }

  get sectionChoices() {
    return sectionOptions(this.summary && this.summary.sections, ALL_SECTIONS);
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return this.searched && !this.loading && !this.hasRows && !this.errorMessage;
  }

  get moreText() {
    if (!this.more || !this.summary) {
      return '';
    }
    return fill(
      MORE,
      countText(this.summary.pageRows, LOCALE),
      countText(this.summary.exportRows, LOCALE)
    );
  }

  get scanStoppedText() {
    return this.scanStopped ? fill(SCAN_STOPPED, countText(this.scanCap, LOCALE)) : '';
  }

  get busy() {
    return this.loading || this.copying || this.downloading;
  }

  get downloadDisabled() {
    return this.busy || !this.hasRows;
  }

  async load() {
    this.loading = true;
    this.errorMessage = undefined;
    try {
      this.summary = await getSummary();
      await this.search();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  async search() {
    if (datesReversed(this.filters)) {
      this.errorMessage = DATES_REVERSED;
      this.rows = [];
      return;
    }
    const pageRows = (this.summary && this.summary.pageRows) || 200;
    const result = await getChanges(filterArgs(this.filters, pageRows));
    this.rows = (result && result.rows) || [];
    this.more = Boolean(result && result.more);
    this.scanStopped = Boolean(result && result.scanStopped);
    this.scanCap = (result && result.scanCap) || 0;
    this.searched = true;
  }

  handleFilter(event) {
    const name = event.target.dataset.filter;
    this.filters = { ...this.filters, [name]: event.detail.value };
  }

  handleSearchKey(event) {
    if (event.key === 'Enter') {
      this.handleSearch();
    }
  }

  async handleSearch() {
    this.loading = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      await this.search();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  handleRefresh() {
    this.noticeMessage = undefined;
    this.load();
  }

  async handleCopyNow() {
    this.copying = true;
    this.errorMessage = undefined;
    try {
      const result = await copyNow();
      this.noticeMessage = result && result.started ? COPY_STARTED : COPY_RUNNING;
      this.summary = await getSummary();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.copying = false;
    }
  }

  async handleDownload() {
    if (datesReversed(this.filters)) {
      this.errorMessage = DATES_REVERSED;
      return;
    }
    this.downloading = true;
    this.errorMessage = undefined;
    try {
      const exportRows = (this.summary && this.summary.exportRows) || 5000;
      const result = await getChanges(filterArgs(this.filters, exportRows));
      const rows = csvRows(result && result.rows, (value) => zonedDateTime(value, TIME_ZONE));
      const link = document.createElement('a');
      link.href = URL.createObjectURL(
        new Blob([toCsv(csvColumns(COLUMN_LABELS), rows)], { type: 'text/csv;charset=utf-8' })
      );
      link.download = fileName(FILE_BASE);
      link.click();
      URL.revokeObjectURL(link.href);
      this.noticeMessage = fill(DOWNLOADED, countText(rows.length, LOCALE));
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.downloading = false;
    }
  }
}
