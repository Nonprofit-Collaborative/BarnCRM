import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import canFind from '@salesforce/customPermission/Find_And_Export_Records';
import getErrorTile from '@salesforce/apex/ErrorLogController.getTile';
import getLastRun from '@salesforce/apex/HealthCheckController.getLastRun';
import { healthCheckBadge } from 'c/healthCheckBadge';

import TITLE from '@salesforce/label/c.Core_OrgOptimizer_Title';
import OVERVIEW from '@salesforce/label/c.Core_OrgOptimizer_Overview';
import GROUP_DATA from '@salesforce/label/c.Core_OrgOptimizer_GroupData';
import GROUP_SETUP from '@salesforce/label/c.Core_OrgOptimizer_GroupSetup';
import QUALITY from '@salesforce/label/c.Core_DataHygiene_PageTitle';
import FIELD_UTILIZATION from '@salesforce/label/c.Core_FieldUtilization_PageTitle';
import DATA_DICTIONARY from '@salesforce/label/c.Core_DataDictionary_PageTitle';
import ACCESS_EXPLORER from '@salesforce/label/c.Core_AccessExplorer_Title';
import AI_EXPORT from '@salesforce/label/c.Core_OrgOptimizer_AiExport';
import HEALTH_CHECK from '@salesforce/label/c.Core_HealthCheck_Title';
import ERRORS from '@salesforce/label/c.Core_OrgOptimizer_Errors';
import STORAGE from '@salesforce/label/c.Core_OrgOptimizer_Storage';
import SETUP from '@salesforce/label/c.Core_OrgOptimizer_Setup';
import SETUP_CHANGES from '@salesforce/label/c.Core_SetupChanges_Title';
import RUN_HEALTH_CHECK from '@salesforce/label/c.Core_OrgOptimizer_RunHealthCheck';
import HEALTH_CHECK_NOT_RUN from '@salesforce/label/c.Core_OrgOptimizer_HealthCheckNotRunHeading';
import BADGE_ALL_CLEAR from '@salesforce/label/c.Core_OrgOptimizer_BadgeAllClear';
import BADGE_NEW from '@salesforce/label/c.Core_OrgOptimizer_BadgeNew';
import BADGE_NEED_ATTENTION from '@salesforce/label/c.Core_OrgOptimizer_BadgeNeedAttention';
import BADGE_DATA_STORAGE from '@salesforce/label/c.Core_OrgOptimizer_BadgeDataStorage';
import SHOW from '@salesforce/label/c.Core_DataJobs_Show';
import SECTIONS from '@salesforce/label/c.Core_Settings_SectionsHeading';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

const OVERVIEW_TAB = 'overview';
/**
 * The page state key that names a section to open: `c__section`, or `<namespace>__section` once
 * BarnCRM has a namespace (NamespaceUtil.stateKey('section') in Apex), so no prefix is written
 * here. Values are the section names, for example `healthCheck` or `errors` (admin-14).
 */
const SECTION_STATE_KEY = /(^|__)section$/;
const LEARN_MORE_URL =
  'https://github.com/Nonprofit-Collaborative/BarnCRM/blob/main/docs/admin-guide/org-optimizer.md';
/** Storage use at or above these percentages is shown in warning and error colors. */
const STORAGE_WARNING = 80;
const STORAGE_ERROR = 95;

function badge(label, variant) {
  return { badgeLabel: label, badgeVariant: variant };
}

/**
 * The Org Optimizer page (ADR-0103 org-optimizer-and-data-manager-pages, admin guide
 * org-optimizer.md), on the UX kit (D-140): a page shell, an Overview of tool tiles, and one
 * section per tool, chosen from the same vertical navigation with icons as BarnCRM Settings
 * (vis-core-14), or from a Show box under medium width (admin-19); after a choice the focus
 * moves to the section. A link opens a section by page state (`c__section=healthCheck`,
 * admin-14). A section's component is created only when it is first opened, and stays,
 * and Health Check never runs on open, so opening the page runs no check (core review ADMIN-7).
 * The Health Check section shows the same stored last run the tile badges (date, counts and
 * Run Again), or Not Run Yet with Run Health Check when there is none, so the tile and the
 * section always agree (owner QA, 2026-10-31). Tile badges show only what is already known: the unread error count and the last
 * Health Check run (two small reads, administrators only), and the Data Quality and Storage
 * results once those sections have reported them. Data Quality needs Find and Export Records;
 * the other sections need Manage BarnCRM Settings. Each embedded component keeps its own server
 * check. Duplicates moved to the Duplicate Matching tab (ADR-0139).
 */
export default class OrgOptimizer extends LightningElement {
  helpReady = isHelpLoaded('Core');

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Core', 'Core_OrgOptimizer_Intro');
    },
    get helpText() {
      return helpText('Core', 'Core_OrgOptimizer_HelpText');
    },
    overview: OVERVIEW,
    quality: QUALITY,
    fieldUtilization: FIELD_UTILIZATION,
    dataDictionary: DATA_DICTIONARY,
    accessExplorer: ACCESS_EXPLORER,
    aiExport: AI_EXPORT,
    healthCheck: HEALTH_CHECK,
    errors: ERRORS,
    storage: STORAGE,
    setup: SETUP,
    setupChanges: SETUP_CHANGES,
    runHealthCheck: RUN_HEALTH_CHECK,
    get healthCheckIntro() {
      return helpText('Core', 'Core_OrgOptimizer_HealthCheckIntro');
    },
    healthCheckNotRun: HEALTH_CHECK_NOT_RUN,
    show: SHOW,
    sections: SECTIONS
  };

  learnMoreUrl = LEARN_MORE_URL;
  activeSection = OVERVIEW_TAB;
  /** The sections opened so far; a section stays loaded once opened. */
  opened = {};
  healthCheckRequested = false;
  /** Set when the person chose a section, so the next render moves the focus to it. */
  focusPending = false;
  /** The stored last Health Check run (getLastRun), once read. */
  lastRun;
  /** Tile badges by section name, each { badgeLabel, badgeVariant }. */
  badges = {};

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    if (canManageSettings) {
      this.readErrorBadge();
      this.readHealthCheckBadge();
    }
  }

  get canSeeQuality() {
    return Boolean(canFind);
  }

  get isAdmin() {
    return Boolean(canManageSettings);
  }

  /** The Overview's tiles, grouped, for the sections the person may open. */
  get overviewGroups() {
    const dataTiles = [];
    if (canFind) {
      dataTiles.push(
        this.tile(
          'quality',
          QUALITY,
          helpText('Core', 'Core_OrgOptimizer_QualityText'),
          'standard:data_integration_hub'
        )
      );
    }
    const setupTiles = [];
    if (canManageSettings) {
      dataTiles.push(
        this.tile(
          'fieldUtilization',
          FIELD_UTILIZATION,
          helpText('Core', 'Core_OrgOptimizer_FieldUtilizationText'),
          'standard:metrics'
        )
      );
      dataTiles.push(
        this.tile(
          'dataDictionary',
          DATA_DICTIONARY,
          helpText('Core', 'Core_OrgOptimizer_DataDictionaryText'),
          'standard:article'
        )
      );
      dataTiles.push(
        this.tile(
          'aiExport',
          AI_EXPORT,
          helpText('Core', 'Core_OrgOptimizer_AiExportText'),
          'standard:data_mapping'
        )
      );
      setupTiles.push(
        this.tile(
          'healthCheck',
          HEALTH_CHECK,
          helpText('Core', 'Core_OrgOptimizer_HealthCheckText'),
          'standard:approval'
        ),
        this.tile(
          'errors',
          ERRORS,
          helpText('Core', 'Core_OrgOptimizer_ErrorsText'),
          'standard:incident'
        ),
        this.tile(
          'storage',
          STORAGE,
          helpText('Core', 'Core_OrgOptimizer_StorageText'),
          'standard:data_model'
        ),
        this.tile(
          'setup',
          SETUP,
          helpText('Core', 'Core_OrgOptimizer_SetupText'),
          'standard:settings'
        ),
        this.tile(
          'setupChanges',
          SETUP_CHANGES,
          helpText('Core', 'Core_OrgOptimizer_SetupChangesText'),
          'standard:timeslot'
        ),
        this.tile(
          'accessExplorer',
          ACCESS_EXPLORER,
          helpText('Core', 'Core_OrgOptimizer_AccessExplorerText'),
          'standard:user_role'
        )
      );
    }
    return [
      { name: 'data', label: GROUP_DATA, tiles: dataTiles },
      { name: 'setup', label: GROUP_SETUP, tiles: setupTiles }
    ];
  }

  tile(name, label, description, iconName) {
    return { name, label, description, iconName, ...(this.badges[name] || {}) };
  }

  setBadge(name, value) {
    this.badges = { ...this.badges, [name]: value };
  }

  /**
   * The section list, grouped like the Overview and with the Overview tiles' icons, for the
   * vertical navigation: Overview first (the page's own tab icon), then each non-empty group.
   */
  get navigationGroups() {
    const groups = this.overviewGroups
      .filter((group) => group.tiles.length > 0)
      .map((group) => ({
        name: group.name,
        label: group.label,
        items: group.tiles.map((tile) => ({
          name: tile.name,
          label: tile.label,
          iconName: tile.iconName
        }))
      }));
    return [
      {
        name: 'start',
        label: TITLE,
        items: [{ name: OVERVIEW_TAB, label: OVERVIEW, iconName: iconFor('Data_Hygiene') }]
      },
      ...groups
    ];
  }

  /** Every section the person may open, in list order. */
  get sectionItems() {
    return this.navigationGroups.flatMap((group) => group.items);
  }

  /** The Show box's choices under medium width: the same sections, in the same order. */
  get sectionOptions() {
    return this.sectionItems.map((item) => ({ label: item.label, value: item.name }));
  }

  get activeSectionLabel() {
    const active = this.sectionItems.find((item) => item.name === this.activeSection);
    return active ? active.label : TITLE;
  }

  /** Only the active section shows; an opened section stays loaded, hidden, so it keeps its state. */
  get sectionClass() {
    const classes = {};
    this.sectionItems.forEach((item) => {
      classes[item.name] = item.name === this.activeSection ? '' : 'slds-hide';
    });
    return classes;
  }

  async readErrorBadge() {
    try {
      const tile = await getErrorTile({ rowCount: 1 });
      const count = (tile && tile.newCount) || 0;
      const shown = tile && tile.newCountCapped ? `${count}+` : String(count);
      this.setBadge(
        'errors',
        count > 0
          ? badge(BADGE_NEW.replace('{0}', shown), 'warning')
          : badge(BADGE_ALL_CLEAR, 'success')
      );
    } catch {
      // A badge is a hint: without it the tile still opens the section, which says what failed.
    }
  }

  async readHealthCheckBadge() {
    try {
      // One badge rule, shared with the Health Check summary on BarnCRM Home.
      this.lastRun = await getLastRun();
      this.setBadge('healthCheck', healthCheckBadge(this.lastRun));
    } catch {
      // As above: the Health Check section itself reports a failure to read.
    }
  }

  handleQualitySummary(event) {
    const needsAttention = (event.detail && event.detail.needsAttention) || 0;
    this.setBadge(
      'quality',
      needsAttention > 0
        ? badge(BADGE_NEED_ATTENTION.replace('{0}', needsAttention), 'warning')
        : badge(BADGE_ALL_CLEAR, 'success')
    );
  }

  handleStorageSummary(event) {
    const percent = event.detail && event.detail.dataStoragePercent;
    if (percent === undefined || percent === null) {
      return;
    }
    let variant = '';
    if (percent >= STORAGE_ERROR) {
      variant = 'error';
    } else if (percent >= STORAGE_WARNING) {
      variant = 'warning';
    }
    this.setBadge('storage', badge(BADGE_DATA_STORAGE.replace('{0}', percent), variant));
  }

  get qualityOpened() {
    return Boolean(this.opened.quality);
  }

  get fieldUtilizationOpened() {
    return Boolean(this.opened.fieldUtilization);
  }

  get dataDictionaryOpened() {
    return Boolean(this.opened.dataDictionary);
  }

  get aiExportOpened() {
    return Boolean(this.opened.aiExport);
  }

  get errorsOpened() {
    return Boolean(this.opened.errors);
  }

  get storageOpened() {
    return Boolean(this.opened.storage);
  }

  get setupOpened() {
    return Boolean(this.opened.setup);
  }

  get setupChangesOpened() {
    return Boolean(this.opened.setupChanges);
  }

  get accessExplorerOpened() {
    return Boolean(this.opened.accessExplorer);
  }

  get healthCheckOpened() {
    return Boolean(this.opened.healthCheck);
  }

  /**
   * A link names a section to open by page state (the Access page's button, Settings' Open
   * Health Check and Open the Error Log, Home). Only a section the person may open is opened;
   * any other value leaves the page where it is. Opening Health Check this way shows the stored
   * run and runs nothing.
   */
  @wire(CurrentPageReference)
  wiredPage(pageReference) {
    const state = (pageReference && pageReference.state) || {};
    const key = Object.keys(state).find((name) => SECTION_STATE_KEY.test(name));
    const requested = key ? state[key] : undefined;
    if (
      requested &&
      requested !== this.activeSection &&
      this.sectionItems.some((item) => item.name === requested)
    ) {
      this.openSection(requested);
    }
  }

  get hasLastRun() {
    return Boolean(this.lastRun && this.lastRun.ranAt);
  }

  /** The panel shows once asked to run, or straight away when a stored run is there to show. */
  get showHealthCheck() {
    return Boolean(this.opened.healthCheck) && (this.healthCheckRequested || this.hasLastRun);
  }

  /** Until Run Health Check is pressed here, the panel shows the stored run, not a new one. */
  get healthCheckLastResultFirst() {
    return !this.healthCheckRequested;
  }

  handleNavSelect(event) {
    this.chooseSection(event.detail.name);
  }

  handleShowChange(event) {
    this.chooseSection(event.detail.value);
  }

  handleSelectTool(event) {
    this.chooseSection(event.detail.name);
  }

  /** A section the person chose: open it, then move the focus to it once it has rendered. */
  chooseSection(name) {
    if (!name) {
      return;
    }
    this.openSection(name);
    this.focusPending = true;
  }

  renderedCallback() {
    if (!this.focusPending) {
      return;
    }
    const section = this.template.querySelector('[data-id="section-content"]');
    if (section) {
      this.focusPending = false;
      section.focus();
    }
  }

  openSection(name) {
    this.activeSection = name;
    if (!this.opened[name]) {
      this.opened = { ...this.opened, [name]: true };
    }
    // Back on the Overview after a run (Run Health Check, or Run Again in the panel), the Health
    // Check tile shows that run.
    if (name === OVERVIEW_TAB && canManageSettings && this.opened.healthCheck) {
      this.readHealthCheckBadge();
    }
  }

  handleRunHealthCheck() {
    this.healthCheckRequested = true;
  }
}
