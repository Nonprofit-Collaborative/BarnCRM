import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import hasErasePermission from '@salesforce/customPermission/Erase_People';
import getPreview from '@salesforce/apex/PersonErasureController.preview';
import erasePerson from '@salesforce/apex/PersonErasureController.erase';

import TITLE from '@salesforce/label/c.Core_EraseAction_Title';
import WARNING from '@salesforce/label/c.Core_EraseAction_Warning';
import PREVIEW from '@salesforce/label/c.Core_EraseAction_Preview';
import WORKING from '@salesforce/label/c.Core_EraseAction_Working';
import COLUMN_ACTION from '@salesforce/label/c.Core_EraseAction_ColumnAction';
import COLUMN_OBJECT from '@salesforce/label/c.Core_EraseAction_ColumnObject';
import COLUMN_COUNT from '@salesforce/label/c.Core_EraseAction_ColumnCount';
import COLUMN_FIELDS from '@salesforce/label/c.Core_EraseAction_ColumnFields';
import COLUMN_NOTE from '@salesforce/label/c.Core_EraseAction_ColumnNote';
import ACTION_CLEARED from '@salesforce/label/c.Core_EraseAction_Cleared';
import ACTION_ENDED from '@salesforce/label/c.Core_EraseAction_Ended';
import ACTION_DELETED from '@salesforce/label/c.Core_EraseAction_Deleted';
import ACTION_KEPT from '@salesforce/label/c.Core_EraseAction_Kept';
import ACTION_UPDATED from '@salesforce/label/c.Core_EraseAction_Updated';
import REFERENCE from '@salesforce/label/c.Core_EraseAction_Reference';
import REFERENCE_HELP from '@salesforce/label/c.Core_EraseAction_ReferenceHelp';
import CONFIRM from '@salesforce/label/c.Core_EraseAction_Confirm';
import ERASE from '@salesforce/label/c.Core_EraseAction_Erase';
import DONE from '@salesforce/label/c.Core_EraseAction_Done';
import OPEN_AUDIT from '@salesforce/label/c.Core_EraseAction_OpenAudit';
import CLOSE from '@salesforce/label/c.Core_EraseAction_Close';
import NO_PERMISSION from '@salesforce/label/c.Core_Erase_NoPermission';

const ACTION_LABELS = {
  Cleared: ACTION_CLEARED,
  Ended: ACTION_ENDED,
  Deleted: ACTION_DELETED,
  Kept: ACTION_KEPT,
  Updated: ACTION_UPDATED
};

/** Matches the server's comparison: spaces collapsed, case ignored. */
function normalized(value) {
  return (value || '').replace(/\s+/g, ' ').trim().toLowerCase();
}

export default class PersonErasure extends NavigationMixin(LightningElement) {
  @api recordId;

  label = {
    title: TITLE,
    warning: WARNING,
    preview: PREVIEW,
    working: WORKING,
    reference: REFERENCE,
    referenceHelp: REFERENCE_HELP,
    erase: ERASE,
    done: DONE,
    openAudit: OPEN_AUDIT,
    close: CLOSE,
    noPermission: NO_PERMISSION
  };

  columns = [
    { label: COLUMN_ACTION, fieldName: 'actionLabel', type: 'text' },
    { label: COLUMN_OBJECT, fieldName: 'objectLabel', type: 'text' },
    { label: COLUMN_COUNT, fieldName: 'count', type: 'number', initialWidth: 110 },
    { label: COLUMN_FIELDS, fieldName: 'fieldList', type: 'text', wrapText: true },
    { label: COLUMN_NOTE, fieldName: 'note', type: 'text', wrapText: true }
  ];

  rows;
  personName;
  typedName = '';
  reference = '';
  working = false;
  error;
  erasureId;

  get allowed() {
    return hasErasePermission === true;
  }

  get hasRows() {
    return Array.isArray(this.rows);
  }

  get erased() {
    return Boolean(this.erasureId);
  }

  get confirmLabel() {
    return CONFIRM.replace('{0}', this.personName || '');
  }

  get eraseDisabled() {
    return (
      this.working || !this.personName || normalized(this.typedName) !== normalized(this.personName)
    );
  }

  async handlePreview() {
    this.working = true;
    this.error = undefined;
    try {
      const result = await getPreview({ personId: this.recordId });
      this.personName = result.personName;
      this.rows = this.toRows(result.changes);
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  async handleErase() {
    this.working = true;
    this.error = undefined;
    try {
      const result = await erasePerson({
        personId: this.recordId,
        typedName: this.typedName,
        requestReference: this.reference
      });
      this.rows = this.toRows(result.changes);
      this.erasureId = result.erasureId;
      this.dispatchEvent(new RefreshEvent());
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  handleTypedName(event) {
    this.typedName = event.target.value;
  }

  handleReference(event) {
    this.reference = event.target.value;
  }

  handleOpenAudit() {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId: this.erasureId, actionName: 'view' }
    });
  }

  handleClose() {
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  toRows(changes) {
    return (changes || []).map((change, index) => ({
      key: String(index),
      actionLabel: ACTION_LABELS[change.action] || change.action,
      objectLabel: change.objectLabel,
      count: change.count,
      fieldList: (change.fields || []).join(', '),
      note: change.note
    }));
  }

  messageOf(failure) {
    return (failure && failure.body && failure.body.message) || String(failure);
  }
}
