import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import findToolStateKey from '@salesforce/apex/DataManagerController.findToolStateKey';
import { fieldSetupPath } from 'c/setupLinks';
// Bare, and correctly so: a custom permission defined in the same package resolves without a
// namespace prefix.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import inspect from '@salesforce/apex/RecordInspectorController.inspect';
import { filterRows } from './inspectorRows';

import TITLE from '@salesforce/label/c.Core_RecordInspector_Title';
import INTRO from '@salesforce/label/c.Core_RecordInspector_Intro';
import INSPECT from '@salesforce/label/c.Core_RecordInspector_Inspect';
import REFRESH from '@salesforce/label/c.Core_RecordInspector_Refresh';
import LOADING from '@salesforce/label/c.Core_RecordInspector_Loading';
import SEARCH from '@salesforce/label/c.Core_RecordInspector_Search';
import COLUMN_FIELD from '@salesforce/label/c.Core_RecordInspector_ColumnField';
import COLUMN_API_NAME from '@salesforce/label/c.Core_RecordInspector_ColumnApiName';
import COLUMN_TYPE from '@salesforce/label/c.Core_RecordInspector_ColumnType';
import COLUMN_VALUE from '@salesforce/label/c.Core_RecordInspector_ColumnValue';
import COPY from '@salesforce/label/c.Core_RecordInspector_Copy';
import COPIED from '@salesforce/label/c.Core_RecordInspector_Copied';
import COPY_FAILED from '@salesforce/label/c.Core_RecordInspector_CopyFailed';
import COUNT from '@salesforce/label/c.Core_RecordInspector_Count';
import COUNT_FILTERED from '@salesforce/label/c.Core_RecordInspector_CountFiltered';
import NO_MATCH from '@salesforce/label/c.Core_RecordInspector_NoMatch';
import EMPTY from '@salesforce/label/c.Core_RecordInspector_Empty';
import SHORTENED from '@salesforce/label/c.Core_RecordInspector_Shortened';
import FIELDS_CUT from '@salesforce/label/c.Core_RecordInspector_FieldsCut';
import OPEN_FIND from '@salesforce/label/c.Core_RecordInspector_OpenFind';
import OPEN_SETUP from '@salesforce/label/c.Core_RecordInspector_OpenSetup';
import { bodyMessage } from 'c/findCsv';

/**
 * The Record Inspector (C-55): a record page component that lists every field the viewer may
 * read on the record, with its label, API name, type and value, including fields that are not on
 * the page layout. Search narrows the list and a button copies a field's API name.
 *
 * Read only. Which fields appear, and whether the record can be read at all, is decided in Apex
 * in user mode; this component adds nothing to what the person can already see. It reads
 * nothing until the person asks, and it shows nothing to someone without Manage BarnCRM
 * Settings.
 */
/** The Find tab, and the suffix of the page state key that chooses its object. */
const FIND_TAB = 'Find';
const TOOL_STATE_SUFFIX = 'tool';

export default class RecordInspector extends NavigationMixin(LightningElement) {
  @api recordId;

  /** The page state key Find reads its tool from, e.g. `c__tool`; the object key is its sibling. */
  toolStateKey;

  @wire(findToolStateKey)
  wiredToolStateKey({ data }) {
    if (data) {
      this.toolStateKey = data;
    }
  }

  labels = {
    title: TITLE,
    intro: INTRO,
    inspect: INSPECT,
    refresh: REFRESH,
    loading: LOADING,
    search: SEARCH,
    columnField: COLUMN_FIELD,
    columnApiName: COLUMN_API_NAME,
    columnType: COLUMN_TYPE,
    columnValue: COLUMN_VALUE,
    copy: COPY,
    openFind: OPEN_FIND,
    noMatch: NO_MATCH,
    shortened: SHORTENED,
    fieldsCut: FIELDS_CUT
  };

  inspection;
  searchTerm = '';
  errorMessage;
  copiedMessage;
  loading = false;

  get canUse() {
    return !!canManageSettings;
  }

  get hasInspection() {
    return !!this.inspection;
  }

  get showIntro() {
    return !this.inspection && !this.loading && !this.errorMessage;
  }

  get inspectLabel() {
    return this.inspection ? this.labels.refresh : this.labels.inspect;
  }

  get rows() {
    if (!this.inspection) {
      return [];
    }
    return filterRows(this.inspection.fields, this.searchTerm).map((field) => ({
      key: field.apiName,
      label: field.label,
      apiName: field.apiName,
      type: field.type,
      truncated: field.truncated,
      hasValue: field.value != null,
      value: field.value,
      empty: EMPTY,
      copyLabel: `${COPY}: ${field.apiName}`,
      setupUrl: fieldSetupPath(this.inspection.objectApiName, field.apiName),
      setupLabel: `${OPEN_SETUP}: ${field.label}`,
      openSetup: OPEN_SETUP
    }));
  }

  /** Opens Find on this record's object, the same for every field. */
  handleOpenFind() {
    const state = {};
    if (this.toolStateKey && this.inspection) {
      state[this.toolStateKey.replace(new RegExp(`${TOOL_STATE_SUFFIX}$`), 'object')] =
        this.inspection.objectApiName;
    }
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: FIND_TAB },
      state
    });
  }

  get noMatch() {
    return this.hasInspection && this.rows.length === 0;
  }

  get countLabel() {
    if (!this.inspection) {
      return '';
    }
    const total = this.inspection.fields.length;
    const shown = this.rows.length;
    return shown === total
      ? COUNT.replace('{0}', String(total))
      : COUNT_FILTERED.replace('{0}', String(shown)).replace('{1}', String(total));
  }

  get fieldsCut() {
    return !!(this.inspection && this.inspection.fieldsCut);
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get hasCopied() {
    return !!this.copiedMessage;
  }

  handleInspect() {
    this.loading = true;
    this.errorMessage = undefined;
    this.copiedMessage = undefined;
    return inspect({ recordId: this.recordId })
      .then((result) => {
        this.inspection = result;
      })
      .catch((error) => {
        this.inspection = undefined;
        this.errorMessage = bodyMessage(error);
      })
      .finally(() => {
        this.loading = false;
      });
  }

  handleSearch(event) {
    this.searchTerm = event.detail.value;
  }

  handleCopy(event) {
    const apiName = event.currentTarget.dataset.apiName;
    this.copiedMessage = undefined;
    const clipboard = typeof navigator !== 'undefined' ? navigator.clipboard : undefined;
    if (!clipboard || !clipboard.writeText) {
      this.errorMessage = COPY_FAILED;
      return Promise.resolve();
    }
    return clipboard
      .writeText(apiName)
      .then(() => {
        this.errorMessage = undefined;
        this.copiedMessage = COPIED.replace('{0}', apiName);
      })
      .catch(() => {
        this.errorMessage = COPY_FAILED;
      });
  }
}
