import { LightningElement } from 'lwc';
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import canFind from '@salesforce/customPermission/Find_And_Export_Records';
import canReviewDuplicates from '@salesforce/customPermission/Review_Duplicate_Suggestions';

import TITLE from '@salesforce/label/c.Core_OrgOptimizer_Title';
import INTRO from '@salesforce/label/c.Core_OrgOptimizer_Intro';
import OVERVIEW from '@salesforce/label/c.Core_OrgOptimizer_Overview';
import QUALITY from '@salesforce/label/c.Core_OrgOptimizer_Quality';
import QUALITY_TEXT from '@salesforce/label/c.Core_OrgOptimizer_QualityText';
import DUPLICATES from '@salesforce/label/c.Core_OrgOptimizer_Duplicates';
import DUPLICATES_TEXT from '@salesforce/label/c.Core_OrgOptimizer_DuplicatesText';
import FIELD_UTILIZATION from '@salesforce/label/c.Core_OrgOptimizer_FieldUtilization';
import FIELD_UTILIZATION_TEXT from '@salesforce/label/c.Core_OrgOptimizer_FieldUtilizationText';
import HEALTH_CHECK from '@salesforce/label/c.Core_OrgOptimizer_HealthCheck';
import HEALTH_CHECK_TEXT from '@salesforce/label/c.Core_OrgOptimizer_HealthCheckText';
import ERRORS from '@salesforce/label/c.Core_OrgOptimizer_Errors';
import ERRORS_TEXT from '@salesforce/label/c.Core_OrgOptimizer_ErrorsText';
import STORAGE from '@salesforce/label/c.Core_OrgOptimizer_Storage';
import STORAGE_TEXT from '@salesforce/label/c.Core_OrgOptimizer_StorageText';
import SETUP from '@salesforce/label/c.Core_OrgOptimizer_Setup';
import SETUP_TEXT from '@salesforce/label/c.Core_OrgOptimizer_SetupText';
import OPEN from '@salesforce/label/c.Core_OrgOptimizer_Open';
import OPEN_ARIA from '@salesforce/label/c.Core_OrgOptimizer_OpenAria';
import RUN_HEALTH_CHECK from '@salesforce/label/c.Core_OrgOptimizer_RunHealthCheck';
import HEALTH_CHECK_INTRO from '@salesforce/label/c.Core_OrgOptimizer_HealthCheckIntro';

const OVERVIEW_TAB = 'overview';

/**
 * The Org Optimizer page (ADR-0103 org-optimizer-and-data-manager-pages, admin guide
 * org-optimizer.md): one vertical tab per section. A section's component is created only when
 * its tab is first opened, and Health Check only on Run Health Check, so opening the page runs
 * no check (core review ADMIN-7). Data quality needs Find and Export Records; Duplicates needs
 * Manage BarnCRM Settings or Review Duplicate Suggestions (BarnCRM Duplicate Review, which
 * reads the list but cannot scan, dismiss or merge); the other sections need Manage BarnCRM
 * Settings. Each embedded component keeps its own server check.
 */
export default class OrgOptimizer extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    overview: OVERVIEW,
    quality: QUALITY,
    duplicates: DUPLICATES,
    fieldUtilization: FIELD_UTILIZATION,
    healthCheck: HEALTH_CHECK,
    errors: ERRORS,
    storage: STORAGE,
    setup: SETUP,
    open: OPEN,
    runHealthCheck: RUN_HEALTH_CHECK,
    healthCheckIntro: HEALTH_CHECK_INTRO
  };

  activeSection = OVERVIEW_TAB;
  /** The sections opened so far; a section stays loaded once opened. */
  opened = {};
  healthCheckRequested = false;

  get canSeeQuality() {
    return Boolean(canFind);
  }

  get isAdmin() {
    return Boolean(canManageSettings);
  }

  get canSeeDuplicates() {
    return Boolean(canManageSettings || canReviewDuplicates);
  }

  /** The Overview's list: one line per section the person may open. */
  get overviewSections() {
    const sections = [];
    if (canFind) {
      sections.push({ name: 'quality', title: QUALITY, text: QUALITY_TEXT });
    }
    if (this.canSeeDuplicates) {
      sections.push({ name: 'duplicates', title: DUPLICATES, text: DUPLICATES_TEXT });
    }
    if (canManageSettings) {
      sections.push(
        { name: 'fieldUtilization', title: FIELD_UTILIZATION, text: FIELD_UTILIZATION_TEXT },
        { name: 'healthCheck', title: HEALTH_CHECK, text: HEALTH_CHECK_TEXT },
        { name: 'errors', title: ERRORS, text: ERRORS_TEXT },
        { name: 'storage', title: STORAGE, text: STORAGE_TEXT },
        { name: 'setup', title: SETUP, text: SETUP_TEXT }
      );
    }
    return sections.map((section) => ({
      ...section,
      openLabel: OPEN_ARIA.replace('{0}', section.title)
    }));
  }

  get qualityOpened() {
    return Boolean(this.opened.quality);
  }

  get duplicatesOpened() {
    return Boolean(this.opened.duplicates);
  }

  get fieldUtilizationOpened() {
    return Boolean(this.opened.fieldUtilization);
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

  get showHealthCheck() {
    return Boolean(this.opened.healthCheck) && this.healthCheckRequested;
  }

  handleActive(event) {
    const name = event.target.value;
    this.activeSection = name;
    if (!this.opened[name]) {
      this.opened = { ...this.opened, [name]: true };
    }
  }

  handleOpenSection(event) {
    const name = event.currentTarget.dataset.section;
    this.activeSection = name;
    this.opened = { ...this.opened, [name]: true };
  }

  handleRunHealthCheck() {
    this.healthCheckRequested = true;
  }
}
