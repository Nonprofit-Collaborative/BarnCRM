import { LightningElement, api, wire } from 'lwc';
import getStatus from '@salesforce/apex/FieldAccessController.getStatus';
import searchSets from '@salesforce/apex/FieldAccessController.searchSets';
import getFields from '@salesforce/apex/FieldAccessController.getFields';
import previewChange from '@salesforce/apex/FieldAccessController.preview';
import applyChange from '@salesforce/apex/FieldAccessController.apply';
import undoChange from '@salesforce/apex/FieldAccessController.undo';
import listChanges from '@salesforce/apex/FieldAccessController.listChanges';
import listObjects from '@salesforce/apex/DataDictionaryController.listObjects';
import BarnConfirmModal from 'c/barnConfirmModal';
import { format, messageFrom } from 'c/findCsv';
import {
  READ,
  EDIT,
  NONE,
  withItems,
  withoutItem,
  conflicts,
  buildChange,
  askedWord,
  previewRows,
  filterFields
} from 'c/fieldAccessPlan';
import { shownColumns, nameOptions } from 'c/accessExplorerRows';

import SETS from '@salesforce/label/c.Core_AccessCompare_Sets';
import SETS_PLACEHOLDER from '@salesforce/label/c.Core_FieldAccess_SetsPlaceholder';
import KIND_OF_RECORD from '@salesforce/label/c.Core_AccessExplorer_KindOfRecord';
import OBJECT_ACCESS from '@salesforce/label/c.Core_FieldAccess_ObjectAccess';
import NO_CHANGE from '@salesforce/label/c.Core_FieldAccess_NoChange';
import WORD_READ from '@salesforce/label/c.Core_AccessExplorer_ColRead';
import WORD_EDIT from '@salesforce/label/c.Core_FieldAccess_ReadEdit';
import WORD_NONE from '@salesforce/label/c.Core_FieldAccess_NoAccess';
import FIELDS_HEADING from '@salesforce/label/c.Core_AccessCompare_FieldsHeading';
import FILTER_FIELDS from '@salesforce/label/c.Core_FieldAccess_FilterFields';
import FIELD_ACCESS from '@salesforce/label/c.Core_FieldAccess_FieldAccess';
import ADD from '@salesforce/label/c.Core_FieldAccess_AddToChanges';
import COL_FIELD from '@salesforce/label/c.Core_AccessExplorer_Field';
import COL_API_NAME from '@salesforce/label/c.Core_AccessExplorer_ColApiName';
import COL_NOW from '@salesforce/label/c.Core_FieldAccess_ColNow';
import COL_NOTE from '@salesforce/label/c.Core_EraseAction_ColumnNote';
import NOW_TEXT from '@salesforce/label/c.Core_FieldAccess_NowText';
import READ_ONLY from '@salesforce/label/c.Core_FieldAccess_ReadOnlyNote';
import CHANGES_HEADING from '@salesforce/label/c.Core_BulkUpdate_Changes';
import COL_ACCESS from '@salesforce/label/c.Core_Access_PageTitle';
import WHOLE_RECORD from '@salesforce/label/c.Core_FieldAccess_WholeRecord';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import CLEAR from '@salesforce/label/c.Core_BulkUpdate_ActionClear';
import PREVIEW from '@salesforce/label/c.Core_BulkUpdate_Preview';
import COL_SET from '@salesforce/label/c.Core_AccessExplorer_KindSet';
import COL_AFTER from '@salesforce/label/c.Core_Import_ChangesAfter';
import COL_WHY from '@salesforce/label/c.Core_FieldAccess_ColWhy';
import WHY_ASKED from '@salesforce/label/c.Core_FieldAccess_WhyAsked';
import WHY_NEEDED from '@salesforce/label/c.Core_FieldAccess_WhyNeeded';
import WHY_REMOVED from '@salesforce/label/c.Core_FieldAccess_WhyRemoved';
import APPLY from '@salesforce/label/c.Core_FieldAccess_Apply';
import CONFIRM_TITLE from '@salesforce/label/c.Core_FieldAccess_ConfirmTitle';
import CONFIRM_BUTTON from '@salesforce/label/c.Core_FieldAccess_ConfirmButton';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import RECENT_HEADING from '@salesforce/label/c.Core_Settings_RecentChangesHeading';
import COL_WHEN from '@salesforce/label/c.Core_FieldAccess_ColWhen';
import COL_BY from '@salesforce/label/c.Core_FieldAccess_ColBy';
import COL_CHANGED from '@salesforce/label/c.Core_FieldAccess_ColChanged';
import COL_REFUSED from '@salesforce/label/c.Core_FieldAccess_ColRefused';
import COL_STATUS from '@salesforce/label/c.Core_ImportRow_StatusLabel';
import COL_UNDO_UNTIL from '@salesforce/label/c.Core_FieldAccess_ColUndoUntil';
import UNDO from '@salesforce/label/c.Core_AutoMerge_Undo';
import UNDO_TITLE from '@salesforce/label/c.Core_FieldAccess_UndoConfirmTitle';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const SEARCH_DELAY = 300;
/** The change is recorded by a queued job just after an apply: list it again after this. */
const RECORD_DELAY = 3000;
const WORDS = {
  read: WORD_READ,
  edit: WORD_EDIT,
  none: WORD_NONE,
  wholeRecord: WHOLE_RECORD,
  reasons: { asked: WHY_ASKED, neededForFields: WHY_NEEDED, removedWithObject: WHY_REMOVED }
};
const DATE_TIME = {
  year: 'numeric',
  month: 'short',
  day: 'numeric',
  hour: '2-digit',
  minute: '2-digit'
};
const text = (fieldName, label, extra = {}) => ({ label, fieldName, ...extra });

/**
 * Access Explorer's Change Field Access view, the Field Access Manager (C-65, ADR-0156, admin
 * guide field-access-manager.md): give or remove Read and Edit on fields and kinds of record for
 * permission sets the organization made, with a row-by-row preview and undo. The change list and
 * its words are c/fieldAccessPlan (framework free); every check and write is FieldAccessController.
 */
export default class FieldAccessManager extends LightningElement {
  /** Show the API Name column and API names in the picker (Access Explorer's toggle). */
  @api showTechnicalNames = false;

  helpReady = isHelpLoaded('Core');

  labels = {
    get intro() {
      return helpText('Core', 'Core_FieldAccess_Intro');
    },
    sets: SETS,
    setsPlaceholder: SETS_PLACEHOLDER,
    get noMatches() {
      return helpText('Core', 'Core_AccessExplorer_NoMatches');
    },
    kindOfRecord: KIND_OF_RECORD,
    objectAccess: OBJECT_ACCESS,
    fieldsHeading: FIELDS_HEADING,
    filterFields: FILTER_FIELDS,
    fieldAccess: FIELD_ACCESS,
    add: ADD,
    changesHeading: CHANGES_HEADING,
    clear: CLEAR,
    get noChanges() {
      return helpText('Core', 'Core_FieldAccess_NoChanges');
    },
    preview: PREVIEW,
    apply: APPLY,
    recentHeading: RECENT_HEADING,
    get noRecent() {
      return helpText('Core', 'Core_FieldAccess_NoRecent');
    },
    refresh: REFRESH,
    loading: LOADING
  };

  objectAccessOptions = [
    { label: NO_CHANGE, value: '' },
    { label: WORD_READ, value: READ },
    { label: WORD_EDIT, value: EDIT },
    { label: WORD_NONE, value: NONE }
  ];
  fieldAccessOptions = [
    { label: WORD_READ, value: READ },
    { label: WORD_EDIT, value: EDIT },
    { label: WORD_NONE, value: NONE }
  ];
  get fieldColumns() {
    return shownColumns(
      [
        text('label', COL_FIELD),
        text('name', COL_API_NAME, { technical: true }),
        text('nowText', COL_NOW),
        text('noteText', COL_NOTE, { initialWidth: 110 })
      ],
      this.showTechnicalNames
    );
  }

  get objectOptions() {
    return nameOptions(this.objectChoices, this.showTechnicalNames);
  }
  itemColumns = [
    text('objectLabel', KIND_OF_RECORD),
    text('fieldText', COL_FIELD),
    text('accessText', COL_ACCESS),
    {
      type: 'button',
      initialWidth: 110,
      typeAttributes: { label: REMOVE, name: 'remove', variant: 'base' }
    }
  ];
  previewColumns = [
    text('setLabel', COL_SET),
    text('objectLabel', KIND_OF_RECORD),
    text('fieldText', COL_FIELD),
    text('nowText', COL_NOW),
    text('afterText', COL_AFTER),
    text('whyText', COL_WHY)
  ];
  recentColumns = [
    text('whenText', COL_WHEN),
    text('byName', COL_BY),
    text('changed', COL_CHANGED, { type: 'number', initialWidth: 120 }),
    text('refused', COL_REFUSED, { type: 'number', initialWidth: 100 }),
    text('status', COL_STATUS),
    text('undoUntilText', COL_UNDO_UNTIL),
    {
      type: 'button',
      initialWidth: 100,
      typeAttributes: {
        label: UNDO,
        name: 'undo',
        variant: 'base',
        disabled: { fieldName: 'undoDisabled' }
      }
    }
  ];

  status;
  objectChoices = [];
  term = '';
  results;
  sets = [];
  objectName;
  fieldList;
  fieldFilter = '';
  ticked = [];
  objectAccess = '';
  fieldAccessChoice = EDIT;
  items = [];
  preview;
  recent = [];
  loading = false;
  errorMessage;
  noticeMessage;
  searchTimer;
  recordTimer;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.loadStatus();
  }

  disconnectedCallback() {
    clearTimeout(this.searchTimer);
    clearTimeout(this.recordTimer);
  }

  @wire(listObjects)
  wiredObjects({ data, error }) {
    if (data) {
      this.objectChoices = data;
    } else if (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  async loadStatus() {
    try {
      this.status = await getStatus();
      if (this.status.canChange) {
        await this.loadRecent();
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  async loadRecent() {
    try {
      this.recent = await listChanges();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  get canChange() {
    return Boolean(this.status && this.status.canChange);
  }

  get refusal() {
    return this.status && !this.status.canChange ? this.status.reason : undefined;
  }

  get chooseSetsText() {
    return format(
      helpText('Core', 'Core_FieldAccess_ChooseSets'),
      this.status ? this.status.maxSets : ''
    );
  }

  get resultItems() {
    return this.results || [];
  }

  get noResults() {
    return Array.isArray(this.results) && this.results.length === 0;
  }

  get setIds() {
    return this.sets.map((chosen) => chosen.id);
  }

  get noSets() {
    return this.sets.length === 0;
  }

  get shownFields() {
    if (!this.fieldList) {
      return [];
    }
    const total = this.fieldList.setCount;
    return filterFields(this.fieldList.fields, this.fieldFilter).map((field) => ({
      ...field,
      nowText: format(NOW_TEXT, field.readCount, field.editCount, total),
      noteText: field.readOnly ? READ_ONLY : ''
    }));
  }

  get addDisabled() {
    return !this.fieldList || (this.ticked.length === 0 && !this.objectAccess);
  }

  get itemRows() {
    return this.items.map((item) => ({
      ...item,
      fieldText: item.fieldLabel || WHOLE_RECORD,
      accessText: askedWord(item.access, WORDS)
    }));
  }

  get hasItems() {
    return this.items.length > 0;
  }

  get conflictMessage() {
    const labels = conflicts(this.items);
    return labels.length
      ? format(helpText('Core', 'Core_FieldAccess_Conflict'), labels.join(', '))
      : undefined;
  }

  get previewDisabled() {
    return this.loading || this.noSets || !this.hasItems || Boolean(this.conflictMessage);
  }

  get previewView() {
    if (!this.preview) {
      return undefined;
    }
    return {
      rows: previewRows(this.preview.rows, WORDS),
      summary: format(
        helpText('Core', 'Core_FieldAccess_PreviewSummary'),
        this.preview.changed,
        this.preview.setCount,
        this.preview.unchanged
      ),
      tooMany: this.preview.tooMany
        ? format(
            helpText('Core', 'Core_FieldAccess_TooManyRows'),
            this.preview.changed,
            this.preview.maxRows
          )
        : undefined,
      applyDisabled: this.loading || this.preview.tooMany || this.preview.changed === 0
    };
  }

  get recentRows() {
    return this.recent.map((job) => ({
      ...job,
      whenText: this.dateText(job.createdAt),
      undoUntilText: job.canUndo ? this.dateText(job.undoDeadline) : '',
      undoDisabled: !job.canUndo || this.loading
    }));
  }

  get hasRecent() {
    return this.recent.length > 0;
  }

  dateText(value) {
    return value ? new Intl.DateTimeFormat(undefined, DATE_TIME).format(new Date(value)) : '';
  }

  // --- Permission sets -----------------------------------------------------------------

  handleTerm(event) {
    this.term = event.target.value;
    clearTimeout(this.searchTimer);
    if ((this.term || '').trim().length < 2) {
      this.results = undefined;
      return;
    }
    const term = this.term;
    // A pause between key presses, so typing a name runs one search, not one per letter.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.searchTimer = setTimeout(() => this.search(term), SEARCH_DELAY);
  }

  async search(term) {
    try {
      const found = await searchSets({ term });
      if (term === this.term) {
        this.results = found;
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  handleChooseSet(event) {
    const id = event.target.dataset.value;
    const choice = (this.results || []).find((result) => result.id === id);
    if (!choice || this.sets.some((chosen) => chosen.id === id)) {
      return;
    }
    if (this.status && this.sets.length >= this.status.maxSets) {
      this.errorMessage = this.chooseSetsText;
      return;
    }
    this.sets = [...this.sets, { id: choice.id, label: choice.label }];
    this.term = '';
    this.results = undefined;
    this.setsChanged();
  }

  handleRemoveSet(event) {
    const id = event.target.dataset.value;
    this.sets = this.sets.filter((chosen) => chosen.id !== id);
    this.setsChanged();
  }

  setsChanged() {
    this.preview = undefined;
    this.errorMessage = undefined;
    if (this.objectName && !this.noSets) {
      this.loadFields();
    } else {
      this.fieldList = undefined;
    }
  }

  // --- Fields --------------------------------------------------------------------------

  handleObject(event) {
    this.objectName = event.detail.value;
    this.objectAccess = '';
    this.loadFields();
  }

  async loadFields() {
    this.loading = true;
    this.ticked = [];
    try {
      this.fieldList = await getFields({ objectName: this.objectName, setIds: this.setIds });
    } catch (error) {
      this.fieldList = undefined;
      this.errorMessage = messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  handleFilter(event) {
    this.fieldFilter = event.target.value;
  }

  handleTick(event) {
    this.ticked = event.detail.selectedRows.map((row) => row.name);
  }

  handleObjectAccess(event) {
    this.objectAccess = event.detail.value;
  }

  handleFieldAccess(event) {
    this.fieldAccessChoice = event.detail.value;
  }

  handleAdd() {
    const object = { name: this.fieldList.objectName, label: this.fieldList.objectLabel };
    let items = this.items;
    if (this.objectAccess) {
      items = withItems(items, object, [], this.objectAccess);
    }
    const fields = this.fieldList.fields.filter((field) => this.ticked.includes(field.name));
    if (fields.length) {
      items = withItems(items, object, fields, this.fieldAccessChoice);
    }
    this.items = items;
    this.ticked = [];
    this.objectAccess = '';
    this.preview = undefined;
    const table = this.template.querySelector('[data-id="fields"]');
    if (table) {
      table.selectedRows = [];
    }
  }

  handleItemAction(event) {
    this.items = withoutItem(this.items, event.detail.row.key);
    this.preview = undefined;
  }

  handleClear() {
    this.items = [];
    this.preview = undefined;
  }

  // --- Preview, apply, undo ------------------------------------------------------------

  get changeJson() {
    return JSON.stringify(buildChange(this.setIds, this.items));
  }

  async handlePreview() {
    this.loading = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.preview = await previewChange({ changeJson: this.changeJson });
    } catch (error) {
      this.preview = undefined;
      this.errorMessage = messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  async handleApply() {
    const count = this.preview.changed;
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: CONFIRM_TITLE,
      message: format(
        helpText('Core', 'Core_FieldAccess_ConfirmMessage'),
        count,
        this.preview.setCount
      ),
      confirmLabel: CONFIRM_BUTTON,
      cancelLabel: CANCEL
    });
    if (!confirmed) {
      return;
    }
    this.loading = true;
    this.errorMessage = undefined;
    try {
      const done = await applyChange({ changeJson: this.changeJson, confirmedCount: count });
      this.noticeMessage = format(
        helpText('Core', 'Core_FieldAccess_Applied'),
        done.changed,
        done.refused
      );
      this.errorMessage = done.failures.length ? done.failures.join(' ') : undefined;
      this.preview = undefined;
      this.items = [];
      if (this.objectName) {
        await this.loadFields();
      }
      this.recordSoon();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  /** The data job is written by a queued job just after the change: list it once it is there. */
  recordSoon() {
    clearTimeout(this.recordTimer);
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.recordTimer = setTimeout(() => this.loadRecent(), RECORD_DELAY);
  }

  async handleRecentAction(event) {
    const job = event.detail.row;
    if (!job.canUndo) {
      return;
    }
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: UNDO_TITLE,
      message: helpText('Core', 'Core_FieldAccess_UndoConfirmMessage'),
      confirmLabel: UNDO,
      cancelLabel: CANCEL
    });
    if (!confirmed) {
      return;
    }
    this.loading = true;
    this.errorMessage = undefined;
    try {
      const done = await undoChange({ jobId: job.id });
      this.noticeMessage = format(
        helpText('Core', 'Core_FieldAccess_Undone'),
        done.changed,
        done.kept,
        done.refused
      );
      this.errorMessage = done.failures.length ? done.failures.join(' ') : undefined;
      if (this.objectName && !this.noSets) {
        await this.loadFields();
      }
      this.recordSoon();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  handleRefresh() {
    this.loadRecent();
  }
}
