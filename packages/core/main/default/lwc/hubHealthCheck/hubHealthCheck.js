import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import getSettingsLink from '@salesforce/apex/SettingsController.getSettingsLink';
import HEADING from '@salesforce/label/c.Core_HealthCheck_Title';
import LAST_RUN from '@salesforce/label/c.Core_HealthCheck_LastRunLabel';
import LINK from '@salesforce/label/c.Core_HubHome_HealthCheckLink';
import { healthCheckBadge } from 'c/healthCheckBadge';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

// The Org Optimizer page's section name for Health Check, read from its page state.
const HEALTH_CHECK_SECTION = 'healthCheck';

/**
 * The last Health Check result on the BarnCRM home page (ADR-0106, D-217): its badge, when it
 * ran and its counts by severity, with a link to the Health Check section of Org Optimizer.
 * Shown only while the Org Optimizer module is installed (ADR-0233): the home model names its
 * tab only then. Home never runs Health Check; the result is the one the module stored.
 */
export default class HubHealthCheck extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  labels = { heading: HEADING, lastRun: LAST_RUN, link: LINK };

  tab;
  lastRun = { ranAt: null };
  errorMessage;

  /** Only while the module is installed: a home model that fails to load names no tab. */
  get shown() {
    return Boolean(this.tab);
  }

  @wire(getHomeModel)
  wiredModel({ data, error }) {
    if (data) {
      this.tab = data.healthCheckTab;
      this.lastRun = {
        ranAt: data.healthCheckRanAt || null,
        errors: data.healthCheckErrors,
        warnings: data.healthCheckWarnings,
        infos: data.healthCheckInfos
      };
      this.errorMessage = undefined;
    } else if (error) {
      this.errorMessage = helpText('Core', 'Core_HubHome_LoadErrorMessage');
    }
  }

  get hasRun() {
    return Boolean(this.lastRun.ranAt);
  }

  get badge() {
    return healthCheckBadge(this.lastRun);
  }

  /** The badge's status word for c-barn-status-badge: Not Run Yet is neutral. */
  get badgeStatus() {
    return this.badge.badgeVariant || 'neutral';
  }

  get resultText() {
    const { errors, warnings, infos } = this.lastRun;
    return helpText('Core', 'Core_HealthCheck_LastResult')
      .replace('{0}', errors)
      .replace('{1}', warnings)
      .replace('{2}', infos);
  }

  get neverText() {
    return helpText('Core', 'Core_HubHome_HealthCheckNever');
  }

  // The section key is qualified for the org's namespace in Apex, like the tab.
  async handleOpen() {
    try {
      const link = await getSettingsLink();
      this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: { apiName: this.tab },
        state: { [link.sectionKey]: HEALTH_CHECK_SECTION }
      });
    } catch {
      this.errorMessage = helpText('Core', 'Core_HubHome_LoadErrorMessage');
    }
  }
}
