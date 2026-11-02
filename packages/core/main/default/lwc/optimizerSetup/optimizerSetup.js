import { LightningElement } from 'lwc';
import getFindings from '@salesforce/apex/OrgOptimizerSetupController.getFindings';

import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import SETUP from '@salesforce/label/c.Core_OrgOptimizer_Setup';
import SETUP_INTRO from '@salesforce/label/c.Core_OrgOptimizer_SetupIntro';
import CHECK_USERS from '@salesforce/label/c.Core_OrgOptimizer_CheckInactiveUsers';
import CHECK_SETS from '@salesforce/label/c.Core_OrgOptimizer_CheckUnassignedPermissionSets';
import CHECK_REPORTS from '@salesforce/label/c.Core_OrgOptimizer_CheckStaleReports';
import CHECK_TEMPLATES from '@salesforce/label/c.Core_OrgOptimizer_CheckUnusedEmailTemplates';
import CHECK_FLOWS from '@salesforce/label/c.Core_OrgOptimizer_CheckInactiveFlows';
import CHECK_JOBS from '@salesforce/label/c.Core_OrgOptimizer_CheckJobsOfInactiveUsers';
import CHECK_FIELD_LIMIT from '@salesforce/label/c.Core_OrgOptimizer_CheckFieldLimit';
import CHECK_RECORD_TYPES from '@salesforce/label/c.Core_OrgOptimizer_CheckRecordTypes';
import COULD_NOT_CHECK from '@salesforce/label/c.Core_OrgOptimizer_CouldNotCheck';
import OPEN_IN_SETUP from '@salesforce/label/c.Core_SetupNote_OpenInSetup';
import MORE_THAN from '@salesforce/label/c.Core_HealthCheck_OrphansMoreThan';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import NEW_TAB from '@salesforce/label/c.Core_Kit_NewTab';
import UNUSED_HEADING from '@salesforce/label/c.Core_OrgOptimizer_Setup';
import DEBT_HEADING from '@salesforce/label/c.Core_TechDebt_DebtHeading';
import DEBT_INTRO from '@salesforce/label/c.Core_TechDebt_DebtIntro';
import CHECK_APEX from '@salesforce/label/c.Core_TechDebt_CheckApex';
import CHECK_TRIGGERS from '@salesforce/label/c.Core_TechDebt_CheckTriggers';
import CHECK_FLOWS_API from '@salesforce/label/c.Core_TechDebt_CheckFlowsApi';
import CHECK_FLOWS_NO_DESCRIPTION from '@salesforce/label/c.Core_TechDebt_CheckFlowsNoDescription';
import { format } from 'c/findCsv';

/**
 * Org Optimizer's Unused Setup section (admin guide org-optimizer.md): one line per check with
 * its count, up to five names, and a link to its Setup page. Read only; read when the section
 * is opened and on Refresh. Admin only: the shell shows it only with Manage BarnCRM Settings,
 * and the controller checks again.
 */
export default class OptimizerSetup extends LightningElement {
  labels = {
    title: SETUP,
    intro: SETUP_INTRO,
    openInSetup: OPEN_IN_SETUP,
    refresh: REFRESH,
    newTab: NEW_TAB
  };

  result;
  errorMessage;
  loading = false;

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    this.errorMessage = undefined;
    try {
      this.result = await getFindings();
    } catch (error) {
      this.errorMessage = (error && error.body && error.body.message) || UNEXPECTED_ERROR;
    } finally {
      this.loading = false;
    }
  }

  titleFor(key) {
    const result = this.result || {};
    switch (key) {
      case 'inactiveUsers':
        return format(CHECK_USERS, result.loginDays);
      case 'unassignedPermissionSets':
        return CHECK_SETS;
      case 'staleReports':
        return format(CHECK_REPORTS, result.reportDays);
      case 'unusedEmailTemplates':
        return CHECK_TEMPLATES;
      case 'inactiveFlows':
        return CHECK_FLOWS;
      case 'jobsOfInactiveUsers':
        return CHECK_JOBS;
      case 'apexOldApi':
        return format(CHECK_APEX, result.apiVersion);
      case 'triggersOldApi':
        return format(CHECK_TRIGGERS, result.apiVersion);
      case 'flowsOldApi':
        return format(CHECK_FLOWS_API, result.apiVersion);
      case 'flowsNoDescription':
        return CHECK_FLOWS_NO_DESCRIPTION;
      case 'objectsNearFieldLimit':
        return CHECK_FIELD_LIMIT;
      case 'unusedRecordTypes':
        return CHECK_RECORD_TYPES;
      default:
        return key;
    }
  }

  get findings() {
    const cap = this.result ? this.result.countCap : 0;
    return ((this.result && this.result.findings) || []).map((finding) => {
      let countText = String(finding.count);
      // A count is a badge, in warning colors when the check found something.
      let countClass = finding.count > 0 ? 'slds-badge slds-theme_warning' : 'slds-badge';
      if (finding.failed) {
        countText = COULD_NOT_CHECK;
        countClass = 'slds-text-color_weak';
      } else if (finding.moreThan) {
        countText = format(MORE_THAN, cap);
      }
      const examples = (finding.examples || []).filter((name) => name);
      return {
        ...finding,
        title: this.titleFor(finding.key),
        countText,
        countClass,
        examplesText: examples.join(', '),
        hasExamples: examples.length > 0
      };
    });
  }

  /** The unused setup checks, then the technical debt checks; the heading shows only when both exist. */
  get sections() {
    const all = this.findings;
    const debt = all.filter((finding) => finding.kind === 'debt');
    const unused = all.filter((finding) => finding.kind !== 'debt');
    const both = debt.length > 0 && unused.length > 0;
    const sections = [
      {
        kind: 'unused',
        sectionId: 'unused-section',
        listId: 'findings',
        heading: UNUSED_HEADING,
        showHeading: both,
        findings: unused
      }
    ];
    if (debt.length) {
      sections.push({
        kind: 'debt',
        sectionId: 'debt-section',
        listId: 'debt-findings',
        heading: DEBT_HEADING,
        showHeading: true,
        intro: DEBT_INTRO,
        findings: debt
      });
    }
    return sections;
  }

  handleRefresh() {
    this.load();
  }
}
