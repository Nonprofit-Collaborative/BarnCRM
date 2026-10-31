import { LightningElement, wire } from 'lwc';
import listObjects from '@salesforce/apex/DataDictionaryController.listObjects';
import describeObject from '@salesforce/apex/DataDictionaryController.describeObject';
import getPlan from '@salesforce/apex/FieldUtilizationController.getPlan';
import countFields from '@salesforce/apex/FieldUtilizationController.countFields';
import { toCsv, fileName, format, messageFrom } from 'c/findCsv';

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
import YES from '@salesforce/label/c.Core_DataDictionary_Yes';
import NO from '@salesforce/label/c.Core_DataDictionary_No';
import COL_OBJECT from '@salesforce/label/c.Core_DataDictionary_ColObject';
import COL_OBJECT_API_NAME from '@salesforce/label/c.Core_DataDictionary_ColObjectApiName';
import COL_FIELD from '@salesforce/label/c.Core_DataDictionary_ColField';
import COL_API_NAME from '@salesforce/label/c.Core_DataDictionary_ColApiName';
import COL_TYPE from '@salesforce/label/c.Core_DataDictionary_ColType';
import COL_LENGTH from '@salesforce/label/c.Core_DataDictionary_ColLength';
import COL_PRECISION from '@salesforce/label/c.Core_DataDictionary_ColPrecision';
import COL_REQUIRED from '@salesforce/label/c.Core_DataDictionary_ColRequired';
import COL_UNIQUE from '@salesforce/label/c.Core_DataDictionary_ColUnique';
import COL_EXTERNAL_ID from '@salesforce/label/c.Core_DataDictionary_ColExternalId';
import COL_CUSTOM from '@salesforce/label/c.Core_DataDictionary_ColCustom';
import COL_PICKLIST_VALUES from '@salesforce/label/c.Core_DataDictionary_ColPicklistValues';
import COL_HELP_TEXT from '@salesforce/label/c.Core_DataDictionary_ColHelpText';
import COL_FORMULA from '@salesforce/label/c.Core_DataDictionary_ColFormula';
import COL_RELATED_TO from '@salesforce/label/c.Core_DataDictionary_ColRelatedTo';
import COL_FILL_RATE from '@salesforce/label/c.Core_DataDictionary_ColFillRate';

const PERCENT = { maximumFractionDigits: 1 };
const FILE_BASE = 'Data_Dictionary';

const isBlank = (value) => value === null || value === undefined;
const yesNo = (value) => (value ? YES : NO);

/** A fill rate as a CSV cell: one decimal and a percent sign, or empty when not counted. */
function fillRateText(share) {
  return isBlank(share) ? '' : `${Math.round(share * 1000) / 10}%`;
}

/** The table and CSV row for one described field. */
function toRow(objectDictionary, field, share) {
  return {
    key: `${objectDictionary.objectName}|${field.fieldName}`,
    objectLabel: objectDictionary.objectLabel,
    objectName: objectDictionary.objectName,
    fieldLabel: field.fieldLabel,
    fieldName: field.fieldName,
    dataType: field.dataType,
    length: isBlank(field.length) ? null : field.length,
    precision: field.precision || '',
    required: yesNo(field.required),
    isUnique: yesNo(field.isUnique),
    externalId: yesNo(field.externalId),
    isCustom: yesNo(field.isCustom),
    picklistValues: field.picklistValues || '',
    helpText: field.helpText || '',
    formula: field.formula || '',
    relatedTo: field.relatedTo || '',
    fillRate: isBlank(share) ? null : share
  };
}

/**
 * Fill rates by field API name, from Field Utilization's own counting: each field's filled and
 * record totals are summed across record types.
 */
function sharesFrom(countRows) {
  const sums = new Map();
  for (const row of countRows) {
    const sum = sums.get(row.fieldName) || { filled: 0, total: 0 };
    sum.filled += row.filled || 0;
    sum.total += row.total || 0;
    sums.set(row.fieldName, sum);
  }
  const shares = new Map();
  sums.forEach((sum, name) => {
    if (sum.total > 0) {
      shares.set(name, sum.filled / sum.total);
    }
  });
  return shares;
}

const TABLE_COLUMNS = [
  { label: COL_OBJECT, fieldName: 'objectLabel', initialWidth: 160 },
  { label: COL_FIELD, fieldName: 'fieldLabel', initialWidth: 200 },
  { label: COL_API_NAME, fieldName: 'fieldName', initialWidth: 200 },
  { label: COL_TYPE, fieldName: 'dataType', initialWidth: 120 },
  { label: COL_LENGTH, fieldName: 'length', type: 'number', initialWidth: 90 },
  { label: COL_PRECISION, fieldName: 'precision', initialWidth: 100 },
  { label: COL_REQUIRED, fieldName: 'required', initialWidth: 90 },
  { label: COL_UNIQUE, fieldName: 'isUnique', initialWidth: 90 },
  { label: COL_EXTERNAL_ID, fieldName: 'externalId', initialWidth: 110 },
  { label: COL_CUSTOM, fieldName: 'isCustom', initialWidth: 90 },
  { label: COL_PICKLIST_VALUES, fieldName: 'picklistValues', wrapText: true, initialWidth: 260 },
  { label: COL_HELP_TEXT, fieldName: 'helpText', wrapText: true, initialWidth: 260 },
  { label: COL_FORMULA, fieldName: 'formula', wrapText: true, initialWidth: 260 },
  { label: COL_RELATED_TO, fieldName: 'relatedTo', initialWidth: 160 }
];

const FILL_RATE_COLUMN = {
  label: COL_FILL_RATE,
  fieldName: 'fillRate',
  type: 'percent',
  typeAttributes: PERCENT,
  initialWidth: 100
};

/** The CSV's columns: the table's, with the object's API name and the fill rate as text. */
function csvColumns(withFillRates) {
  const columns = [
    { label: COL_OBJECT, path: 'objectLabel' },
    { label: COL_OBJECT_API_NAME, path: 'objectName' },
    ...TABLE_COLUMNS.slice(1).map((column) => ({ label: column.label, path: column.fieldName }))
  ];
  if (withFillRates) {
    columns.push({ label: COL_FILL_RATE, path: 'fillRateText' });
  }
  return columns;
}

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
      for (const objectName of names) {
        // One call at a time, so the server never runs two.
        // eslint-disable-next-line no-await-in-loop
        const described = await describeObject({ objectName });
        if (run !== this.run) {
          return;
        }
        this.done += 1;
        this.rows = [...this.rows, ...described.fields.map((field) => toRow(described, field))];
        if (withFillRates) {
          // eslint-disable-next-line no-await-in-loop
          await this.addFillRates(run, described);
          if (run !== this.run) {
            return;
          }
        }
      }
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

  /** Fills one object's rows from Field Utilization's plan and counts, within its limits. */
  async addFillRates(run, described) {
    this.fillingLabel = described.objectLabel;
    try {
      const plan = await getPlan({ objectName: described.objectName });
      if (run !== this.run) {
        return;
      }
      if (plan.tooLarge) {
        this.skipped = [...this.skipped, described.objectLabel];
        return;
      }
      const names = (plan.fields || []).map((field) => field.fieldName);
      const size = plan.chunkSize || names.length || 1;
      const counted = [];
      for (let start = 0; start < names.length; start += size) {
        // eslint-disable-next-line no-await-in-loop
        const chunk = await countFields({
          objectName: described.objectName,
          fieldNames: names.slice(start, start + size)
        });
        if (run !== this.run) {
          return;
        }
        counted.push(...(chunk.rows || []));
      }
      const shares = sharesFrom(counted);
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
    const rows = this.rows.map((row) => ({ ...row, fillRateText: fillRateText(row.fillRate) }));
    const link = document.createElement('a');
    link.href = URL.createObjectURL(
      new Blob([toCsv(csvColumns(this.builtWithFillRates), rows)], {
        type: 'text/csv;charset=utf-8'
      })
    );
    link.download = fileName(FILE_BASE);
    link.click();
    URL.revokeObjectURL(link.href);
    this.noticeMessage = format(DOWNLOADED, String(rows.length));
  }
}
