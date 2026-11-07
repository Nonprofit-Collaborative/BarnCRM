import { LightningElement, api } from 'lwc';
import deactivate from '@salesforce/apex/OrgAutomationController.deactivate';
import restore from '@salesforce/apex/OrgAutomationController.restore';
import BarnConfirmModal from 'c/barnConfirmModal';
import { bodyMessage, format } from 'c/findCsv';
import { helpText } from 'c/barnHelpText';

import TITLE from '@salesforce/label/c.Core_OrgAutomation_DeactivateTitle';
import DEACTIVATE from '@salesforce/label/c.Core_OrgAutomation_DeactivateSelected';
import SNAPSHOTS from '@salesforce/label/c.Core_OrgAutomation_Snapshots';
import PHRASE from '@salesforce/label/c.Core_OrgAutomation_ConfirmPhrase';
import RESULT_CHANGED from '@salesforce/label/c.Core_OrgAutomation_ResultDeactivated';
import RESULT_UNCHANGED from '@salesforce/label/c.Core_OrgAutomation_ResultLeft';
import RESULT_FAILED from '@salesforce/label/c.Core_OrgAutomation_ResultFailed';
import RESULT_PENDING from '@salesforce/label/c.Core_OrgAutomation_ResultPending';
import RESTORED from '@salesforce/label/c.Core_OrgAutomation_ResultRestored';
import PARTIAL from '@salesforce/label/c.Core_OrgAutomation_StatusPartial';
import RESTORING from '@salesforce/label/c.Core_OrgAutomation_StatusRestoring';
import RUNNING from '@salesforce/label/c.Core_Integrations_StatusInProgress';
import DONE from '@salesforce/label/c.Core_Shared_Completed';
import RESTORE from '@salesforce/label/c.Core_CmdtManager_RestoreAction';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import TYPE_TO_CONFIRM from '@salesforce/label/c.Core_SuperTransform_TypeToConfirm';
import NAME from '@salesforce/label/c.Core_CmdtManager_NameField';
import TYPE from '@salesforce/label/c.Core_DataDictionary_ColType';
import OBJECT from '@salesforce/label/c.Core_MatchLogic_Object';
import RESULT from '@salesforce/label/c.Core_Find_Result';
import REASON from '@salesforce/label/c.Core_Import_ResultsReason';
import STARTED from '@salesforce/label/c.Core_DataJobs_Started';

const STATUSES = {
  Running: RUNNING,
  Done: DONE,
  Partial: PARTIAL,
  Failed: RESULT_FAILED,
  Restoring: RESTORING,
  Restored: RESTORED
};
const RESULTS = {
  Pending: RESULT_PENDING,
  Changed: RESULT_CHANGED,
  Unchanged: RESULT_UNCHANGED,
  Failed: RESULT_FAILED
};
const BUSY = ['Running', 'Restoring'];
const RESTORABLE = ['Done', 'Partial'];

/**
 * Deactivate Org Flows and Validation Rules (C-60, D-184, ADR-0174): choose the org's own active
 * flows and validation rules, confirm (a typed phrase in production), and a snapshot is saved
 * before they are turned off. Each run is listed with every item's result, and Restore puts back
 * exactly what it changed. The parent reads again and passes the new state in.
 */
export default class AutomationDeactivate extends LightningElement {
  /** Inventory rows that can be deactivated, already filtered by the parent. */
  @api rows = [];
  /** The deactivation snapshots, newest first. */
  @api snapshots = [];
  @api isSandbox = false;

  selectedIds = [];
  working = false;
  errorMessage;

  labels = {
    title: TITLE,
    deactivate: DEACTIVATE,
    snapshots: SNAPSHOTS,
    restore: RESTORE,
    get intro() {
      return helpText('Core', 'Core_AutomationDeactivate_Intro');
    },
    get noneToChoose() {
      return helpText('Core', 'Core_AutomationDeactivate_NoneToChoose');
    }
  };

  chooseColumns = [
    { label: NAME, fieldName: 'name', wrapText: true },
    { label: TYPE, fieldName: 'typeText' },
    { label: OBJECT, fieldName: 'objectLabel' }
  ];

  itemColumns = [
    { label: NAME, fieldName: 'name', wrapText: true },
    { label: OBJECT, fieldName: 'objectName' },
    { label: RESULT, fieldName: 'resultText' },
    { label: REASON, fieldName: 'reason', wrapText: true }
  ];

  get hasRows() {
    return Boolean(this.rows && this.rows.length);
  }

  get busy() {
    return (this.snapshots || []).some((snapshot) => BUSY.includes(snapshot.status));
  }

  get deactivateDisabled() {
    return this.working || this.busy || this.chosen.length === 0;
  }

  get chosen() {
    const ids = new Set(this.selectedIds);
    return (this.rows || []).filter((row) => ids.has(row.key));
  }

  get hasSnapshots() {
    return Boolean(this.snapshots && this.snapshots.length);
  }

  get snapshotViews() {
    return (this.snapshots || []).map((snapshot) => ({
      ...snapshot,
      heading: [
        snapshot.name,
        STATUSES[snapshot.status] || snapshot.status,
        `${STARTED} ${new Date(snapshot.createdAt).toLocaleString()}`,
        snapshot.createdBy
      ]
        .filter(Boolean)
        .join(' · '),
      running: BUSY.includes(snapshot.status),
      canRestore: RESTORABLE.includes(snapshot.status) && !this.busy && !this.working,
      items: (snapshot.items || []).map((item) => this.itemView(item))
    }));
  }

  get runningText() {
    return helpText('Core', 'Core_AutomationDeactivate_Running');
  }

  /** An item's result in words: the restore's when there was one. */
  itemView(item) {
    let resultText = RESULTS[item.result] || item.result;
    let reason = item.message;
    if (item.restoreResult === 'Changed') {
      resultText = RESTORED;
      reason = undefined;
    } else if (item.restoreResult === 'Failed') {
      resultText = RESULT_FAILED;
      reason = item.restoreMessage;
    }
    return { ...item, resultText, reason };
  }

  handleSelect(event) {
    this.selectedIds = event.detail.selectedRows.map((row) => row.key);
  }

  async handleDeactivate() {
    const chosen = this.chosen;
    const production = !this.isSandbox;
    const confirmed = await BarnConfirmModal.open({
      label: TITLE,
      size: 'small',
      message: helpText('Core', 'Core_AutomationDeactivate_ConfirmMessage', chosen.length),
      details: production ? [helpText('Core', 'Core_AutomationDeactivate_ProductionWarning')] : [],
      items: chosen.map((row) => row.name),
      confirmLabel: DEACTIVATE,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive',
      typeToConfirm: production ? PHRASE : undefined,
      typeToConfirmLabel: production ? format(TYPE_TO_CONFIRM, PHRASE) : undefined
    });
    if (confirmed !== true) {
      return;
    }
    const items = chosen.map((row) => ({
      kind: row.kind,
      recordId: row.recordId,
      name: row.name,
      objectName: row.objectName
    }));
    await this.work(() => deactivate({ itemsJson: JSON.stringify(items) }));
    this.selectedIds = [];
  }

  async handleRestore(event) {
    const snapshotId = event.target.dataset.snapshot;
    const confirmed = await BarnConfirmModal.open({
      label: RESTORE,
      size: 'small',
      message: helpText('Core', 'Core_AutomationDeactivate_RestoreMessage'),
      confirmLabel: RESTORE,
      cancelLabel: CANCEL
    });
    if (confirmed !== true) {
      return;
    }
    await this.work(() => restore({ snapshotId }));
  }

  /** Runs one call, then asks the parent to read again. */
  async work(call) {
    this.working = true;
    this.errorMessage = undefined;
    try {
      await call();
      this.dispatchEvent(new CustomEvent('changed'));
    } catch (error) {
      this.errorMessage = bodyMessage(error);
    } finally {
      this.working = false;
    }
  }
}
