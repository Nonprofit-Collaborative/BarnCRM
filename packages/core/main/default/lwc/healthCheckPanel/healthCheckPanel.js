import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import BarnConfirmModal from 'c/barnConfirmModal';
import { EnclosingTabId } from 'lightning/platformWorkspaceApi';
import { followLinkInWorkspace } from 'c/workspaceTabs';

import getReport from '@salesforce/apex/HealthCheckController.getReport';
import getLastRun from '@salesforce/apex/HealthCheckController.getLastRun';
import applyRecommendedMode from '@salesforce/apex/HealthCheckController.applyRecommendedMode';
import applyJunctionMembership from '@salesforce/apex/HealthCheckController.applyJunctionMembership';
import enableAutomaticHouseholds from '@salesforce/apex/HealthCheckController.enableAutomaticHouseholds';
import applyFix from '@salesforce/apex/HealthCheckController.applyFix';

import CATEGORY_ACCESS from '@salesforce/label/c.Core_HealthCheck_CategoryAccess';
import CATEGORY_LICENSES from '@salesforce/label/c.Core_HealthCheck_CategoryLicenses';
import CATEGORY_ORG_SHAPE from '@salesforce/label/c.Core_HealthCheck_CategoryOrgShape';
import CATEGORY_SETTINGS from '@salesforce/label/c.Core_HealthCheck_CategorySettings';
import CANCEL from '@salesforce/label/c.Core_HealthCheck_CancelButton';
import CONFIRM from '@salesforce/label/c.Core_HealthCheck_ConfirmButton';
import CONFIRM_HEADING from '@salesforce/label/c.Core_HealthCheck_ConfirmHeading';
import CONFIRM_INTRO from '@salesforce/label/c.Core_HealthCheck_ConfirmIntro';
import CONFIRM_MODE_DETAIL from '@salesforce/label/c.Core_HealthCheck_ConfirmModeDetail';
import CURRENT_MODE from '@salesforce/label/c.Core_HealthCheck_CurrentModeLabel';
import INTRO from '@salesforce/label/c.Core_HealthCheck_Intro';
import LAST_RUN from '@salesforce/label/c.Core_HealthCheck_LastRunLabel';
import NEVER_RUN from '@salesforce/label/c.Core_HealthCheck_NeverRun';
import RUN_NOW from '@salesforce/label/c.Core_HealthCheck_RunNowButton';
import LOAD_FAILED from '@salesforce/label/c.Core_HealthCheck_LoadFailed';
import LOADING from '@salesforce/label/c.Core_HealthCheck_Loading';
import NO_FINDINGS from '@salesforce/label/c.Core_HealthCheck_NoFindings';
import ORG_SHAPE_CARD from '@salesforce/label/c.Core_HealthCheck_OrgShapeCardTitle';
import READ_ONLY from '@salesforce/label/c.Core_HealthCheck_ReadOnlyNotice';
import RECOMMENDED_MODE from '@salesforce/label/c.Core_HealthCheck_RecommendedModeLabel';
import RERUN from '@salesforce/label/c.Core_HealthCheck_RerunButton';
import SEVERITY_ERROR from '@salesforce/label/c.Core_HealthCheck_SeverityError';
import SEVERITY_INFO from '@salesforce/label/c.Core_HealthCheck_SeverityInfo';
import SEVERITY_WARNING from '@salesforce/label/c.Core_HealthCheck_SeverityWarning';
import TITLE from '@salesforce/label/c.Core_HealthCheck_Title';
import USE_RECOMMENDED from '@salesforce/label/c.Core_HealthCheck_UseRecommendedButton';

const ACTION_PREFIX = 'action:';
const ACTION_RECOMMENDED_MODE = 'action:applyRecommendedMode';
const ACTION_JUNCTION_MEMBERSHIP = 'action:applyJunctionMembership';
const ACTION_AUTOMATIC_HOUSEHOLDS = 'action:enableAutomaticHouseholds';

const SEVERITY_DISPLAY = {
  Error: { icon: 'utility:error', variant: 'error', order: 0 },
  Warning: { icon: 'utility:warning', variant: 'warning', order: 1 },
  Info: { icon: 'utility:info', variant: '', order: 2 }
};

const CATEGORY_ORDER = ['OrgShape', 'Licenses', 'Access', 'Settings'];

/**
 * Health Check: what BarnCRM found in this org and what to do about it (feature C-11).
 *
 * The panel is readable by anyone. The Fix buttons appear only when the report says the
 * viewer holds the Manage BarnCRM Settings permission, which Apex checks again before it
 * changes anything.
 *
 * A fix that changes something (an "action:" target) never runs on the first click: the
 * panel shows what it will do, taken from the finding, and waits for Confirm (C-21,
 * ADR-0048). A fix that only opens a page runs at once, because opening a page changes
 * nothing.
 *
 * The confirmation is a platform modal (c/barnConfirmModal), so it opens over the report
 * wherever the button is, traps focus, and on Escape or Cancel closes and returns focus to
 * that button. The fix request carries the finding's fix scope, so Apex runs it only if it
 * would still change exactly what the dialog showed. When a
 * fix fails for any reason the panel runs Health Check again, so what it shows is current.
 *
 * With lastResultFirst set (BarnCRM Home sets it), the panel does not run Health Check when it
 * opens: it shows when Health Check last ran in full and how many findings it had, and its
 * button reads Run now (ADMIN-7). Any page that wants that behavior sets the same property.
 */
export default class HealthCheckPanel extends NavigationMixin(LightningElement) {
  /** Show the last stored result and Run now, instead of running every check on open. */
  @api lastResultFirst = false;

  report;
  lastRun;
  loading = false;
  errorMessage;
  fixOutcome;

  @wire(EnclosingTabId) enclosingTabId;

  labels = {
    title: TITLE,
    intro: INTRO,
    rerun: RERUN,
    useRecommended: USE_RECOMMENDED,
    orgShapeCard: ORG_SHAPE_CARD,
    readOnly: READ_ONLY,
    loading: LOADING,
    noFindings: NO_FINDINGS,
    currentMode: CURRENT_MODE,
    recommendedMode: RECOMMENDED_MODE,
    lastRun: LAST_RUN,
    neverRun: NEVER_RUN
  };

  connectedCallback() {
    if (this.lastResultFirst) {
      this.loadLastRun();
    } else {
      this.load();
    }
  }

  /** Read the last stored result without running any check. */
  async loadLastRun() {
    this.loading = true;
    this.errorMessage = undefined;
    try {
      this.lastRun = await getLastRun();
    } catch (error) {
      this.lastRun = undefined;
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  /** The last result shows until a full report replaces it. */
  get showLastRun() {
    return this.lastResultFirst && !this.hasReport && !this.loading && !this.errorMessage;
  }

  get hasLastRun() {
    return !!(this.lastRun && this.lastRun.ranAt);
  }

  get lastRunAt() {
    return this.hasLastRun ? this.lastRun.ranAt : undefined;
  }

  get lastRunResult() {
    return this.hasLastRun ? this.lastRun.result : '';
  }

  /** Run now before the first full run where the last result shows; Re-run after. */
  get rerunLabel() {
    return this.lastResultFirst && !this.hasReport ? RUN_NOW : RERUN;
  }

  /** Run Health Check again. Also the Re-run button's handler. */
  @api
  async load() {
    this.loading = true;
    this.errorMessage = undefined;
    this.fixOutcome = undefined;
    try {
      this.report = await getReport();
    } catch (error) {
      this.report = undefined;
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.loading = false;
    }
  }

  get hasReport() {
    return !!this.report;
  }

  get canManageSettings() {
    return !!(this.report && this.report.canManageSettings);
  }

  get isReadOnly() {
    return this.hasReport && !this.canManageSettings;
  }

  get orgShapeSummary() {
    return this.report ? this.report.orgShapeSummary : '';
  }

  get currentModeLabel() {
    return this.report ? this.report.currentModeLabel : '';
  }

  get recommendedModeLabel() {
    return this.report ? this.report.recommendedModeLabel : '';
  }

  /** The "Use recommended mode" button only makes sense when the mode is wrong. */
  get showUseRecommended() {
    return this.canManageSettings && !!(this.report && this.report.modeNeedsAttention);
  }

  get hasFindings() {
    return !!(this.report && this.report.findings && this.report.findings.length > 0);
  }

  get showNoFindings() {
    return this.hasReport && !this.hasFindings;
  }

  /** Findings grouped by category, in reading order, with their severity display. */
  get groups() {
    if (!this.hasFindings) {
      return [];
    }

    const byCategory = new Map();
    this.report.findings.forEach((finding) => {
      const category = finding.category || 'Settings';
      if (!byCategory.has(category)) {
        byCategory.set(category, []);
      }
      byCategory.get(category).push(this.decorate(finding));
    });

    return CATEGORY_ORDER.filter((category) => byCategory.has(category)).map((category) => {
      const findings = byCategory.get(category);
      findings.sort((left, right) => left.order - right.order);
      return { key: category, label: this.categoryLabel(category), findings };
    });
  }

  decorate(finding) {
    const display = SEVERITY_DISPLAY[finding.severity] || SEVERITY_DISPLAY.Info;
    return {
      key: finding.key,
      title: finding.title,
      detail: finding.detail,
      severity: finding.severity,
      severityText: this.severityText(finding.severity),
      iconName: display.icon,
      iconVariant: display.variant,
      order: display.order,
      fixLabel: finding.fixLabel,
      fixTarget: finding.fixTarget,
      showFix: !!finding.fixTarget && !!finding.fixLabel && this.canManageSettings,
      links: finding.links || [],
      hasLinks: !!(finding.links && finding.links.length > 0)
    };
  }

  categoryLabel(category) {
    switch (category) {
      case 'OrgShape':
        return CATEGORY_ORG_SHAPE;
      case 'Licenses':
        return CATEGORY_LICENSES;
      case 'Access':
        return CATEGORY_ACCESS;
      default:
        return CATEGORY_SETTINGS;
    }
  }

  severityText(severity) {
    switch (severity) {
      case 'Error':
        return SEVERITY_ERROR;
      case 'Warning':
        return SEVERITY_WARNING;
      default:
        return SEVERITY_INFO;
    }
  }

  handleRerun() {
    this.load();
  }

  handleUseRecommended() {
    return this.confirmFix({
      target: ACTION_RECOMMENDED_MODE,
      title: USE_RECOMMENDED,
      detail: CONFIRM_MODE_DETAIL.replace('{0}', this.currentModeLabel).replace(
        '{1}',
        this.recommendedModeLabel
      )
    });
  }

  /**
   * Show what a fix will do in a confirm dialog, and run it only when the viewer confirms.
   * Cancel, Escape and the close button run nothing.
   */
  async confirmFix(pending) {
    this.fixOutcome = undefined;
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: CONFIRM_HEADING,
      message: CONFIRM_INTRO,
      details: [pending.title, pending.detail],
      confirmLabel: CONFIRM,
      cancelLabel: CANCEL
    });
    if (confirmed) {
      this.runFix(pending);
    }
  }

  /** Run the fix the viewer has just seen described and confirmed. */
  runFix(pending) {
    if (pending.target === ACTION_RECOMMENDED_MODE) {
      this.runAction(applyRecommendedMode);
      return;
    }
    if (pending.target === ACTION_JUNCTION_MEMBERSHIP) {
      this.runAction(applyJunctionMembership);
      return;
    }
    if (pending.target === ACTION_AUTOMATIC_HOUSEHOLDS) {
      this.runAction(enableAutomaticHouseholds);
      return;
    }
    const fixKey = pending.target.substring(ACTION_PREFIX.length);
    this.runAction(() => applyFix({ fixKey, expectedScope: pending.scope || [] }));
  }

  /** The finding a Fix button belongs to, so the confirm box can repeat what it says. */
  /** In a console a record a finding names opens as a subtab, so the report stays open. */
  handleFindingLink(event) {
    const url = event.currentTarget.getAttribute('href');
    followLinkInWorkspace(this, event, { url }, () =>
      this[NavigationMixin.Navigate]({ type: 'standard__webPage', attributes: { url } })
    );
  }

  findingFor(key) {
    const findings = (this.report && this.report.findings) || [];
    return findings.find((finding) => finding.key === key);
  }

  /**
   * A fix is one of three things: a method on the controller, a page to navigate to, or a
   * section of the settings console for the console to open. A method waits for Confirm.
   */
  handleFix(event) {
    const target = event.currentTarget.dataset.target;
    if (!target) {
      return;
    }

    if (target.startsWith(ACTION_PREFIX)) {
      const key = event.currentTarget.dataset.key;
      const finding = this.findingFor(key);
      if (!finding || !finding.title) {
        // Nothing to show means nothing the administrator could confirm: the report on screen
        // is not the one this button came from. Run Health Check again instead.
        this.load();
        return;
      }
      this.confirmFix({
        target,
        title: finding.title,
        detail: finding.detail,
        scope: finding.fixScope
      });
      return;
    }
    if (target.startsWith('/')) {
      this[NavigationMixin.Navigate]({
        type: 'standard__webPage',
        attributes: { url: target }
      });
      return;
    }

    // A section fix opens the settings console at that section. Offer it to the host first:
    // a console already showing this panel switches section in place and calls
    // preventDefault, and the event then reports itself as handled. Only when nobody
    // handles it, which is every other placement including the Hub home page, does the
    // panel navigate to the console itself.
    const handled = !this.dispatchEvent(
      new CustomEvent('navigatetosection', {
        detail: { section: target },
        bubbles: true,
        composed: true,
        cancelable: true
      })
    );
    if (handled) {
      return;
    }

    this.navigateToSettings(target);
  }

  /**
   * Open the settings console at a section. The tab API name and the page state key both
   * carry the package namespace, so they come from Apex rather than being written here
   * (see docs/contributor-guide/environment.md, "Namespace registration").
   */
  navigateToSettings(section) {
    const apiName = this.report && this.report.settingsTabApiName;
    const stateKey = this.report && this.report.sectionStateKey;
    if (!apiName || !stateKey) {
      return;
    }

    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName },
      state: { [stateKey]: section }
    });
  }

  /**
   * Run a fix and show the report it returns. When the fix fails, nothing was changed, but
   * the report on screen may be why (the org changed since it was read), so Health Check
   * runs again and the failure stays on screen above the fresh report.
   */
  async runAction(action) {
    this.loading = true;
    this.errorMessage = undefined;
    this.fixOutcome = undefined;
    try {
      this.report = await action();
      this.fixOutcome = this.report ? this.report.fixOutcome : undefined;
    } catch (error) {
      const message = this.messageFrom(error);
      // If the re-run fails too, the fix's own message is the one worth reading, so the
      // report already shown stays.
      const shown = this.report;
      this.report = await getReport().catch(() => shown);
      this.errorMessage = message;
    } finally {
      this.loading = false;
    }
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    if (error && error.message) {
      return error.message;
    }
    return LOAD_FAILED;
  }
}
