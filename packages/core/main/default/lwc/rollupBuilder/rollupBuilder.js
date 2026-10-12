import { LightningElement, wire } from 'lwc';
import getModel from '@salesforce/apex/RollupBuilderController.getModel';
import getDraft from '@salesforce/apex/RollupBuilderController.getDraft';

import TITLE from '@salesforce/label/c.Core_RollupBuilder_Title';
import COPY_OF from '@salesforce/label/c.Core_RollupBuilder_CopyOf';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Rollups_UnexpectedError';

/**
 * The Rollup Builder tab (`decisions/NEXT-barncrm-owns-its-rollup-engine.md` decision 7): every
 * rollup, shipped or admin-made, listed with the Rollups page's own controls, plus New, Edit and
 * Copy, which open the five steps. Saving refreshes the list.
 */
export default class RollupBuilder extends LightningElement {
  labels = { title: TITLE };

  model;
  draft;
  editing = false;
  notice;
  error;

  @wire(getModel)
  wiredModel({ data, error }) {
    if (data) {
      this.model = data;
    } else if (error) {
      this.error = this.messageFrom(error);
    }
  }

  get listClass() {
    return this.editing ? 'slds-hide' : '';
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
  }

  handleCancel() {
    this.editing = false;
  }

  messageFrom(error) {
    return error && error.body && error.body.message ? error.body.message : UNEXPECTED_ERROR;
  }
}
