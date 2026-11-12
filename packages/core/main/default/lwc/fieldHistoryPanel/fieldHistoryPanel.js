import { LightningElement, api } from 'lwc';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import BarnConfirmModal from 'c/barnConfirmModal';
import getHistory from '@salesforce/apex/FieldHistoryController.getHistory';
import restore from '@salesforce/apex/FieldHistoryController.restore';

import FIELD from '@salesforce/label/c.Core_AccessExplorer_Field';
import OLD_VALUE from '@salesforce/label/c.Core_Settings_ColumnOldValue';
import NEW_VALUE from '@salesforce/label/c.Core_SuperTransform_NewValue';
import CHANGED_AT from '@salesforce/label/c.Core_SetupChanges_ColChangedAt';
import CHANGED_BY from '@salesforce/label/c.Core_SetupChanges_ColChangedBy';
import RESTORE from '@salesforce/label/c.Core_CmdtManager_RestoreAction';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import BLANK from '@salesforce/label/c.Core_Find_Blank';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

function format(label, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), label);
}

/**
 * The Field History card (C-68, admin guide field-history.md): the kept changes to the chosen
 * fields of one record, newest first, with Restore for admins after a confirm. Shows nothing
 * while Field History is off. The server decides what may be read and restored.
 */
export default class FieldHistoryPanel extends LightningElement {
  helpReady = isHelpLoaded('Core');

  labels = {
    get title() {
      return helpText('Core', 'Core_FieldHistory_Title');
    },
    get empty() {
      return helpText('Core', 'Core_FieldHistory_Empty');
    },
    get cut() {
      return helpText('Core', 'Core_FieldHistory_Cut');
    },
    field: FIELD,
    before: OLD_VALUE,
    after: NEW_VALUE,
    changedAt: CHANGED_AT,
    changedBy: CHANGED_BY,
    restore: RESTORE,
    refresh: REFRESH,
    loading: LOADING
  };

  view;
  loading = false;
  error;
  message;
  _recordId;

  @api
  get recordId() {
    return this._recordId;
  }
  set recordId(value) {
    const changed = value !== this._recordId;
    this._recordId = value;
    if (changed && this.isConnected) {
      this.load();
    }
  }

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    if (!this._recordId) {
      return;
    }
    await this.call(async () => {
      this.view = await getHistory({ recordId: this._recordId });
    });
  }

  /** Runs one server call with the spinner on, showing its error, if any, in one sentence. */
  async call(work) {
    this.loading = true;
    this.error = undefined;
    try {
      await work();
    } catch (caught) {
      this.error =
        (caught && caught.body && caught.body.message) ||
        helpText('Core', 'Core_Duplicates_ErrorUnexpected');
    } finally {
      this.loading = false;
    }
  }

  /** Off: the card is not drawn at all. An error still shows, so a failure is never silent. */
  get showCard() {
    return Boolean((this.view && this.view.enabled) || this.error);
  }

  get rows() {
    return ((this.view && this.view.entries) || []).map((entry) => ({
      ...entry,
      key: `${entry.historyId}-${entry.field}`,
      beforeText: entry.before || BLANK,
      afterText: entry.after || BLANK
    }));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  handleRefresh() {
    this.message = undefined;
    this.load();
  }

  async handleRestore(event) {
    const { history, field } = event.target.dataset;
    const entry = this.rows.find((row) => row.historyId === history && row.field === field);
    if (!entry) {
      return;
    }
    const confirmed = await BarnConfirmModal.open({
      label: helpText('Core', 'Core_FieldHistory_RestoreHeading'),
      message: format(
        helpText('Core', 'Core_FieldHistory_RestoreBody'),
        entry.label,
        entry.beforeText
      ),
      confirmLabel: RESTORE,
      cancelLabel: CANCEL,
      size: 'small'
    });
    if (!confirmed) {
      return;
    }
    await this.call(async () => {
      this.view = await restore({
        recordId: this._recordId,
        historyId: history,
        fieldName: field
      });
      this.message = format(helpText('Core', 'Core_FieldHistory_Restored'), entry.label);
      await notifyRecordUpdateAvailable([{ recordId: this._recordId }]);
    });
  }
}
