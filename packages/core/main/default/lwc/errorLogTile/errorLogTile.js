import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { openInWorkspace } from 'c/workspaceTabs';
import ERROR_LOG_OBJECT from '@salesforce/schema/Error_Log__c';
import { refreshApex } from '@salesforce/apex';
import getTile from '@salesforce/apex/ErrorLogController.getTile';
import acknowledge from '@salesforce/apex/ErrorLogController.acknowledge';
import getBugReport from '@salesforce/apex/ErrorLogController.getBugReport';
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

  @wire(EnclosingTabId) enclosingTabId;

  @wire(getTile, { rowCount: ROW_COUNT })
  wiredTile(result) {
    this.wiredTileResult = result;
    if (result.data) {
      this.tile = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = bodyMessage(result.error, helpText('Core', 'Core_ErrorLog_ActionFailed'));
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

  get entries() {
    return this.tile && this.tile.recent ? this.tile.recent : [];
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
        this.tile = tile;
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
   */
  async handleCopyBugReport(event) {
    const errorLogId = event.target.dataset.entry;
    this.errorMessage = undefined;
    this.reportText = undefined;
    let text;
    try {
      text = bugReportText(await getBugReport({ errorLogId }), bugReportWords());
    } catch (error) {
      this.errorMessage = bodyMessage(error, helpText('Core', 'Core_ErrorLog_ActionFailed'));
      return;
    }
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
