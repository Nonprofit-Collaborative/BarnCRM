import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { openInWorkspace } from 'c/workspaceTabs';
import ERROR_LOG_OBJECT from '@salesforce/schema/Error_Log__c';
import CONTEXT_FIELD from '@salesforce/schema/Error_Log__c.Context__c';
import SEVERITY_FIELD from '@salesforce/schema/Error_Log__c.Severity__c';
import TIMESTAMP_FIELD from '@salesforce/schema/Error_Log__c.Timestamp__c';
import OCCURRENCES_FIELD from '@salesforce/schema/Error_Log__c.Occurrences__c';
import OBJECT_NAME_FIELD from '@salesforce/schema/Error_Log__c.Object_Name__c';
import TECHNICAL_DETAIL_FIELD from '@salesforce/schema/Error_Log__c.Technical_Detail__c';
import { getRecords } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import getTile from '@salesforce/apex/ErrorLogController.getTile';
import acknowledge from '@salesforce/apex/ErrorLogController.acknowledge';
import Toast from 'lightning/toast';
import { bugReportText } from 'c/bugReportText';

import TITLE from '@salesforce/label/c.Core_ErrorLogTile_Title';
import NEW_COUNT from '@salesforce/label/c.Core_ErrorLogTile_NewCount';
import ACKNOWLEDGE from '@salesforce/label/c.Core_ErrorLogTile_Acknowledge';
import VIEW_ALL from '@salesforce/label/c.Core_ErrorLogTile_ViewAll';
import OPEN_ENTRY from '@salesforce/label/c.Core_ErrorLogTile_OpenEntry';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const ROW_COUNT = 5;

/**
 * What "Copy for Bug Report" reads (ADR-0093): the listed entries, as the user, through
 * Lightning Data Service. Technical Detail is optional, so someone who may not read it (staff)
 * still gets a report, without the detail.
 */
const BUG_REPORT_FIELDS = [
  CONTEXT_FIELD,
  SEVERITY_FIELD,
  TIMESTAMP_FIELD,
  OCCURRENCES_FIELD,
  OBJECT_NAME_FIELD
];

/** One field's value from a UI API record, by its schema import. */
function valueOf(record, field) {
  const cell = record.fields[field.fieldApiName];
  return cell ? cell.value : undefined;
}

/** A UI API record as the entry c/bugReportText turns into text. */
function bugReportEntry(record) {
  return {
    context: valueOf(record, CONTEXT_FIELD),
    severity: valueOf(record, SEVERITY_FIELD),
    occurredAt: valueOf(record, TIMESTAMP_FIELD),
    occurrences: valueOf(record, OCCURRENCES_FIELD),
    objectName: valueOf(record, OBJECT_NAME_FIELD),
    technicalDetail: valueOf(record, TECHNICAL_DETAIL_FIELD)
  };
}

/** The bug report's headings, from the Core help catalog (QA review Q10). */
function bugReportWords() {
  return {
    heading: helpText('Core', 'Core_ErrorLogTile_BugReport_Heading'),
    where: helpText('Core', 'Core_ErrorLogTile_BugReport_Where'),
    object: helpText('Core', 'Core_ErrorLogTile_BugReport_Object'),
    severity: helpText('Core', 'Core_ErrorLogTile_BugReport_Severity'),
    when: helpText('Core', 'Core_ErrorLogTile_BugReport_When'),
    times: helpText('Core', 'Core_ErrorLogTile_BugReport_Times'),
    codes: helpText('Core', 'Core_ErrorLogTile_BugReport_Codes'),
    stack: helpText('Core', 'Core_ErrorLogTile_BugReport_Stack'),
    none: helpText('Core', 'Core_ErrorLogTile_BugReport_None'),
    noDetail: helpText('Core', 'Core_ErrorLogTile_BugReport_NoDetail')
  };
}

export default class ErrorLogTile extends NavigationMixin(LightningElement) {
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
    newCount: NEW_COUNT,
    get empty() {
      return helpText('Core', 'Core_ErrorLogTile_Empty');
    },
    acknowledge: ACKNOWLEDGE,
    viewAll: VIEW_ALL,
    openEntry: OPEN_ENTRY,
    get readOnly() {
      return helpText('Core', 'Core_ErrorLogTile_ReadOnly');
    },
    get copyBugReport() {
      return helpText('Core', 'Core_ErrorLogTile_CopyBugReport');
    },
    get copyFailed() {
      return helpText('Core', 'Core_ErrorLogTile_CopyFailed');
    }
  };

  /** The report text, shown to copy by hand when the browser refuses the clipboard. */
  reportText;
  tile;
  errorMessage;
  busy = false;
  wiredTileResult;
  /** The getRecords request for the listed entries; undefined while none are listed. */
  bugReportQuery;
  /** The listed entries' bug report records, by record id. */
  bugReports = {};
  bugReportError;
  /** True once the read for the current listed entries has returned (data or error). */
  bugReportsRead = false;

  @wire(EnclosingTabId) enclosingTabId;

  @wire(getTile, { rowCount: ROW_COUNT })
  wiredTile(result) {
    this.wiredTileResult = result;
    if (result.data) {
      this.setTile(result.data);
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = bodyMessage(result.error, helpText('Core', 'Core_ErrorLog_ActionFailed'));
    }
  }

  @wire(getRecords, { records: '$bugReportQuery' })
  wiredBugReports({ data, error }) {
    if (data) {
      const byId = {};
      (data.results || []).forEach((item) => {
        if (item && item.result && item.result.id) {
          byId[item.result.id] = item.result;
        }
      });
      this.bugReports = byId;
      this.bugReportError = undefined;
      this.bugReportsRead = true;
    } else if (error) {
      this.bugReportError = error;
      this.bugReportsRead = true;
    }
  }

  /** Keeps the tile and asks for the listed entries' bug report fields when the list changes. */
  setTile(tile) {
    this.tile = tile;
    const ids = (tile && tile.recent ? tile.recent : []).map((entry) => entry.recordId);
    const current = this.bugReportQuery ? this.bugReportQuery[0].recordIds : [];
    if (ids.join() !== current.join()) {
      this.bugReportsRead = false;
      this.bugReportQuery = ids.length
        ? [{ recordIds: ids, fields: BUG_REPORT_FIELDS, optionalFields: [TECHNICAL_DETAIL_FIELD] }]
        : undefined;
    }
  }

  get newCount() {
    return this.tile ? this.tile.newCount : 0;
  }

  get newCountLabel() {
    const more = this.tile && this.tile.newCountCapped ? '+' : '';
    return this.labels.newCount.replace('{0}', `${this.newCount}${more}`);
  }

  /** Unread errors are a warning; none is a good state (the visual standard's vocabulary). */
  get newCountStatus() {
    return this.newCount > 0 ? 'warning' : 'success';
  }

  /**
   * Each entry with how many times it happened (repeats fold onto one entry, R-E7) and, for a
   * screen reader, button titles that name the entry they act on.
   */
  get entries() {
    const recent = this.tile && this.tile.recent ? this.tile.recent : [];
    return recent.map((entry) => {
      const row = entry.name || entry.context || '';
      return {
        ...entry,
        timesText:
          entry.occurrences > 1
            ? helpText('Core', 'Core_ErrorLogTile_Times', entry.occurrences)
            : '',
        openTitle: helpText('Core', 'Core_ErrorLogTile_RowAction', this.labels.openEntry, row),
        copyTitle: helpText('Core', 'Core_ErrorLogTile_RowAction', this.labels.copyBugReport, row),
        // Until the read is in, the entry is not known to be gone, so Copy waits.
        copyDisabled: !this.bugReportsRead && !this.bugReportError,
        acknowledgeTitle: helpText(
          'Core',
          'Core_ErrorLogTile_RowAction',
          this.labels.acknowledge,
          row
        )
      };
    });
  }

  get hasEntries() {
    return this.entries.length > 0;
  }

  get isEmpty() {
    return !!this.tile && !this.hasEntries;
  }

  get canUpdate() {
    return !!(this.tile && this.tile.canUpdate);
  }

  get isReadOnly() {
    return !!this.tile && !this.canUpdate;
  }

  get actionsDisabled() {
    return !this.canUpdate || this.busy;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  handleAcknowledge(event) {
    const errorLogId = event.target.dataset.entry;
    this.busy = true;
    this.errorMessage = undefined;
    return acknowledge({ errorLogId })
      .then((tile) => {
        this.setTile(tile);
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Core', 'Core_ErrorLog_ActionFailed'));
      })
      .finally(() => {
        this.busy = false;
        if (this.wiredTileResult) {
          refreshApex(this.wiredTileResult);
        }
      });
  }

  /**
   * Copy for Bug Report (QA review Q10): redacted text (c/bugReportText keeps only error codes
   * and stack lines, never the message or a record) on the clipboard, or shown to copy by hand.
   * The entries were read when the list loaded, so the copy runs inside the click.
   */
  async handleCopyBugReport(event) {
    const errorLogId = event.target.dataset.entry;
    this.errorMessage = undefined;
    this.reportText = undefined;
    const record = this.bugReports[errorLogId];
    if (!record) {
      this.errorMessage = this.bugReportError
        ? bodyMessage(this.bugReportError, helpText('Core', 'Core_ErrorLog_ActionFailed'))
        : helpText('Core', 'Core_ErrorLog_EntryNotFound');
      return;
    }
    const text = bugReportText(bugReportEntry(record), bugReportWords());
    try {
      await navigator.clipboard.writeText(text);
      Toast.show({ label: helpText('Core', 'Core_ErrorLogTile_Copied'), variant: 'success' }, this);
    } catch {
      this.reportText = text;
    }
  }

  /** In a console the entry opens as a subtab beside this tile; elsewhere it opens as a page. */
  async handleOpenEntry(event) {
    const pageReference = {
      type: 'standard__recordPage',
      attributes: {
        recordId: event.target.dataset.entry,
        objectApiName: ERROR_LOG_OBJECT.objectApiName,
        actionName: 'view'
      }
    };
    if (!(await openInWorkspace(this, { pageReference }))) {
      this[NavigationMixin.Navigate](pageReference);
    }
  }

  handleViewAll() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: {
        objectApiName: ERROR_LOG_OBJECT.objectApiName,
        actionName: 'list'
      },
      state: {
        filterName: 'New_Errors'
      }
    });
  }
}
