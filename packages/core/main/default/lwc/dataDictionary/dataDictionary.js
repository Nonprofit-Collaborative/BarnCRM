import { LightningElement, wire } from 'lwc';
import listObjects from '@salesforce/apex/DataDictionaryController.listObjects';
import describeObject from '@salesforce/apex/DataDictionaryController.describeObject';
import getAutomation from '@salesforce/apex/DataDictionaryController.getAutomation';
import {
  readFillRates,
  toRow,
  dictionaryCsv,
  toAutomationRow,
  automationCsv,
  AUTOMATION_COLUMNS,
  TABLE_COLUMNS,
  FILL_RATE_COLUMN
} from 'c/dictionaryKit';
import { fileName, format, messageFrom, saveBlob } from 'c/findCsv';
import WhereUsedModal from 'c/whereUsedModal';
import WHERE_USED from '@salesforce/label/c.Core_WhereUsed_Action';

import TITLE from '@salesforce/label/c.Core_DataDictionary_PageTitle';
import CHOOSE_LABEL from '@salesforce/label/c.Core_AccessCompare_KindsHeading';
import SOURCE_LABEL from '@salesforce/label/c.Core_Filter_AvailableValues';
import SELECTED_LABEL from '@salesforce/label/c.Core_DataDictionary_SelectedLabel';
import INCLUDE_FILL_RATES from '@salesforce/label/c.Core_DataDictionary_IncludeFillRates';
import BUILD from '@salesforce/label/c.Core_DataDictionary_Build';
import DOWNLOAD from '@salesforce/label/c.Core_AccessExplorer_Download';
import INCLUDE_AUTOMATION from '@salesforce/label/c.Core_DataDictionary_IncludeAutomation';
import AUTOMATION_TITLE from '@salesforce/label/c.Core_DataDictionary_AutomationTitle';
import DOWNLOAD_AUTOMATION from '@salesforce/label/c.Core_DataDictionary_DownloadAutomation';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
const FILE_BASE = 'Data_Dictionary';
const AUTOMATION_FILE_BASE = 'Automation_Inventory';
/** Each row's Where Used action (C-59); the table only, never the CSV. */
const WHERE_USED_COLUMN = {
  type: 'action',
  typeAttributes: { rowActions: [{ label: WHERE_USED, name: 'whereUsed' }] }
};

/**
 * The Data Dictionary section of Org Optimizer (plan Section 6.1.1 item 13, D-154, admin guide
 * data-dictionary.md): choose kinds of record, and the page describes them one at a time, then
 * (when asked) adds fill rates from Field Utilization's own counting, one call at a time. The
 * rows can be downloaded as CSV. Describe only; the controllers check Manage BarnCRM Settings.
 */
export default class DataDictionary extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Core', 'Core_DataDictionary_PageIntro');
    },
    chooseLabel: CHOOSE_LABEL,
    sourceLabel: SOURCE_LABEL,
    selectedLabel: SELECTED_LABEL,
    includeFillRates: INCLUDE_FILL_RATES,
    get includeFillRatesHelp() {
      return helpText('Core', 'Core_DataDictionary_IncludeFillRatesHelp');
    },
    build: BUILD,
    download: DOWNLOAD,
    get empty() {
      return helpText('Core', 'Core_DataDictionary_Empty');
    },
    includeAutomation: INCLUDE_AUTOMATION,
    get includeAutomationHelp() {
      return helpText('Core', 'Core_DataDictionary_IncludeAutomationHelp');
    },
    automationTitle: AUTOMATION_TITLE,
    get automationNote() {
      return helpText('Core', 'Core_DataDictionary_AutomationNote');
    },
    get automationEmpty() {
      return helpText('Core', 'Core_DataDictionary_AutomationEmpty');
    },
    downloadAutomation: DOWNLOAD_AUTOMATION
  };

  automationColumns = AUTOMATION_COLUMNS;
  includeAutomation = false;
  builtWithAutomation = false;
  automationRows = [];
  automationNotRead = [];
  automationTruncated = [];

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
    return this.builtWithFillRates
      ? [...TABLE_COLUMNS, FILL_RATE_COLUMN, WHERE_USED_COLUMN]
      : [...TABLE_COLUMNS, WHERE_USED_COLUMN];
  }

  /** A field row's Where Used action: which BarnCRM setup uses the field. */
  handleRowAction(event) {
    const { action, row } = event.detail;
    if (action.name !== 'whereUsed') {
      return;
    }
    WhereUsedModal.open({
      size: 'medium',
      objectName: row.objectName,
      objectLabel: row.objectLabel,
      fieldName: row.fieldName,
      fieldLabel: row.fieldLabel
    });
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
      ? format(helpText('Core', 'Core_DataDictionary_FillProgress'), this.fillingLabel)
      : format(
          helpText('Core', 'Core_DataDictionary_Progress'),
          String(this.done),
          String(this.total)
        );
  }

  get progressValue() {
    return this.total ? Math.round((this.done / this.total) * 100) : 0;
  }

  get showAutomation() {
    return this.builtWithAutomation && !this.building;
  }

  get hasAutomationRows() {
    return this.automationRows.length > 0;
  }

  get showAutomationEmpty() {
    return this.showAutomation && !this.hasAutomationRows;
  }

  get downloadAutomationDisabled() {
    return this.building || !this.hasAutomationRows;
  }

  get automationNotReadMessage() {
    return this.automationNotRead.length
      ? format(
          helpText('Core', 'Core_DataDictionary_AutomationNotRead'),
          this.automationNotRead.join(', ')
        )
      : undefined;
  }

  get automationTruncatedMessage() {
    return this.automationTruncated.length
      ? format(
          helpText('Core', 'Core_DataDictionary_AutomationTruncated'),
          this.automationTruncated.join(', ')
        )
      : undefined;
  }

  get notCountedMessage() {
    return this.skipped.length
      ? format(helpText('Core', 'Core_DataDictionary_NotCounted'), this.skipped.join(', '))
      : undefined;
  }

  handleSelect(event) {
    this.selected = event.detail.value;
  }

  handleFillRates(event) {
    this.includeFillRates = event.target.checked;
  }

  handleAutomation(event) {
    this.includeAutomation = event.target.checked;
  }

  async handleBuild() {
    const run = ++this.run;
    const names = [...this.selected];
    const withFillRates = this.includeFillRates;
    this.builtWithAutomation = this.includeAutomation;
    this.automationRows = [];
    this.automationNotRead = [];
    this.automationTruncated = [];
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
    if (this.builtWithAutomation) {
      await this.addAutomation(run, described);
    }
    await this.describeNext(run, names, index + 1, withFillRates);
  }

  /** Adds one object's triggers and flows; a read that fails is named and the dictionary stays. */
  async addAutomation(run, described) {
    try {
      const inventory = await getAutomation({ objectName: described.objectName });
      if (run !== this.run) {
        return;
      }
      this.automationRows = [...this.automationRows, ...inventory.rows.map(toAutomationRow)];
      if (inventory.triggersFailed || inventory.flowsFailed) {
        this.automationNotRead = [...this.automationNotRead, described.objectLabel];
      }
      if (inventory.truncated) {
        this.automationTruncated = [...this.automationTruncated, described.objectLabel];
      }
    } catch {
      this.automationNotRead = [...this.automationNotRead, described.objectLabel];
    }
  }

  handleDownloadAutomation() {
    saveBlob(
      new Blob([automationCsv(this.automationRows)], { type: 'text/csv;charset=utf-8' }),
      fileName(AUTOMATION_FILE_BASE)
    );
    this.noticeMessage = format(
      helpText('Core', 'Core_DataDictionary_DownloadedAutomation'),
      String(this.automationRows.length)
    );
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
    this.noticeMessage = format(
      helpText('Core', 'Core_DataDictionary_Downloaded'),
      String(this.rows.length)
    );
  }
}
