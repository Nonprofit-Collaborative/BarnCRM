import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import findToolStateKey from '@salesforce/apex/DataManagerController.findToolStateKey';
import pageLink from '@salesforce/apex/RecordInspectorController.pageLink';
import { iconFor } from 'c/barnIcons';
import { tabPageReference } from 'c/barnTabs';
import { fieldSetupPath } from 'c/setupLinks';
// Bare, and correctly so: a custom permission defined in the same package resolves without a
// namespace prefix.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import inspect from '@salesforce/apex/RecordInspectorController.inspect';
import { filterRows, parseRecordId } from './inspectorRows';
import RECORD_INPUT from '@salesforce/label/c.Core_RecordInspector_RecordInput';
import GO from '@salesforce/label/c.Core_RecordInspector_Go';

import TITLE from '@salesforce/label/c.Core_RecordInspector_Title';
import INSPECT from '@salesforce/label/c.Core_RecordInspector_Inspect';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import LOADING from '@salesforce/label/c.Core_RecordInspector_Loading';
import SEARCH from '@salesforce/label/c.Core_RecordInspector_Search';
import COLUMN_FIELD from '@salesforce/label/c.Core_AccessExplorer_Field';
import COLUMN_API_NAME from '@salesforce/label/c.Core_AccessExplorer_ColApiName';
import COLUMN_TYPE from '@salesforce/label/c.Core_DataDictionary_ColType';
import COLUMN_VALUE from '@salesforce/label/c.Core_Filter_Value';
import COPY from '@salesforce/label/c.Core_RecordInspector_Copy';
import COPIED from '@salesforce/label/c.Core_RecordInspector_Copied';
import COUNT from '@salesforce/label/c.Core_RecordInspector_Count';
import COUNT_FILTERED from '@salesforce/label/c.Core_RecordInspector_CountFiltered';
import EMPTY from '@salesforce/label/c.Core_RecordInspector_Empty';
import SHORTENED from '@salesforce/label/c.Core_RecordInspector_Shortened';
import OPEN_FIND from '@salesforce/label/c.Core_DataHygiene_OpenInFind';
import OPEN_SETUP from '@salesforce/label/c.Core_SetupNote_OpenInSetup';
import { bodyMessage, format } from 'c/findCsv';
import WhereUsedModal from 'c/whereUsedModal';
import WHERE_USED_ALT from '@salesforce/label/c.Core_WhereUsed_Title';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * The Record Inspector (C-55): lists every field the viewer may read on one record, with its
 * label, API name, type and value, including fields that are not on the page layout. Search
 * narrows the list and a button copies a field's API name.
 *
 * It runs on its own page (the Record Inspector tab), opened by the Inspect This Record button
 * (c/recordInspectorButton) with the record ID in the page state, and reads that record at once;
 * opened with no ID, it asks for an ID or a record link. On a record page it inspects that
 * record when asked, as it did before the page existed.
 *
 * Read only. Which fields appear, and whether the record can be read at all, is decided in Apex
 * in user mode; this component adds nothing to what the person can already see. It reads
 * nothing until the person asks, and it shows nothing to someone without Manage BarnCRM
 * Settings.
 */
/** The Find tab, and the suffix of the page state key that chooses its object. */
const FIND_TAB = 'Find';
const TOOL_STATE_SUFFIX = 'tool';
/** The suffix of the page state key that names the record, e.g. `c__recordId`. */
const RECORD_ID_STATE = '__recordId';

export default class RecordInspector extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  /** Set on a record page only; on the Record Inspector page the record comes from the URL. */
  @api recordId;

  /** The record the page state names, on the Record Inspector page. */
  pageRecordId;
  /** What is typed in the page's Record ID or Link box. */
  pageInput = '';
  /** The Record Inspector tab and state key, qualified for the org (Apex). */
  link;
  iconName = iconFor('Record_Inspector');

  @wire(pageLink)
  wiredPageLink({ data }) {
    if (data) {
      this.link = data;
    }
  }

  /** On the Record Inspector page: reads the record the page state names, at once. */
  @wire(CurrentPageReference)
  handlePageReference(pageReference) {
    if (this.recordId || !this.canUse) {
      return;
    }
    const state = (pageReference && pageReference.state) || {};
    const key = Object.keys(state).find((name) => name.endsWith(RECORD_ID_STATE));
    const asked = key ? state[key] : undefined;
    const requested = parseRecordId(asked);
    if (requested && requested === this.pageRecordId) {
      return;
    }
    this.pageRecordId = requested;
    this.pageInput = asked || '';
    this.inspection = undefined;
    this.errorMessage = undefined;
    // A flag, not the text: the page state can arrive before the help text has loaded.
    this.badInput = !requested && !!asked;
    if (requested) {
      this.handleInspect();
    }
  }

  /** True when the pasted text or the page state holds no record ID. */
  badInput = false;

  get onPage() {
    return !this.recordId;
  }

  /** The record to read: the record page's, or the one the Record Inspector page names. */
  get targetId() {
    return this.recordId || this.pageRecordId;
  }

  get canInspect() {
    return !!this.targetId;
  }

  get introText() {
    return this.onPage
      ? helpText('Core', 'Core_RecordInspector_PageIntro')
      : helpText('Core', 'Core_RecordInspector_Intro');
  }

  /** The inspected record's name, linked back to its page, shown on the Record Inspector page. */
  get showRecordHeading() {
    return this.onPage && this.hasInspection;
  }

  get recordName() {
    return (this.inspection && (this.inspection.recordName || this.inspection.recordId)) || '';
  }

  get recordUrl() {
    return this.inspection ? `/lightning/r/${this.inspection.recordId}/view` : undefined;
  }

  handlePageInput(event) {
    this.pageInput = event.detail.value;
  }

  /** Enter in the box inspects, as the button does. */
  handlePageKey(event) {
    if (event.key === 'Enter') {
      this.pageInput = event.target.value;
      this.handleGo();
    }
  }

  /** Inspects the pasted ID or link, through the page state so the address names the record. */
  handleGo() {
    const requested = parseRecordId(this.pageInput);
    if (!requested) {
      this.inspection = undefined;
      this.errorMessage = undefined;
      this.badInput = true;
      return undefined;
    }
    if (requested === this.pageRecordId || !this.link) {
      this.pageRecordId = requested;
      return this.handleInspect();
    }
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: this.link.tabApiName },
      state: { [this.link.recordIdKey]: requested }
    });
    return undefined;
  }

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
    inspect: INSPECT,
    recordInput: RECORD_INPUT,
    go: GO,
    refresh: REFRESH,
    loading: LOADING,
    search: SEARCH,
    columnField: COLUMN_FIELD,
    columnApiName: COLUMN_API_NAME,
    columnType: COLUMN_TYPE,
    columnValue: COLUMN_VALUE,
    copy: COPY,
    openFind: OPEN_FIND,
    get noMatch() {
      return helpText('Core', 'Core_RecordInspector_NoMatch');
    },
    shortened: SHORTENED,
    get fieldsCut() {
      return helpText('Core', 'Core_RecordInspector_FieldsCut');
    }
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
    return !this.inspection && !this.loading && !this.hasError;
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
      openSetup: OPEN_SETUP,
      whereUsedLabel: format(WHERE_USED_ALT, field.label)
    }));
  }

  /** A field row's Where Used button (C-59): which BarnCRM setup uses the field. */
  handleWhereUsed(event) {
    const apiName = event.currentTarget.dataset.apiName;
    const field = (this.inspection.fields || []).find((one) => one.apiName === apiName);
    WhereUsedModal.open({
      size: 'medium',
      objectName: this.inspection.objectApiName,
      objectLabel: this.inspection.objectLabel,
      fieldName: apiName,
      fieldLabel: field ? field.label : apiName
    });
  }

  /** Opens Find on this record's object, the same for every field. */
  async handleOpenFind() {
    const state = {};
    if (this.toolStateKey && this.inspection) {
      state[this.toolStateKey.replace(new RegExp(`${TOOL_STATE_SUFFIX}$`), 'object')] =
        this.inspection.objectApiName;
    }
    this[NavigationMixin.Navigate](await tabPageReference(FIND_TAB, state));
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

  get shownError() {
    return this.badInput ? helpText('Core', 'Core_RecordInspector_BadInput') : this.errorMessage;
  }

  get hasError() {
    return !!this.shownError;
  }

  get hasCopied() {
    return !!this.copiedMessage;
  }

  handleInspect() {
    this.loading = true;
    this.errorMessage = undefined;
    this.badInput = false;
    this.copiedMessage = undefined;
    return inspect({ recordId: this.targetId })
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
      this.errorMessage = helpText('Core', 'Core_RecordInspector_CopyFailed');
      return Promise.resolve();
    }
    return clipboard
      .writeText(apiName)
      .then(() => {
        this.errorMessage = undefined;
        this.copiedMessage = COPIED.replace('{0}', apiName);
      })
      .catch(() => {
        this.errorMessage = helpText('Core', 'Core_RecordInspector_CopyFailed');
      });
  }
}
