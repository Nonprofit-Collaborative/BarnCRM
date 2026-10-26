import { LightningElement, api, wire } from 'lwc';
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
import LEARN_MORE_ARIA from '@salesforce/label/c.Core_Settings_LearnMoreAria';
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
import OPEN_NAMED from '@salesforce/label/c.Core_Settings_OpenNamedButton';
import FEEDBACK_LINK from '@salesforce/label/c.Core_Settings_FeedbackLink';
import FEEDBACK_ARIA from '@salesforce/label/c.Core_Settings_FeedbackAria';
import FEEDBACK_URL from '@salesforce/label/c.Core_Settings_FeedbackUrl';
import TAB_LABEL from '@salesforce/label/c.Core_Console_TabLabel';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { labelTab } from 'c/workspaceTabs';

/** The page state key a link to a section uses: `c__section`, or the namespace's. */
const SECTION_STATE = '__section';
const RECENT_LIMIT = 10;

// The three household naming patterns are edited in the naming panel (a Component row), which
// saves them. Their plain rows are hidden while that panel is in the section so a pattern has
// one editor (ADMIN-11). The settings and their definitions stay; search still finds them and
// lands on the panel.
const NAMING_PANEL_COMPONENT = 'householdNamingSettings';
const NAMING_PATTERN_KEYS = [
  'Household_Name_Pattern__c',
  'Formal_Greeting_Pattern__c',
  'Informal_Greeting_Pattern__c'
];

/** The panel row of a section, when it has one. */
function namingPanelRow(section) {
  return section.settings.find((setting) => setting.component === NAMING_PANEL_COMPONENT);
}

/** True for a naming pattern row whose section also shows the naming panel. */
function isHiddenNamingPattern(section, setting) {
  return NAMING_PATTERN_KEYS.includes(setting.key) && Boolean(namingPanelRow(section));
}
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
    case 'seasonalAddressJob':
      return import('c/seasonalAddressJob');
    case 'errorDigestJob':
      return import('c/errorDigestJob');
    case 'moduleManager':
      return import('c/moduleManager');
    case 'customMetadataManager':
      return import('c/customMetadataManager');
    case 'editionSetting':
      return import('c/editionSetting');
    case 'featureSettings':
      return import('c/featureSettings');
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
    feedbackLink: FEEDBACK_LINK,
    feedbackAria: FEEDBACK_ARIA,
    feedbackUrl: FEEDBACK_URL
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

  /**
   * A module key (Rollups, for example) set on a module's own settings page: the console then
   * shows only that module's rows, and no search, which looks across every module. Blank on
   * BarnCRM Settings, which shows everything.
   */
  @api module;

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
  focusKey;

  @wire(CurrentPageReference)
  handlePageReference(pageReference) {
    // The Setup Assistant links here with the section its step belongs to.
    const state = (pageReference && pageReference.state) || {};
    const key = Object.keys(state).find((name) => name.endsWith(SECTION_STATE));
    const requested = key && state[key];
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
    this.focusChosenSetting();
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
    return section.settings
      .filter((setting) => !isHiddenNamingPattern(section, setting))
      .map((setting) => this.toRow(setting));
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
      learnMoreLabel: LEARN_MORE_ARIA.replace('{0}', setting.label),
      disabled: !this.canEdit,
      ctor: this.componentTypes[setting.component],
      navigatesAway: setting.dataType === 'Component' && !setting.component,
      // The button names its destination ("Open Rollup Builder"), else the generic wording.
      openLabel: setting.navigationLabel
        ? OPEN_NAMED.replace('{0}', setting.navigationLabel)
        : OPEN_SECTION,
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

  /** False on a module's own page, where a search hit could name a section it does not show. */
  get showSearch() {
    return !this.module;
  }

  /** The sections to show: all of them, or only a module's rows when `module` is set. */
  forModule(sections) {
    if (!this.module) {
      return sections;
    }
    const wanted = this.module.trim().toLowerCase();
    return sections
      .map((section) => ({
        ...section,
        settings: (section.settings || []).filter(
          (setting) => (setting.module || '').toLowerCase() === wanted
        )
      }))
      .filter((section) => section.settings.length > 0);
  }

  applyModel(model) {
    this.sections = this.forModule((model && model.sections) || []);
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

  /** First-run setup finished (ADR-0124): the edition and features changed what shows. */
  handleSetupFinished() {
    this.load();
  }

  /** A feature turned on in General (ADR-0124): its settings rows now show, without a reload. */
  handleFeatureTurnedOn() {
    this.load();
  }

  handleSearchSelect(event) {
    if (event.detail && event.detail.section) {
      const sameSection = this.selectedSection === event.detail.section;
      this.selectedSection = event.detail.section;
      this.focusKey = this.visibleKeyFor(event.detail.section, event.detail.key);
      if (sameSection) {
        // Nothing re-renders when the section is already open, so go to the row now.
        this.focusChosenSetting();
      }
    }
  }

  /** A hidden naming pattern is found on the naming panel, so a search for it lands there. */
  visibleKeyFor(sectionName, key) {
    const section = this.sections.find((candidate) => candidate.name === sectionName);
    if (!section || !isHiddenNamingPattern(section, { key })) {
      return key;
    }
    return namingPanelRow(section).key;
  }

  // The admin guide says a search result takes you to the setting, not just its section, so
  // once the section has rendered the chosen row is scrolled to and focused (ADMIN-21).
  focusChosenSetting() {
    if (!this.focusKey) {
      return;
    }
    const key = this.focusKey;
    const row = Array.from(this.template.querySelectorAll('[data-key]')).find(
      (candidate) => candidate.dataset.key === key
    );
    if (!row) {
      return;
    }
    this.focusKey = undefined;
    if (typeof row.scrollIntoView === 'function') {
      row.scrollIntoView({ block: 'center' });
    }
    if (typeof row.focus === 'function') {
      row.focus();
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
