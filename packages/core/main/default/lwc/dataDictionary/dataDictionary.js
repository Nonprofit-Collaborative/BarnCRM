import { LightningElement, wire } from 'lwc';
import listObjects from '@salesforce/apex/DataDictionaryController.listObjects';
import describeObject from '@salesforce/apex/DataDictionaryController.describeObject';
import {
  readFillRates,
  toRow,
  dictionaryCsv,
  TABLE_COLUMNS,
  FILL_RATE_COLUMN
} from 'c/dictionaryKit';
import { fileName, format, messageFrom, saveBlob } from 'c/findCsv';

import TITLE from '@salesforce/label/c.Core_DataDictionary_PageTitle';
import INTRO from '@salesforce/label/c.Core_DataDictionary_PageIntro';
import CHOOSE_LABEL from '@salesforce/label/c.Core_DataDictionary_ChooseLabel';
import SOURCE_LABEL from '@salesforce/label/c.Core_DataDictionary_SourceLabel';
import SELECTED_LABEL from '@salesforce/label/c.Core_DataDictionary_SelectedLabel';
import INCLUDE_FILL_RATES from '@salesforce/label/c.Core_DataDictionary_IncludeFillRates';
import INCLUDE_FILL_RATES_HELP from '@salesforce/label/c.Core_DataDictionary_IncludeFillRatesHelp';
import BUILD from '@salesforce/label/c.Core_DataDictionary_Build';
import DOWNLOAD from '@salesforce/label/c.Core_DataDictionary_Download';
import DOWNLOADED from '@salesforce/label/c.Core_DataDictionary_Downloaded';
import PROGRESS from '@salesforce/label/c.Core_DataDictionary_Progress';
import FILL_PROGRESS from '@salesforce/label/c.Core_DataDictionary_FillProgress';
import NOT_COUNTED from '@salesforce/label/c.Core_DataDictionary_NotCounted';
import EMPTY from '@salesforce/label/c.Core_DataDictionary_Empty';
const FILE_BASE = 'Data_Dictionary';

/**
 * The Data Dictionary section of Org Optimizer (plan Section 6.1.1 item 13, D-154, admin guide
 * data-dictionary.md): choose kinds of record, and the page describes them one at a time, then
 * (when asked) adds fill rates from Field Utilization's own counting, one call at a time. The
 * rows can be downloaded as CSV. Describe only; the controllers check Manage BarnCRM Settings.
 */
export default class DataDictionary extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    chooseLabel: CHOOSE_LABEL,
    sourceLabel: SOURCE_LABEL,
    selectedLabel: SELECTED_LABEL,
    includeFillRates: INCLUDE_FILL_RATES,
    includeFillRatesHelp: INCLUDE_FILL_RATES_HELP,
    build: BUILD,
    download: DOWNLOAD,
    empty: EMPTY
  };

  objectOptions = [];
  selected = [];
  includeFillRates = false;
  rows = [];
  skipped = [];
  building = false;
  done = 0;
  total = 0;
  fillingLabel;
  builtWithFillRates = false;
  errorMessage;
  noticeMessage;
  run = 0;
  chosenDefaults = false;

  @wire(listObjects)
  wiredObjects({ data, error }) {
    if (data) {
      this.objectOptions = data.map((option) => ({
        value: option.value,
        label: `${option.label} (${option.value})`
      }));
      if (!this.chosenDefaults) {
        this.chosenDefaults = true;
        this.selected = data.filter((option) => option.isDefault).map((option) => option.value);
      }
    } else if (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  get columns() {
    return this.builtWithFillRates ? [...TABLE_COLUMNS, FILL_RATE_COLUMN] : TABLE_COLUMNS;
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return !this.hasRows && !this.building;
  }

  get buildDisabled() {
    return this.building || this.selected.length === 0;
  }

  get downloadDisabled() {
    return this.building || !this.hasRows;
  }

  get progressText() {
    if (!this.building) {
      return undefined;
    }
    return this.fillingLabel
      ? format(FILL_PROGRESS, this.fillingLabel)
      : format(PROGRESS, String(this.done), String(this.total));
  }

  get progressValue() {
    return this.total ? Math.round((this.done / this.total) * 100) : 0;
  }

  get notCountedMessage() {
    return this.skipped.length ? format(NOT_COUNTED, this.skipped.join(', ')) : undefined;
  }

  handleSelect(event) {
    this.selected = event.detail.value;
  }

  handleFillRates(event) {
    this.includeFillRates = event.target.checked;
  }

  async handleBuild() {
    const run = ++this.run;
    const names = [...this.selected];
    const withFillRates = this.includeFillRates;
    this.rows = [];
    this.skipped = [];
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    this.builtWithFillRates = withFillRates;
    this.building = true;
    this.done = 0;
    this.total = names.length;
    try {
      await this.describeNext(run, names, 0, withFillRates);
    } catch (error) {
      if (run === this.run) {
        this.errorMessage = messageFrom(error);
      }
    } finally {
      if (run === this.run) {
        this.building = false;
        this.fillingLabel = undefined;
      }
    }
  }

  /** Describes one object, then the next: one call at a time, so the server never runs two. */
  async describeNext(run, names, index, withFillRates) {
    if (index >= names.length || run !== this.run) {
      return;
    }
    const described = await describeObject({ objectName: names[index] });
    if (run !== this.run) {
      return;
    }
    this.done += 1;
    this.rows = [...this.rows, ...described.fields.map((field) => toRow(described, field))];
    if (withFillRates) {
      await this.addFillRates(run, described);
    }
    await this.describeNext(run, names, index + 1, withFillRates);
  }

  /** Fills one object's rows from Field Utilization's plan and counts, within its limits. */
  async addFillRates(run, described) {
    this.fillingLabel = described.objectLabel;
    try {
      const shares = await readFillRates(described.objectName, () => run === this.run);
      if (run !== this.run) {
        return;
      }
      if (!shares) {
        this.skipped = [...this.skipped, described.objectLabel];
        return;
      }
      this.rows = this.rows.map((row) => {
        const known = row.objectName === described.objectName && shares.has(row.fieldName);
        return known ? { ...row, fillRate: shares.get(row.fieldName) } : row;
      });
    } catch {
      // A count that fails leaves that object's fill rates blank and says so; the dictionary stays.
      this.skipped = [...this.skipped, described.objectLabel];
    }
  }

  handleDownload() {
    saveBlob(
      new Blob([dictionaryCsv(this.rows, this.builtWithFillRates)], {
        type: 'text/csv;charset=utf-8'
      }),
      fileName(FILE_BASE)
    );
    this.noticeMessage = format(DOWNLOADED, String(this.rows.length));
  }
}
