import { LightningElement } from 'lwc';
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import canFind from '@salesforce/customPermission/Find_And_Export_Records';
import getErrorTile from '@salesforce/apex/ErrorLogController.getTile';
import getLastRun from '@salesforce/apex/HealthCheckController.getLastRun';
import { healthCheckBadge } from 'c/healthCheckBadge';

import TITLE from '@salesforce/label/c.Core_OrgOptimizer_Title';
import INTRO from '@salesforce/label/c.Core_OrgOptimizer_Intro';
import HELP_TEXT from '@salesforce/label/c.Core_OrgOptimizer_HelpText';
import OVERVIEW from '@salesforce/label/c.Core_OrgOptimizer_Overview';
import GROUP_DATA from '@salesforce/label/c.Core_OrgOptimizer_GroupData';
import GROUP_SETUP from '@salesforce/label/c.Core_OrgOptimizer_GroupSetup';
import QUALITY from '@salesforce/label/c.Core_OrgOptimizer_Quality';
import QUALITY_TEXT from '@salesforce/label/c.Core_OrgOptimizer_QualityText';
import FIELD_UTILIZATION from '@salesforce/label/c.Core_OrgOptimizer_FieldUtilization';
import FIELD_UTILIZATION_TEXT from '@salesforce/label/c.Core_OrgOptimizer_FieldUtilizationText';
import DATA_DICTIONARY from '@salesforce/label/c.Core_OrgOptimizer_DataDictionary';
import DATA_DICTIONARY_TEXT from '@salesforce/label/c.Core_OrgOptimizer_DataDictionaryText';
import HEALTH_CHECK from '@salesforce/label/c.Core_OrgOptimizer_HealthCheck';
import HEALTH_CHECK_TEXT from '@salesforce/label/c.Core_OrgOptimizer_HealthCheckText';
import ERRORS from '@salesforce/label/c.Core_OrgOptimizer_Errors';
import ERRORS_TEXT from '@salesforce/label/c.Core_OrgOptimizer_ErrorsText';
import STORAGE from '@salesforce/label/c.Core_OrgOptimizer_Storage';
import STORAGE_TEXT from '@salesforce/label/c.Core_OrgOptimizer_StorageText';
import SETUP from '@salesforce/label/c.Core_OrgOptimizer_Setup';
import SETUP_TEXT from '@salesforce/label/c.Core_OrgOptimizer_SetupText';
import RUN_HEALTH_CHECK from '@salesforce/label/c.Core_OrgOptimizer_RunHealthCheck';
import HEALTH_CHECK_INTRO from '@salesforce/label/c.Core_OrgOptimizer_HealthCheckIntro';
import HEALTH_CHECK_NOT_RUN from '@salesforce/label/c.Core_OrgOptimizer_HealthCheckNotRunHeading';
import BADGE_ALL_CLEAR from '@salesforce/label/c.Core_OrgOptimizer_BadgeAllClear';
import BADGE_NEW from '@salesforce/label/c.Core_OrgOptimizer_BadgeNew';
import BADGE_NEED_ATTENTION from '@salesforce/label/c.Core_OrgOptimizer_BadgeNeedAttention';
import BADGE_DATA_STORAGE from '@salesforce/label/c.Core_OrgOptimizer_BadgeDataStorage';

const OVERVIEW_TAB = 'overview';
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
 * vertical tab per section. A section's component is created only when its tab is first opened,
 * and Health Check never runs on open, so opening the page runs no check (core review ADMIN-7).
 * The Health Check section shows the same stored last run the tile badges (date, counts and
 * Run now), or Not Run Yet with Run Health Check when there is none, so the tile and the
 * section always agree (owner QA, 2026-10-31). Tile badges show only what is already known: the unread error count and the last
 * Health Check run (two small reads, administrators only), and the Data Quality and Storage
 * results once those sections have reported them. Data Quality needs Find and Export Records;
 * the other sections need Manage BarnCRM Settings. Each embedded component keeps its own server
 * check. Duplicates moved to the Duplicate Matching tab (ADR-0139).
 */
export default class OrgOptimizer extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    helpText: HELP_TEXT,
    overview: OVERVIEW,
    quality: QUALITY,
    fieldUtilization: FIELD_UTILIZATION,
    dataDictionary: DATA_DICTIONARY,
    healthCheck: HEALTH_CHECK,
    errors: ERRORS,
    storage: STORAGE,
    setup: SETUP,
    runHealthCheck: RUN_HEALTH_CHECK,
    healthCheckIntro: HEALTH_CHECK_INTRO,
    healthCheckNotRun: HEALTH_CHECK_NOT_RUN
  };

  learnMoreUrl = LEARN_MORE_URL;
  activeSection = OVERVIEW_TAB;
  /** The sections opened so far; a section stays loaded once opened. */
  opened = {};
  healthCheckRequested = false;
  /** The stored last Health Check run (getLastRun), once read. */
  lastRun;
  /** Tile badges by section name, each { badgeLabel, badgeVariant }. */
  badges = {};

  connectedCallback() {
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
      dataTiles.push(this.tile('quality', QUALITY, QUALITY_TEXT, 'standard:data_integration_hub'));
    }
    const setupTiles = [];
    if (canManageSettings) {
      dataTiles.push(
        this.tile('fieldUtilization', FIELD_UTILIZATION, FIELD_UTILIZATION_TEXT, 'standard:metrics')
      );
      dataTiles.push(
        this.tile('dataDictionary', DATA_DICTIONARY, DATA_DICTIONARY_TEXT, 'standard:article')
      );
      setupTiles.push(
        this.tile('healthCheck', HEALTH_CHECK, HEALTH_CHECK_TEXT, 'standard:approval'),
        this.tile('errors', ERRORS, ERRORS_TEXT, 'standard:incident'),
        this.tile('storage', STORAGE, STORAGE_TEXT, 'standard:data_model'),
        this.tile('setup', SETUP, SETUP_TEXT, 'standard:settings')
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

  get errorsOpened() {
    return Boolean(this.opened.errors);
  }

  get storageOpened() {
    return Boolean(this.opened.storage);
  }

  get setupOpened() {
    return Boolean(this.opened.setup);
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

  handleActive(event) {
    this.openSection(event.target.value);
  }

  handleSelectTool(event) {
    this.openSection(event.detail.name);
  }

  openSection(name) {
    this.activeSection = name;
    if (!this.opened[name]) {
      this.opened = { ...this.opened, [name]: true };
    }
    // Back on the Overview after a run (Run Health Check, or Run now in the panel), the Health
    // Check tile shows that run.
    if (name === OVERVIEW_TAB && canManageSettings && this.opened.healthCheck) {
      this.readHealthCheckBadge();
    }
  }

  handleRunHealthCheck() {
    this.healthCheckRequested = true;
  }
}
