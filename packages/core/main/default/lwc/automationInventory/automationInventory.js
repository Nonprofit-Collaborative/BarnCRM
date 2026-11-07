import { LightningElement } from 'lwc';
import getInventory from '@salesforce/apex/OrgAutomationController.getInventory';
import startScan from '@salesforce/apex/OrgAutomationController.startScan';
import SCAN from '@salesforce/label/c.Core_OrgAutomation_Scan';

import TITLE from '@salesforce/label/c.Core_DataDictionary_AutomationTitle';
import NAME from '@salesforce/label/c.Core_CmdtManager_NameField';
import TYPE from '@salesforce/label/c.Core_DataDictionary_ColType';
import OBJECT from '@salesforce/label/c.Core_MatchLogic_Object';
import STATUS from '@salesforce/label/c.Core_ImportRow_StatusLabel';
import RUNS from '@salesforce/label/c.Core_DataDictionary_ColAutomationRuns';
import OWNER from '@salesforce/label/c.Core_OrgAutomation_Owner';
import COVERED from '@salesforce/label/c.Core_OrgAutomation_Covered';
import OWNER_ORG from '@salesforce/label/c.Core_OrgAutomation_OwnerOrg';
import OWNER_BARN from '@salesforce/label/c.Core_ErrorDigest_SenderName';
import NOT_CHECKED from '@salesforce/label/c.Core_OrgAutomation_NotChecked';
import TYPE_BARN from '@salesforce/label/c.Core_OrgAutomation_TypeBarn';
import TYPE_FLOW from '@salesforce/label/c.Core_DataDictionary_TypeFlow';
import TYPE_PROCESS from '@salesforce/label/c.Core_OrgAutomation_TypeProcess';
import TYPE_TRIGGER from '@salesforce/label/c.Core_DataDictionary_TypeApexTrigger';
import TYPE_VALIDATION from '@salesforce/label/c.Core_OrgAutomation_TypeValidation';
import TYPE_WORKFLOW from '@salesforce/label/c.Core_OrgAutomation_TypeWorkflow';
import ACTIVE from '@salesforce/label/c.Core_MatchLogic_Active';
import INACTIVE from '@salesforce/label/c.Core_MatchLogic_Inactive';
import ON from '@salesforce/label/c.Core_Feature_On';
import OFF from '@salesforce/label/c.Core_Feature_Off';
import ALWAYS_RUNS from '@salesforce/label/c.Core_OrgAutomation_AlwaysRuns';
import YES from '@salesforce/label/c.Core_AccessExplorer_Yes';
import NO from '@salesforce/label/c.Core_DataDictionary_No';
import ALL from '@salesforce/label/c.Core_DataJobs_ShowAll';
import HOW_TO from '@salesforce/label/c.Core_OrgAutomation_HowTo';
import DOWNLOAD from '@salesforce/label/c.Core_AccessExplorer_Download';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import COPY from '@salesforce/label/c.Core_RecordInspector_Copy';
import CLOSE from '@salesforce/label/c.Core_BulkUpdate_Close';
import API_NAME from '@salesforce/label/c.Core_AccessExplorer_ColApiName';
import OBJECT_API_NAME from '@salesforce/label/c.Core_DataDictionary_ColObjectApiName';
import { bodyMessage, downloadCsv } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { snippetCode, snippetKind } from './automationSnippets';

const TYPES = {
  BarnCRM: TYPE_BARN,
  Flow: TYPE_FLOW,
  ProcessBuilder: TYPE_PROCESS,
  ApexTrigger: TYPE_TRIGGER,
  ValidationRule: TYPE_VALIDATION,
  WorkflowRule: TYPE_WORKFLOW
};
const STATUSES = {
  Active: ACTIVE,
  Inactive: INACTIVE,
  On: ON,
  Off: OFF,
  AlwaysRuns: ALWAYS_RUNS
};
const COVERAGE = { Yes: YES, No: NO, NotChecked: NOT_CHECKED };
const PARTS = { Switches: TYPE_BARN, Flows: TYPE_FLOW, Triggers: TYPE_TRIGGER };
const OWNER_BARNCRM = 'BarnCRM';
const OWNER_THIS_ORG = 'Org';
const ALL_VALUE = '';
const HOW_TO_ACTION = 'howTo';
const SCAN_RUNNING = 'Running';
const SCAN_FAILED = 'Failed';
const DEACTIVATION_BUSY = ['Running', 'Restoring'];
/** How often, and how many times, the page reads again while a scan runs. */
const POLL_MS = 4000;
const POLL_LIMIT = 45;

/** The owner in words: BarnCRM, This Org, or the managed package's namespace. */
function ownerText(owner) {
  if (owner === OWNER_BARNCRM) {
    return OWNER_BARN;
  }
  return owner === OWNER_THIS_ORG ? OWNER_ORG : owner;
}

/**
 * The Automation tab's inventory (C-60, D-184): every automation in the org in one table, with
 * its owner and whether the BarnCRM Automation Control setting (Pause All and Bypass) covers it,
 * filters by object and owner, a CSV, and for an org item it does not cover the code that makes
 * it respect Pause All.
 */
export default class AutomationInventory extends LightningElement {
  helpReady = isHelpLoaded('Core');
  labels = {
    title: TITLE,
    object: OBJECT,
    owner: OWNER,
    download: DOWNLOAD,
    refresh: REFRESH,
    howTo: HOW_TO,
    copy: COPY,
    close: CLOSE,
    scan: SCAN,
    get connectionNeeded() {
      return helpText('Core', 'Core_AutomationInventory_ConnectionNeeded');
    },
    get scanIntro() {
      return helpText('Core', 'Core_AutomationInventory_ScanIntro');
    },
    get intro() {
      return helpText('Core', 'Core_AutomationInventory_Intro');
    },
    get empty() {
      return helpText('Core', 'Core_AutomationInventory_Empty');
    },
    get truncated() {
      return helpText('Core', 'Core_AutomationInventory_Truncated');
    },
    get notCheckedHelp() {
      return helpText('Core', 'Core_AutomationInventory_NotCheckedHelp');
    }
  };

  result;
  loading = false;
  errorMessage;
  objectFilter = ALL_VALUE;
  ownerFilter = ALL_VALUE;
  sortedBy = 'objectLabel';
  sortDirection = 'asc';
  /** The row whose snippet is shown. */
  snippetRow;
  pollTimer;
  polls = 0;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  disconnectedCallback() {
    clearTimeout(this.pollTimer);
  }

  async load() {
    this.loading = true;
    this.errorMessage = undefined;
    try {
      this.result = await getInventory();
      this.pollWhileScanning();
    } catch (error) {
      this.errorMessage = bodyMessage(error);
    } finally {
      this.loading = false;
    }
  }

  /** Reads again a few seconds later while a scan or deactivation runs, up to POLL_LIMIT times. */
  pollWhileScanning() {
    clearTimeout(this.pollTimer);
    if (!(this.scanRunning || this.deactivationRunning) || this.polls >= POLL_LIMIT) {
      this.polls = 0;
      return;
    }
    this.polls += 1;
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.pollTimer = setTimeout(() => this.load(), POLL_MS);
  }

  get canScan() {
    return Boolean(this.result && this.result.canUseConnection && this.result.connected);
  }

  get needsConnection() {
    return Boolean(this.result && this.result.canUseConnection && !this.result.connected);
  }

  get scanRunning() {
    return Boolean(this.result && this.result.scanStatus === SCAN_RUNNING);
  }

  get deactivationRunning() {
    return this.snapshots.some((snapshot) => DEACTIVATION_BUSY.includes(snapshot.status));
  }

  get snapshots() {
    return (this.result && this.result.snapshots) || [];
  }

  get isSandbox() {
    return Boolean(this.result && this.result.isSandbox);
  }

  /** The org's own active flows and validation rules in the filtered list (R-OA6). */
  get deactivatableRows() {
    return this.filteredRows.filter((row) => row.canDeactivate);
  }

  get scanDisabled() {
    return this.loading || this.scanRunning;
  }

  /** The newest scan in words: running, failed (why), or when it read the org. */
  get scanLine() {
    const result = this.result || {};
    if (result.scanStatus === SCAN_RUNNING) {
      return helpText('Core', 'Core_AutomationInventory_ScanRunning');
    }
    if (result.scanStatus === SCAN_FAILED) {
      return result.scanMessage;
    }
    return result.scannedAt
      ? helpText(
          'Core',
          'Core_AutomationInventory_ScannedAt',
          new Date(result.scannedAt).toLocaleString()
        )
      : undefined;
  }

  async handleScan() {
    this.errorMessage = undefined;
    try {
      await startScan();
      await this.load();
    } catch (error) {
      this.errorMessage = bodyMessage(error);
    }
  }

  get rows() {
    return ((this.result && this.result.rows) || []).map((row) => ({
      ...row,
      typeText: TYPES[row.kind] || row.kind,
      statusText: STATUSES[row.status] || row.status,
      ownerText: ownerText(row.owner),
      coveredText: COVERAGE[row.covered] || row.covered,
      objectLabel: row.objectLabel || row.objectName || ''
    }));
  }

  get filteredRows() {
    const field = this.sortedBy;
    const direction = this.sortDirection === 'asc' ? 1 : -1;
    return this.rows
      .filter(
        (row) =>
          (this.objectFilter === ALL_VALUE || row.objectName === this.objectFilter) &&
          (this.ownerFilter === ALL_VALUE || row.owner === this.ownerFilter)
      )
      .sort(
        (a, b) =>
          direction * String(a[field] || '').localeCompare(String(b[field] || '')) ||
          String(a.name || '').localeCompare(String(b.name || ''))
      );
  }

  get hasRows() {
    return this.filteredRows.length > 0;
  }

  get showEmpty() {
    return Boolean(this.result) && !this.hasRows;
  }

  get objectOptions() {
    const byName = new Map();
    for (const row of this.rows) {
      if (row.objectName) {
        byName.set(row.objectName, row.objectLabel);
      }
    }
    return [{ label: ALL, value: ALL_VALUE }].concat(
      [...byName.entries()]
        .sort((a, b) => a[1].localeCompare(b[1]))
        .map(([value, label]) => ({ label, value }))
    );
  }

  get ownerOptions() {
    const owners = new Set(this.rows.map((row) => row.owner));
    const packages = [...owners].filter((o) => o !== OWNER_BARNCRM && o !== OWNER_THIS_ORG).sort();
    return [{ label: ALL, value: ALL_VALUE }].concat(
      [OWNER_BARNCRM, OWNER_THIS_ORG, ...packages]
        .filter((owner) => owners.has(owner))
        .map((owner) => ({ label: ownerText(owner), value: owner }))
    );
  }

  get columns() {
    return [
      { label: NAME, fieldName: 'name', sortable: true, wrapText: true },
      { label: TYPE, fieldName: 'typeText', sortable: true },
      { label: OBJECT, fieldName: 'objectLabel', sortable: true },
      { label: STATUS, fieldName: 'statusText', sortable: true },
      { label: OWNER, fieldName: 'ownerText', sortable: true },
      { label: RUNS, fieldName: 'detail', wrapText: true },
      { label: COVERED, fieldName: 'coveredText', sortable: true },
      {
        type: 'action',
        typeAttributes: { rowActions: (row, done) => done(this.actionsFor(row)) }
      }
    ];
  }

  /** The How To action, for an org item that Pause All does not cover (or is not checked). */
  actionsFor(row) {
    return row.owner === OWNER_THIS_ORG && row.covered !== 'Yes' && snippetKind(row.kind)
      ? [{ label: HOW_TO, name: HOW_TO_ACTION }]
      : [];
  }

  get unreadableMessage() {
    const parts = (this.result && this.result.unreadable) || [];
    return parts.length
      ? helpText(
          'Core',
          'Core_AutomationInventory_Unreadable',
          parts.map((part) => PARTS[part] || part).join(', ')
        )
      : undefined;
  }

  get isTruncated() {
    return Boolean(this.result && this.result.truncated);
  }

  get hasNotChecked() {
    return this.rows.some((row) => row.covered === 'NotChecked');
  }

  get downloadDisabled() {
    return !this.hasRows;
  }

  get snippet() {
    if (!this.snippetRow) {
      return undefined;
    }
    const kind = snippetKind(this.snippetRow.kind);
    const name = this.snippetRow.name;
    let steps;
    if (kind === 'flow') {
      steps = helpText('Core', 'Core_AutomationInventory_SnippetFlow', name);
    } else if (kind === 'apex') {
      steps = helpText('Core', 'Core_AutomationInventory_SnippetApex', name);
    } else {
      steps = helpText('Core', 'Core_AutomationInventory_SnippetFormula', name);
    }
    return {
      heading: `${HOW_TO}: ${name}`,
      steps,
      code: snippetCode(
        this.snippetRow,
        this.result && this.result.classPrefix,
        this.result && this.result.fieldPrefix
      )
    };
  }

  handleObject(event) {
    this.objectFilter = event.detail.value;
  }

  handleOwner(event) {
    this.ownerFilter = event.detail.value;
  }

  handleSort(event) {
    this.sortedBy = event.detail.fieldName;
    this.sortDirection = event.detail.sortDirection;
  }

  handleRowAction(event) {
    if (event.detail.action.name === HOW_TO_ACTION) {
      this.snippetRow = event.detail.row;
    }
  }

  handleCloseSnippet() {
    this.snippetRow = undefined;
  }

  handleCopy() {
    const code = this.snippet && this.snippet.code;
    if (code && navigator.clipboard) {
      navigator.clipboard.writeText(code);
    }
  }

  handleRefresh() {
    this.snippetRow = undefined;
    this.load();
  }

  handleDownload() {
    downloadCsv(
      'Automation-Inventory',
      [
        { label: NAME, path: 'name' },
        { label: API_NAME, path: 'apiName' },
        { label: TYPE, path: 'typeText' },
        { label: OBJECT, path: 'objectLabel' },
        { label: OBJECT_API_NAME, path: 'objectName' },
        { label: STATUS, path: 'statusText' },
        { label: OWNER, path: 'ownerText' },
        { label: RUNS, path: 'detail' },
        { label: COVERED, path: 'coveredText' }
      ],
      this.filteredRows
    );
  }
}
