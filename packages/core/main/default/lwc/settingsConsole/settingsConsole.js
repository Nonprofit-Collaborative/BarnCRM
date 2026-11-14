import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getConsoleModel from '@salesforce/apex/SettingsController.getConsoleModel';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';
import getRecentChanges from '@salesforce/apex/SettingsController.getRecentChanges';
import getSettingsLink from '@salesforce/apex/SettingsController.getSettingsLink';
import TITLE from '@salesforce/label/c.Core_Settings_Title';
import NOT_SET from '@salesforce/label/c.Core_Settings_NotSet';
import SECTIONS_HEADING from '@salesforce/label/c.Core_Settings_SectionsHeading';
import HELP_ARIA from '@salesforce/label/c.Core_Settings_HelpAria';
import RECENT_HEADING from '@salesforce/label/c.Core_Settings_RecentChangesHeading';
import COLUMN_SETTING from '@salesforce/label/c.Core_Settings_ColumnSetting';
import COLUMN_OLD from '@salesforce/label/c.Core_Settings_ColumnOldValue';
import COLUMN_NEW from '@salesforce/label/c.Core_SuperTransform_NewValue';
import COLUMN_BY from '@salesforce/label/c.Core_SetupChanges_ColChangedBy';
import COLUMN_AT from '@salesforce/label/c.Core_SetupChanges_ColChangedAt';
import OPEN_IN_SETUP from '@salesforce/label/c.Core_SetupNote_OpenInSetup';
import NEW_TAB from '@salesforce/label/c.Core_Kit_NewTab';
import { setupValuePath } from 'c/setupLinks';
import OPEN_SECTION from '@salesforce/label/c.Core_Settings_OpenSectionButton';
import OPEN_NAMED from '@salesforce/label/c.Core_Settings_OpenNamedButton';
import FEEDBACK_LINK from '@salesforce/label/c.Core_Settings_FeedbackLink';
import FEEDBACK_ARIA from '@salesforce/label/c.Core_Settings_FeedbackAria';
import FEEDBACK_URL from '@salesforce/label/c.Core_Settings_FeedbackUrl';
import DEFAULT_BADGE from '@salesforce/label/c.Core_Settings_DefaultBadge';
import DEFAULTS_TITLE from '@salesforce/label/c.Core_Settings_DefaultsBannerTitle';
import KEEP_ALL_DEFAULTS from '@salesforce/label/c.Core_Settings_KeepAllDefaults';
import KEEP_DEFAULT from '@salesforce/label/c.Core_Settings_KeepDefaultButton';
import KEEP_DEFAULT_ARIA from '@salesforce/label/c.Core_Settings_KeepDefaultAria';
import USE_SUGGESTION from '@salesforce/label/c.Core_Settings_UseSuggestion';
import USE_SUGGESTION_ARIA from '@salesforce/label/c.Core_Settings_UseSuggestionAria';
import TAB_LABEL from '@salesforce/label/c.Core_Format_Pair';
import SECTION from '@salesforce/label/c.Core_SetupChanges_ColSection';
import SAVES_ON_ITS_OWN from '@salesforce/label/c.Core_Settings_SavesOnItsOwn';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { labelTab } from 'c/workspaceTabs';
import { groupRows, findBox } from './settingsGroups';
import { navigationGroups, openPageReference } from './settingsNavigation';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/** The page state key a link to a section uses: `c__section`, or the namespace's. */
const SECTION_STATE = '__section';
const RECENT_LIMIT = 10;
/** The stored name of the General section (SettingSections.GENERAL), not a display label. */
const GENERAL_SECTION = 'General';
/** The stored name of the Integrations section: a read-only page with nothing to save. */
const INTEGRATIONS_SECTION = 'Integrations';

// The three household naming patterns are edited in the naming panel (a Component row), which
// saves them. Their plain rows are hidden while that panel is in the section so a pattern has
// one editor (ADMIN-11). The settings and their definitions stay; search still finds them and
// lands on the panel. The six organization address parts are handled the same way by the
// address panel.
const PANEL_SETTINGS = {
  householdNamingSettings: [
    'Household_Name_Pattern__c',
    'Formal_Greeting_Pattern__c',
    'Informal_Greeting_Pattern__c'
  ],
  organizationAddressSettings: [
    'Organization_Street__c',
    'Organization_Street_2__c',
    'Organization_City__c',
    'Organization_State__c',
    'Organization_Postal_Code__c',
    'Organization_Country__c'
  ]
};

/** The panel row that edits this setting, when its section shows that panel. */
function panelRowFor(section, key) {
  const component = Object.keys(PANEL_SETTINGS).find((name) => PANEL_SETTINGS[name].includes(key));
  return component
    ? section.settings.find((setting) => setting.component === component)
    : undefined;
}

/** True for a setting row whose section also shows the panel that edits it. */
function isHiddenPanelSetting(section, setting) {
  return Boolean(panelRowFor(section, setting.key));
}
const TAB_ICON = 'standard:settings';

/**
 * Rows that open a tool's one home in Org Optimizer (admin-14), by setting key: the section of
 * the Org Optimizer tab each opens, passed as page state.
 */
const OPTIMIZER_SECTIONS = {
  Health_Check_Optimizer_Link: 'healthCheck',
  Error_Log_Optimizer_Link: 'errors'
};

/** Panels that save nothing: they get no "Saves on its own" cue (admin-18). */
const READ_ONLY_PANELS = ['integrationsPanel'];

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
    case 'nightlyJobsPanel':
      return import('c/nightlyJobsPanel');
    case 'moduleManager':
      return import('c/moduleManager');
    case 'customMetadataManager':
      return import('c/customMetadataManager');
    case 'editionSetting':
      return import('c/editionSetting');
    case 'featureSettings':
      return import('c/featureSettings');
    case 'organizationAddressSettings':
      return import('c/organizationAddressSettings');
    case 'integrationsPanel':
      return import('c/integrationsPanel');
    case 'importFieldConnection':
      return import('c/importFieldConnection');
    case 'npspHouseholdAdoption':
      return import('c/npspHouseholdAdoption');
    case 'npcHouseholdConversion':
      return import('c/npcHouseholdConversion');
    default:
      return null;
  }
}

export default class SettingsConsole extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  labels = {
    title: TITLE,
    sectionsHeading: SECTIONS_HEADING,
    get purpose() {
      return helpText('Core', 'Core_Settings_Purpose');
    },
    get saved() {
      return helpText('Core', 'Core_Settings_SavedMessage');
    },
    get saveError() {
      return helpText('Core', 'Core_Settings_SaveErrorMessage');
    },
    get outOfRange() {
      return helpText('Core', 'Core_Settings_NumberOutOfRangeOnPage');
    },
    get loadError() {
      return helpText('Core', 'Core_Settings_LoadErrorMessage');
    },
    get readOnly() {
      return helpText('Core', 'Core_Settings_ReadOnlyNotice');
    },
    get emptySection() {
      return helpText('Core', 'Core_Settings_EmptySectionMessage');
    },
    recentHeading: RECENT_HEADING,
    get recentEmpty() {
      return helpText('Core', 'Core_Settings_RecentChangesEmpty');
    },
    get notInstalled() {
      return helpText('Core', 'Core_Settings_ComponentNotInstalled');
    },
    get fromSetupHelp() {
      return helpText('Core', 'Core_Settings_FromSetupHelp');
    },
    openInSetup: OPEN_IN_SETUP,
    newTab: NEW_TAB,
    feedbackLink: FEEDBACK_LINK,
    feedbackAria: FEEDBACK_ARIA,
    feedbackUrl: FEEDBACK_URL,
    defaultBadge: DEFAULT_BADGE,
    defaultsTitle: DEFAULTS_TITLE,
    get defaultsText() {
      return helpText('Core', 'Core_Settings_DefaultsBannerText');
    },
    keepAllDefaults: KEEP_ALL_DEFAULTS,
    keepDefault: KEEP_DEFAULT,
    useSuggestion: USE_SUGGESTION,
    section: SECTION,
    savesOnItsOwn: SAVES_ON_ITS_OWN
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
   * No longer used: the console always shows every module's rows. The property stays declared
   * because the platform refuses to remove a page property from a component that any Lightning
   * page in the org places, so an org that had the old module settings pages could not take an
   * upgrade without it. Any value set is ignored.
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
  saving = false;
  componentTypes = {};
  requestedSection;
  enclosingTabId;
  focusKey;
  /** The box a link named (P1), scrolled to once its page has rendered. */
  focusBox;
  boxRequestHandled = false;
  /** Set when a section is chosen in the Section box, so its heading takes focus. */
  focusSectionHeading = false;

  @wire(CurrentPageReference)
  handlePageReference(pageReference) {
    // The Setup Assistant links here with the section its step belongs to.
    const state = (pageReference && pageReference.state) || {};
    const key = Object.keys(state).find((name) => name.endsWith(SECTION_STATE));
    const requested = key && state[key];
    if (requested) {
      this.requestedSection = requested;
      this.boxRequestHandled = false;
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
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  renderedCallback() {
    this.nameTab();
    this.focusChosenSetting();
    this.scrollToChosenBox();
    this.focusFirstHeading();
  }

  nameTab() {
    const label = this.selectedSection
      ? TAB_LABEL.replace('{0}', TITLE).replace('{1}', this.selectedSection)
      : TITLE;
    labelTab(this, label, TAB_ICON);
  }

  /** The section list in short groups, each section with its icon, Error Log last. */
  get navigationGroups() {
    return navigationGroups(this.sections.map((section) => section.name));
  }

  /** The same sections, in the same order, for the Section box on a narrow screen (admin-19). */
  get sectionOptions() {
    const options = [];
    this.navigationGroups.forEach((group) => {
      group.items.forEach((item) => options.push({ label: item.label, value: item.name }));
    });
    return options;
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
      .filter((setting) => !isHiddenPanelSetting(section, setting))
      .map((setting) => this.toRow(setting));
  }

  /**
   * The page's rows in boxed sub-sections (P1), each with a heading in title case. A panel alone
   * in a box named like it keeps its heading for search and focus, hidden so the title does
   * not show twice.
   */
  get currentGroups() {
    return groupRows(this.selectedSection, this.currentSettings).map((box, index) => ({
      ...box,
      headingId: `settings-box-${index}`,
      rows: box.rows.map((row) => ({
        ...row,
        headingClass:
          box.rows.length === 1 && String(row.label).toLowerCase() === box.label.toLowerCase()
            ? 'slds-assistive-text'
            : 'slds-text-heading_small slds-var-m-bottom_x-small'
      }))
    }));
  }

  get sectionIsEmpty() {
    return !this.loading && this.currentSettings.length === 0;
  }

  /** Recent Changes shows on the General section only, however the section was reached. */
  get showRecentChanges() {
    return this.selectedSection === GENERAL_SECTION;
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

  /** Save and Discard Changes show to editors, except on the Integrations page. */
  get showSaveBar() {
    return this.canEdit && this.selectedSection !== INTEGRATIONS_SECTION;
  }

  /** How many settings have unsaved edits, in any section: the save bar's count. */
  get dirtyCount() {
    return Object.keys(this.pending).length;
  }

  /**
   * What the save bar covers, in words (admin-18): the unsaved rows of the section on screen,
   * and those left in other sections, which Save sends too. Panels never count.
   */
  get saveBarText() {
    const section = this.currentSection;
    const keys = section ? section.settings.map((setting) => setting.key) : [];
    const pendingKeys = Object.keys(this.pending);
    const here = pendingKeys.filter((key) => keys.includes(key)).length;
    const elsewhere = pendingKeys.length - here;
    if (elsewhere > 0) {
      return helpText('Core', 'Core_Settings_UnsavedInSections', here, elsewhere);
    }
    return here === 1
      ? helpText('Core', 'Core_Settings_UnsavedOneInSection')
      : helpText('Core', 'Core_Settings_UnsavedInSection', here);
  }

  /** The section's rows that show a default nobody saved. */
  get unsavedDefaultRows() {
    return this.currentSettings.filter((row) => row.showsUnsavedDefault);
  }

  get hasUnsavedDefaults() {
    return !this.loading && this.unsavedDefaultRows.length > 0;
  }

  get canKeepAllDefaults() {
    return this.unsavedDefaultRows.some((row) => row.canKeepDefault);
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
    // A default nobody saved, still on screen: the admin can keep it as a saved choice (RM1).
    const showsUnsavedDefault = Boolean(setting.unsavedDefault) && !hasPending;
    return {
      ...setting,
      isCheckbox,
      isText: setting.dataType === 'Text',
      isNumber: setting.dataType === 'Number',
      // A Record Type row is one choice from a list, so it is the same dropdown (ADR-0141).
      // A Picklist From Field row is the same dropdown, of a field's active values; while the
      // org lacks the field the server sends it as Text.
      isPicklist:
        setting.dataType === 'Picklist' ||
        setting.dataType === 'RecordType' ||
        setting.dataType === 'PicklistFromField',
      isDateTime: setting.dataType === 'DateTime',
      // A blank date and time is never an empty box with nothing said: it reads "Not set", and
      // the row's description says what that means for it.
      blankDateTime:
        setting.dataType === 'DateTime' && !(hasPending ? pendingValue : setting.value),
      blankText: setting.defaultText || NOT_SET,
      isRecord: setting.dataType === 'Record',
      // A Field List is the same checkbox list, of an object's fields (R-AD10).
      isRecordTypeList: setting.dataType === 'RecordTypeList' || setting.dataType === 'FieldList',
      isComponent: setting.dataType === 'Component',
      // A value Setup holds: shown read only, never saved (ADR-0135).
      isSetupValue: setting.dataType === 'SetupValue',
      // The Setup page that changes it, opened in a new tab (D-137).
      setupUrl: setting.dataType === 'SetupValue' ? setupValuePath(setting.key) : undefined,
      // The description sits behind an info icon, with Learn More beside it (UX PR 6).
      hasHelpContent: Boolean(setting.description || setting.helpUrl),
      showsHelpLine: Boolean(setting.description || setting.helpUrl || showsUnsavedDefault),
      // What a blank Text row means, shown in its empty box (never a value to keep).
      placeholder: setting.defaultText || undefined,
      // Company Information's value for a blank row, offered to fill in until it is saved.
      showsSuggestion: Boolean(setting.suggestedValue) && this.canEdit && !hasPending,
      suggestionText: helpText('Core', 'Core_Settings_CompanySuggestion').replace(
        '{0}',
        setting.suggestedValue || ''
      ),
      useSuggestionLabel: USE_SUGGESTION_ARIA.replace('{0}', setting.label),
      helpLabel: HELP_ARIA.replace('{0}', setting.label),
      disabled: !this.canEdit,
      ctor: this.componentTypes[setting.component],
      navigatesAway: setting.dataType === 'Component' && !setting.component,
      navigationSection: OPTIMIZER_SECTIONS[setting.key],
      savesOnItsOwn:
        Boolean(this.componentTypes[setting.component]) &&
        !READ_ONLY_PANELS.includes(setting.component),
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
      showsUnsavedDefault,
      // No one-click keep for a default BarnCRM's detection would replace (a Person Account org's
      // household membership): the admin chooses it by hand instead.
      // Nor for a blank that only says what it means ("Not set"): there is no value to keep.
      canKeepDefault:
        showsUnsavedDefault && this.canEdit && !setting.detectionMayChange && !setting.defaultText,
      keepDefaultLabel: KEEP_DEFAULT_ARIA.replace('{0}', setting.label)
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

  /**
   * Opens the section a link asked for, when the model has one by that name. A link may name a
   * box instead (P1), such as Households or Relationships, which were pages until they were
   * merged into People and Households: its page opens, scrolled to that box once per link.
   */
  selectRequestedSection() {
    if (!this.requestedSection) {
      return false;
    }
    const wanted = this.requestedSection.toLowerCase();
    const match = this.sections.find((section) => section.name.toLowerCase() === wanted);
    if (match) {
      this.selectedSection = match.name;
      return true;
    }
    const target = findBox(
      this.sections.map((section) => section.name),
      this.requestedSection
    );
    if (!target) {
      return false;
    }
    this.selectedSection = target.page;
    if (!this.boxRequestHandled) {
      this.boxRequestHandled = true;
      this.focusBox = target.box;
    }
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

  /**
   * Opens a module's own settings page, which lives on its own tab (ADR-0020), or a tool's one
   * home in Org Optimizer at its section (admin-14), with the state key qualified in Apex. A
   * target that is an object (Form__c) opens that object's tab, where its records are set up.
   */
  async handleOpenSection(event) {
    const { target, section } = event.currentTarget.dataset;
    if (!target) {
      return;
    }
    const pageReference = openPageReference(target);
    if (section) {
      try {
        const link = await getSettingsLink();
        pageReference.state = { [link.sectionKey]: section };
      } catch {
        // Without the key the tab still opens, on its overview.
      }
    }
    this[NavigationMixin.Navigate](pageReference);
  }

  handleSectionSelect(event) {
    this.selectedSection = event.detail.name;
  }

  /** A section chosen in the Section box: focus moves to its first heading (admin-19). */
  handleSectionPick(event) {
    this.selectedSection = event.detail.value;
    this.focusSectionHeading = true;
  }

  /** Moves focus to the open section's first box heading once it has rendered. */
  focusFirstHeading() {
    if (!this.focusSectionHeading) {
      return;
    }
    const heading = this.template.querySelector('section[data-box] h2');
    if (heading && typeof heading.focus === 'function') {
      this.focusSectionHeading = false;
      heading.focus();
    }
  }

  /** First-run setup finished (ADR-0124): the edition and features changed what shows. */
  handleSetupFinished() {
    this.reloadAndRefreshPanels();
  }

  /**
   * Reloads the rows, then asks each panel that stayed mounted to re-read its own data. A panel
   * fetches once when it connects and the same instance survives a reload, so without this the
   * Edition row kept saying "Not chosen yet" until the browser page was refreshed.
   */
  async reloadAndRefreshPanels() {
    await this.load();
    this.refreshPanels();
  }

  /**
   * Asks each mounted panel that can re-read its own data to do so. Also run after a save,
   * since a saved setting can change what a panel shows (the Seasonal Addresses switch
   * schedules or stops the swap the panel below it reports on).
   */
  refreshPanels() {
    this.template.querySelectorAll('[data-panel]').forEach((panel) => {
      if (typeof panel.refresh === 'function') {
        panel.refresh();
      }
    });
  }

  /** A feature turned on in General (ADR-0124): its settings rows now show, without a reload. */
  handleFeatureTurnedOn() {
    this.load();
  }

  /** A panel saved its own settings (the organization address): Recent changes now lists them. */
  handleSettingsSaved() {
    this.loadChanges();
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

  /** A setting hidden behind a panel is found on that panel, so a search for it lands there. */
  visibleKeyFor(sectionName, key) {
    const section = this.sections.find((candidate) => candidate.name === sectionName);
    const panel = section && panelRowFor(section, key);
    return panel ? panel.key : key;
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

  /** Scrolls to the box a link named and moves focus to its heading, once it has rendered. */
  scrollToChosenBox() {
    if (!this.focusBox) {
      return;
    }
    const box = Array.from(this.template.querySelectorAll('[data-box]')).find(
      (candidate) => candidate.dataset.box === this.focusBox
    );
    if (!box) {
      return;
    }
    this.focusBox = undefined;
    if (typeof box.scrollIntoView === 'function') {
      box.scrollIntoView({ block: 'start' });
    }
    const heading = box.querySelector('h2');
    if (heading && typeof heading.focus === 'function') {
      heading.focus();
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
    await this.send({ ...this.pending });
  }

  /**
   * Keeps the default a row shows as a saved choice (RM1): the shown value goes through the
   * same save as a value chosen by hand, so the permission, validation, change history and
   * any follow-on work are the same. Other unsaved edits stay on the page.
   */
  async handleKeepDefault(event) {
    const key = event.currentTarget.dataset.keep;
    const section = this.currentSection;
    const setting = section && section.settings.find((candidate) => candidate.key === key);
    if (
      !this.canEdit ||
      !setting ||
      !setting.unsavedDefault ||
      setting.detectionMayChange ||
      setting.defaultText
    ) {
      return;
    }
    await this.send({ [key]: setting.value });
  }

  /**
   * Fills a blank row with Company Information's value as an unsaved edit, so it is saved (or
   * discarded) with the save bar like any value typed by hand.
   */
  handleUseSuggestion(event) {
    const key = event.currentTarget.dataset.suggest;
    const section = this.currentSection;
    const setting = section && section.settings.find((candidate) => candidate.key === key);
    if (!this.canEdit || !setting || !setting.suggestedValue) {
      return;
    }
    this.pending = { ...this.pending, [key]: setting.suggestedValue };
    this.message = undefined;
  }

  /**
   * Keeps every default the section shows in one save, each exactly as shown, through the same
   * save as Keep This Setting. A row with an unsaved edit, or whose default detection may
   * replace, is left alone.
   */
  async handleKeepAllDefaults() {
    const values = {};
    this.unsavedDefaultRows
      .filter((row) => row.canKeepDefault)
      .forEach((row) => {
        values[row.key] = row.value;
      });
    if (!this.canEdit || Object.keys(values).length === 0) {
      return;
    }
    await this.send(values);
  }

  /** Saves the given values, then leaves on the page only the edits that were not sent. */
  async send(values) {
    this.saving = true;
    try {
      const model = await saveSettings({ values });
      this.applyModel(model);
      const remaining = { ...this.pending };
      Object.keys(values).forEach((key) => delete remaining[key]);
      this.pending = remaining;
      this.messageIsError = false;
      this.message = this.labels.saved;
      this.refreshPanels();
      await this.loadChanges();
    } catch (error) {
      this.messageIsError = true;
      this.message = this.readError(error) || this.labels.saveError;
    } finally {
      this.saving = false;
    }
  }

  readError(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return undefined;
  }
}
