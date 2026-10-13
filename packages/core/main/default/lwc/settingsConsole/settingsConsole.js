import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getConsoleModel from '@salesforce/apex/SettingsController.getConsoleModel';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';
import getRecentChanges from '@salesforce/apex/SettingsController.getRecentChanges';
import TITLE from '@salesforce/label/c.Core_Settings_Title';
import SECTIONS_HEADING from '@salesforce/label/c.Core_Settings_SectionsHeading';
import SAVE_BUTTON from '@salesforce/label/c.Core_Settings_SaveButton';
import DISCARD_BUTTON from '@salesforce/label/c.Core_Settings_DiscardButton';
import SAVED_MESSAGE from '@salesforce/label/c.Core_Settings_SavedMessage';
import SAVE_ERROR from '@salesforce/label/c.Core_Settings_SaveErrorMessage';
import OUT_OF_RANGE from '@salesforce/label/c.Core_Settings_NumberOutOfRangeOnPage';
import LOAD_ERROR from '@salesforce/label/c.Core_Settings_LoadErrorMessage';
import READ_ONLY_NOTICE from '@salesforce/label/c.Core_Settings_ReadOnlyNotice';
import LEARN_MORE from '@salesforce/label/c.Core_Settings_LearnMoreLink';
import EMPTY_SECTION from '@salesforce/label/c.Core_Settings_EmptySectionMessage';
import RECENT_HEADING from '@salesforce/label/c.Core_Settings_RecentChangesHeading';
import RECENT_EMPTY from '@salesforce/label/c.Core_Settings_RecentChangesEmpty';
import COLUMN_SETTING from '@salesforce/label/c.Core_Settings_ColumnSetting';
import COLUMN_OLD from '@salesforce/label/c.Core_Settings_ColumnOldValue';
import COLUMN_NEW from '@salesforce/label/c.Core_Settings_ColumnNewValue';
import COLUMN_BY from '@salesforce/label/c.Core_Settings_ColumnChangedBy';
import COLUMN_AT from '@salesforce/label/c.Core_Settings_ColumnChangedAt';
import NOT_INSTALLED from '@salesforce/label/c.Core_Settings_ComponentNotInstalled';
import OPEN_SECTION from '@salesforce/label/c.Core_Settings_OpenSectionButton';
import TAB_LABEL from '@salesforce/label/c.Core_Console_TabLabel';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { labelTab } from 'c/workspaceTabs';

const RECENT_LIMIT = 10;
const TAB_ICON = 'standard:settings';

/** A Record Type List value, stored as developer names separated by commas, as a list. */
function splitList(text) {
  if (typeof text !== 'string' || text.trim() === '') {
    return [];
  }
  return text
    .split(',')
    .map((name) => name.trim())
    .filter((name) => name);
}

/**
 * The panels Core itself ships, each behind a literal import (ADR-0020). A dynamic specifier
 * is rejected by the platform, and Core cannot name a component from a package that depends on
 * it, so a module reaches its own settings page by navigation instead.
 */
function importCoreComponent(name) {
  switch (name) {
    case 'householdNamingSettings':
      return import('c/householdNamingSettings');
    case 'automationControl':
      return import('c/automationControl');
    case 'errorLogTile':
      return import('c/errorLogTile');
    case 'accessManager':
      return import('c/accessManager');
    case 'healthCheckPanel':
      return import('c/healthCheckPanel');
    case 'sampleDataManager':
      return import('c/sampleDataManager');
    case 'rollupDefinitions':
      return import('c/rollupDefinitions');
    case 'seasonalAddressJob':
      return import('c/seasonalAddressJob');
    case 'errorDigestJob':
      return import('c/errorDigestJob');
    case 'moduleManager':
      return import('c/moduleManager');
    case 'customMetadataManager':
      return import('c/customMetadataManager');
    default:
      return null;
  }
}

export default class SettingsConsole extends NavigationMixin(LightningElement) {
  labels = {
    title: TITLE,
    sectionsHeading: SECTIONS_HEADING,
    save: SAVE_BUTTON,
    discard: DISCARD_BUTTON,
    saved: SAVED_MESSAGE,
    saveError: SAVE_ERROR,
    outOfRange: OUT_OF_RANGE,
    loadError: LOAD_ERROR,
    readOnly: READ_ONLY_NOTICE,
    learnMore: LEARN_MORE,
    emptySection: EMPTY_SECTION,
    recentHeading: RECENT_HEADING,
    recentEmpty: RECENT_EMPTY,
    notInstalled: NOT_INSTALLED,
    openSection: OPEN_SECTION
  };

  columns = [
    { label: COLUMN_SETTING, fieldName: 'settingName', type: 'text' },
    { label: COLUMN_OLD, fieldName: 'oldValue', type: 'text' },
    { label: COLUMN_NEW, fieldName: 'newValue', type: 'text' },
    { label: COLUMN_BY, fieldName: 'changedBy', type: 'text' },
    {
      label: COLUMN_AT,
      fieldName: 'changedAt',
      type: 'date',
      typeAttributes: {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      }
    }
  ];

  sections = [];
  changes = [];
  canEdit = false;
  selectedSection;
  pending = {};
  message;
  messageIsError = false;
  loading = true;
  componentTypes = {};
  requestedSection;
  enclosingTabId;

  @wire(CurrentPageReference)
  handlePageReference(pageReference) {
    // The Setup Assistant links here with the section its step belongs to.
    const requested = pageReference && pageReference.state && pageReference.state.c__section;
    if (requested) {
      this.requestedSection = requested;
      this.selectRequestedSection();
    }
  }

  /** In a console the tab is named for the section on screen. */
  @wire(EnclosingTabId)
  wiredTabId(tabId) {
    this.enclosingTabId = tabId;
    this.nameTab();
  }

  connectedCallback() {
    this.load();
  }

  renderedCallback() {
    this.nameTab();
  }

  nameTab() {
    const label = this.selectedSection
      ? TAB_LABEL.replace('{0}', TITLE).replace('{1}', this.selectedSection)
      : TITLE;
    labelTab(this, label, TAB_ICON);
  }

  get navigationItems() {
    return this.sections.map((section) => ({
      name: section.name,
      label: section.name
    }));
  }

  get currentSection() {
    return this.sections.find((section) => section.name === this.selectedSection);
  }

  get currentSettings() {
    const section = this.currentSection;
    if (!section) {
      return [];
    }
    return section.settings.map((setting) => this.toRow(setting));
  }

  get sectionIsEmpty() {
    return !this.loading && this.currentSettings.length === 0;
  }

  get hasChangesToShow() {
    return this.changes.length > 0;
  }

  get showReadOnlyNotice() {
    return !this.loading && !this.canEdit;
  }

  get isDirty() {
    return Object.keys(this.pending).length > 0;
  }

  get saveDisabled() {
    return !this.canEdit || !this.isDirty;
  }

  get messageClass() {
    return this.messageIsError
      ? 'slds-text-color_error slds-p-vertical_x-small'
      : 'slds-text-color_success slds-p-vertical_x-small';
  }

  toRow(setting) {
    const pendingValue = this.pending[setting.key];
    const hasPending = pendingValue !== undefined;
    const isCheckbox = setting.dataType === 'Checkbox';
    return {
      ...setting,
      isCheckbox,
      isText: setting.dataType === 'Text',
      isNumber: setting.dataType === 'Number',
      isPicklist: setting.dataType === 'Picklist',
      isDateTime: setting.dataType === 'DateTime',
      isRecord: setting.dataType === 'Record',
      isRecordTypeList: setting.dataType === 'RecordTypeList',
      isComponent: setting.dataType === 'Component',
      hasHelp: Boolean(setting.helpUrl),
      disabled: !this.canEdit,
      ctor: this.componentTypes[setting.component],
      navigatesAway: setting.dataType === 'Component' && !setting.component,
      missing:
        setting.dataType === 'Component' &&
        Boolean(setting.component) &&
        !this.componentTypes[setting.component],
      checked: isCheckbox ? (hasPending ? pendingValue === true : setting.checked) : false,
      value: hasPending ? pendingValue : setting.value,
      selected: splitList(hasPending ? pendingValue : setting.value),
      // Ties the description to the control for a screen reader; ids are scoped to this template.
      descriptionId: setting.description ? `description-${setting.key}` : undefined
    };
  }

  async load() {
    this.loading = true;
    try {
      const model = await getConsoleModel();
      this.applyModel(model);
      this.message = undefined;
    } catch {
      this.messageIsError = true;
      this.message = this.labels.loadError;
    }
    this.loading = false;
    await this.loadChanges();
  }

  async loadChanges() {
    try {
      this.changes = (await getRecentChanges({ limitCount: RECENT_LIMIT })) || [];
    } catch {
      this.changes = [];
    }
  }

  applyModel(model) {
    this.sections = (model && model.sections) || [];
    this.canEdit = Boolean(model && model.canEdit);
    if (!this.selectRequestedSection() && !this.selectedSection && this.sections.length > 0) {
      this.selectedSection = this.sections[0].name;
    }
    this.loadCoreComponents();
  }

  /** Opens the section a link asked for, when the model has one by that name. */
  selectRequestedSection() {
    if (!this.requestedSection) {
      return false;
    }
    const wanted = this.requestedSection.toLowerCase();
    const match = this.sections.find((section) => section.name.toLowerCase() === wanted);
    if (!match) {
      return false;
    }
    this.selectedSection = match.name;
    return true;
  }

  loadCoreComponents() {
    this.sections.forEach((section) => {
      section.settings.forEach((setting) => {
        if (setting.component && !this.componentTypes[setting.component]) {
          this.loadCoreComponent(setting.component);
        }
      });
    });
  }

  async loadCoreComponent(name) {
    const pending = importCoreComponent(name);
    if (!pending) {
      return;
    }
    try {
      const module = await pending;
      this.componentTypes = { ...this.componentTypes, [name]: module.default };
    } catch {
      // The module that ships this panel is not installed, so the row says so.
      this.componentTypes = { ...this.componentTypes };
    }
  }

  /** Opens a module's own settings page, which lives on its own tab (ADR-0020). */
  handleOpenSection(event) {
    const target = event.currentTarget.dataset.target;
    if (!target) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: target }
    });
  }

  handleSectionSelect(event) {
    this.selectedSection = event.detail.name;
  }

  handleSearchSelect(event) {
    if (event.detail && event.detail.section) {
      this.selectedSection = event.detail.section;
    }
  }

  handleChange(event) {
    const key = event.target.dataset.key;
    const kind = event.target.dataset.kind;
    let value;
    if (kind === 'Checkbox') {
      value = event.target.checked;
    } else if (kind === 'Picklist') {
      value = event.detail.value;
    } else if (kind === 'Record') {
      value = event.detail.recordId || '';
    } else if (kind === 'RecordTypeList') {
      value = (event.detail.value || []).join(',');
    } else {
      value = event.target.value;
    }
    this.pending = { ...this.pending, [key]: value };
    this.message = undefined;
  }

  handleDiscard() {
    this.pending = {};
    this.message = undefined;
  }

  async handleSave() {
    if (!this.canEdit || !this.isDirty) {
      return;
    }
    // A number outside its range is marked on the box and nothing is sent (ADMIN-27); the
    // server refuses it too, for anyone who saves another way.
    const numbers = Array.from(
      this.template.querySelectorAll('lightning-input[data-kind="Number"]')
    );
    const invalid = numbers.filter((input) => input.reportValidity() === false);
    if (invalid.length > 0) {
      this.messageIsError = true;
      this.message = this.labels.outOfRange;
      return;
    }
    const values = { ...this.pending };
    try {
      const model = await saveSettings({ values });
      this.applyModel(model);
      this.pending = {};
      this.messageIsError = false;
      this.message = this.labels.saved;
      await this.loadChanges();
    } catch (error) {
      this.messageIsError = true;
      this.message = this.readError(error) || this.labels.saveError;
    }
  }

  readError(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return undefined;
  }
}
