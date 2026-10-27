import { LightningElement, wire } from 'lwc';
import getModel from '@salesforce/apex/RollupBuilderController.getModel';
import getDraft from '@salesforce/apex/RollupBuilderController.getDraft';

import TITLE from '@salesforce/label/c.Core_RollupBuilder_Title';
import COPY_OF from '@salesforce/label/c.Core_RollupBuilder_CopyOf';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Rollups_UnexpectedError';
import TAB_LABEL from '@salesforce/label/c.Core_Console_TabLabel';
import OTHER_TOOLS from '@salesforce/label/c.Core_OtherRollupTools_Title';
import IMPORT_FROM_DLRS from '@salesforce/label/c.Core_RollupBuilder_DlrsImportButton';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { labelTab } from 'c/rollupTabLabel';

const TAB_ICON = 'utility:builder';

/**
 * The Rollup Builder tab (`decisions/0082-barncrm-owns-its-rollup-engine.md` decision 7): every
 * rollup, shipped or admin-made, listed with the Rollups page's own controls, plus New, Edit and
 * Copy, which open the five steps. Saving refreshes the list.
 */
export default class RollupBuilder extends LightningElement {
  labels = { title: TITLE, otherTools: OTHER_TOOLS, importFromDlrs: IMPORT_FROM_DLRS };

  model;
  draft;
  editing = false;
  importing = false;
  notice;
  error;
  enclosingTabId;

  /** In a console the tab is named for the rollup being edited. */
  @wire(EnclosingTabId)
  wiredTabId(tabId) {
    this.enclosingTabId = tabId;
    this.nameTab();
  }

  renderedCallback() {
    this.nameTab();
  }

  nameTab() {
    const name = this.editing && this.draft ? this.draft.name : undefined;
    const label = name ? TAB_LABEL.replace('{0}', TITLE).replace('{1}', name) : TITLE;
    labelTab(this, label, TAB_ICON);
  }

  @wire(getModel)
  wiredModel({ data, error }) {
    if (data) {
      this.model = data;
    } else if (error) {
      this.error = this.messageFrom(error);
    }
  }

  /** DLRS or Rollup Helper in this org: separate tools whose rollups BarnCRM does not manage. */
  get otherToolNotices() {
    return (this.model && this.model.otherToolNotices) || [];
  }

  get hasOtherTools() {
    return this.otherToolNotices.length > 0;
  }

  get listClass() {
    return this.editing || this.importing ? 'slds-hide' : '';
  }

  /** Import from DLRS, offered when DLRS has an active rollup and the viewer may manage (R-R16). */
  get showImport() {
    return Boolean(this.model && this.model.canImportFromDlrs) && !this.editing && !this.importing;
  }

  handleImport() {
    this.notice = undefined;
    this.error = undefined;
    this.importing = true;
  }

  /** The wizard closed: finished (with its notice) or left, the copies kept either way. */
  handleImportClosed(event) {
    this.importing = false;
    this.handleSaved({ detail: { notice: event.detail && event.detail.notice } });
  }

  /** Whether the viewer may switch instant totals off and on (Manage BarnCRM Settings). */
  get canManage() {
    return Boolean(this.model && this.model.canManage);
  }

  handleNew() {
    this.open(null);
  }

  handleEdit(event) {
    this.load(event.detail.recordId, false);
  }

  handleCopy(event) {
    this.load(event.detail.recordId, true);
  }

  load(recordId, asCopy) {
    this.error = undefined;
    getDraft({ definitionId: recordId })
      .then((draft) => {
        this.open(
          asCopy
            ? { ...draft, recordId: undefined, name: COPY_OF.replace('{0}', draft.name) }
            : draft
        );
      })
      .catch((error) => {
        this.error = this.messageFrom(error);
      });
  }

  open(draft) {
    this.notice = undefined;
    this.draft = draft;
    this.editing = true;
  }

  handleSaved(event) {
    this.notice = event.detail.notice;
    this.editing = false;
    const list = this.template.querySelector('c-rollup-definitions');
    if (list) {
      list.refresh();
    }
    const instant = this.template.querySelector('c-rollup-instant-totals');
    if (instant) {
      instant.load();
    }
    const attention = this.template.querySelector('c-rollup-needs-attention');
    if (attention) {
      attention.load();
    }
  }

  handleCancel() {
    this.editing = false;
  }

  messageFrom(error) {
    return error && error.body && error.body.message ? error.body.message : UNEXPECTED_ERROR;
  }
}
