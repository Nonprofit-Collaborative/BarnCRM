import { LightningElement, api } from 'lwc';
import getState from '@salesforce/apex/ModuleManagerController.getState';
import saveShowNonprofitModules from '@salesforce/apex/ModuleManagerController.saveShowNonprofitModules';
import turnOff from '@salesforce/apex/ModuleManagerController.turnOff';
import turnOn from '@salesforce/apex/ModuleManagerController.turnOn';
import grantAdminAccess from '@salesforce/apex/ModuleManagerController.grantAdminAccess';
import uninstallReport from '@salesforce/apex/ModuleManagerController.uninstallReport';

import STATUS_ON from '@salesforce/label/c.Core_ModuleManager_StatusOn';
import STATUS_OFF from '@salesforce/label/c.Core_ModuleManager_StatusOff';
import STATUS_NOT_INSTALLED from '@salesforce/label/c.Core_ModuleManager_StatusNotInstalled';
import LEARN_MORE from '@salesforce/label/c.Core_SetupAssistant_ModuleLearnMore';
import NEW_TAB from '@salesforce/label/c.Core_SuiteChoice_NewTab';
import INSTALL from '@salesforce/label/c.Core_SuiteChoice_ModuleInstallLink';
import NO_INSTALL_LINK from '@salesforce/label/c.Core_ModuleManager_NoInstallLink';
import TURN_OFF from '@salesforce/label/c.Core_ModuleManager_TurnOffButton';
import TURN_ON from '@salesforce/label/c.Core_ModuleManager_TurnOnButton';
import REPORT from '@salesforce/label/c.Core_ModuleManager_ReportButton';
import REPORT_INTRO from '@salesforce/label/c.Core_ModuleManager_ReportIntro';
import REPORT_EMPTY from '@salesforce/label/c.Core_ModuleManager_ReportEmpty';
import INSTALLED_PACKAGES from '@salesforce/label/c.Core_ModuleManager_InstalledPackagesLink';
import TABS_NOTICE from '@salesforce/label/c.Core_ModuleManager_TabsNotice';
import CHECK_AGAIN from '@salesforce/label/c.Core_SuiteChoice_CheckAgain';
import READ_ONLY from '@salesforce/label/c.Core_ModuleManager_ReadOnlyNotice';
import LOAD_ERROR from '@salesforce/label/c.Core_ModuleManager_LoadErrorMessage';
import OPEN_APP from '@salesforce/label/c.Core_ModuleManager_OpenApp';
import INSTALL_FIRST from '@salesforce/label/c.Core_ModuleManager_InstallFirst';
import NONPROFIT_TITLE from '@salesforce/label/c.Core_ModuleManager_NonprofitTitle';
import SHOW_NONPROFIT from '@salesforce/label/c.Core_ModuleManager_ShowNonprofit';
import NONPROFIT_HIDDEN from '@salesforce/label/c.Core_ModuleManager_NonprofitHidden';

const STATUS_TEXT = { On: STATUS_ON, Off: STATUS_OFF, NotInstalled: STATUS_NOT_INSTALLED };
const INSTALLED_PACKAGES_URL = '/lightning/setup/ImportedPackage/home';

/**
 * The Module Manager (C-24), the BarnCRM Settings Modules section (ADR-0124): every module this
 * org is offered by its "BarnCRM X" name, whether it is installed and on, a link to an installed
 * module's own app, and the one thing to do next with it. Installing and uninstalling are Salesforce's own
 * screens, opened from here; nothing is installed or removed by BarnCRM
 * (0073-module-manager-turns-automation-off-and-never-installs.md).
 *
 * The modules only the Nonprofit Edition offers (`nonprofitOnly`, from the catalog's editions)
 * are listed last, in their own section with a Show Nonprofit Modules checkbox that is on until
 * an administrator clears it. Clearing it hides those rows only, and a line counts the installed
 * ones it hides so none disappears without a cue.
 */
export default class ModuleManager extends LightningElement {
  state;
  showNonprofit = true;
  reports = {};
  errorMessage;
  installedPackagesUrl = INSTALLED_PACKAGES_URL;

  labels = {
    learnMore: LEARN_MORE,
    newTab: NEW_TAB,
    install: INSTALL,
    noInstallLink: NO_INSTALL_LINK,
    turnOff: TURN_OFF,
    turnOn: TURN_ON,
    report: REPORT,
    reportIntro: REPORT_INTRO,
    reportEmpty: REPORT_EMPTY,
    installedPackages: INSTALLED_PACKAGES,
    tabsNotice: TABS_NOTICE,
    checkAgain: CHECK_AGAIN,
    readOnly: READ_ONLY,
    openApp: OPEN_APP,
    nonprofitTitle: NONPROFIT_TITLE,
    showNonprofit: SHOW_NONPROFIT
  };

  connectedCallback() {
    this.load();
  }

  load() {
    return this.run(getState, {});
  }

  /** The console calls this after first-run setup finishes, because this row stays mounted. */
  @api
  refresh() {
    return this.load();
  }

  get canEdit() {
    return Boolean(this.state && this.state.canEdit);
  }

  get isReadOnly() {
    return Boolean(this.state) && !this.state.canEdit;
  }

  get rows() {
    const modules = (this.state && this.state.modules) || [];
    return modules.map((module) => {
      const report = this.reports[module.name];
      return {
        ...module,
        displayName: module.label || module.name,
        statusText: STATUS_TEXT[module.status] || module.status,
        badgeClass:
          module.status === 'On'
            ? 'slds-badge slds-theme_success slds-var-m-left_x-small'
            : 'slds-badge slds-var-m-left_x-small',
        isOn: module.canSwitch && module.status === 'On',
        isOff: module.canSwitch && module.status === 'Off',
        showInstall: module.status === 'NotInstalled' && Boolean(module.installUrl),
        noInstallLink: module.status === 'NotInstalled' && !module.installUrl,
        installFirstText:
          module.status === 'NotInstalled' && module.installFirst
            ? INSTALL_FIRST.replace('{0}', module.installFirst)
            : null,
        hasReport: Boolean(report),
        reportEmpty: Boolean(report) && report.length === 0,
        report: (report || []).map((line) => ({
          ...line,
          countText: `${Number(line.count).toLocaleString()}${line.capped ? '+' : ''}`
        }))
      };
    });
  }

  /**
   * The rows in two groups: the modules both editions offer, then the nonprofit-only ones in a
   * section of their own. The section exists only when the list holds a nonprofit module.
   */
  get groups() {
    const rows = this.rows;
    const groups = [
      {
        key: 'general',
        isNonprofit: false,
        showRows: true,
        rows: rows.filter((r) => !r.nonprofitOnly)
      }
    ];
    const nonprofit = rows.filter((r) => r.nonprofitOnly);
    if (nonprofit.length) {
      const hidden = this.showNonprofit
        ? 0
        : nonprofit.filter((r) => r.status !== 'NotInstalled').length;
      groups.push({
        key: 'nonprofit',
        isNonprofit: true,
        showRows: this.showNonprofit,
        rows: nonprofit,
        hiddenText: hidden ? NONPROFIT_HIDDEN.replace('{0}', String(hidden)) : null
      });
    }
    return groups;
  }

  async handleShowNonprofitChange(event) {
    const checked = event.target.checked;
    this.showNonprofit = checked;
    const saved = await this.run(saveShowNonprofitModules, { show: checked });
    if (!saved) {
      this.showNonprofit = !checked;
    }
  }

  handleCheckAgain() {
    this.reports = {};
    this.load();
  }

  handleTurnOff(event) {
    this.run(turnOff, { moduleName: event.target.dataset.name });
  }

  // Turning on and giving the admin set are two calls: a permission set assignment cannot
  // share a transaction with the settings write.
  async handleTurnOn(event) {
    const moduleName = event.target.dataset.name;
    if (await this.run(turnOn, { moduleName })) {
      try {
        await grantAdminAccess({ moduleName });
      } catch (error) {
        this.errorMessage = this.messageFrom(error);
      }
    }
  }

  async handleReport(event) {
    const moduleName = event.target.dataset.name;
    try {
      const lines = await uninstallReport({ moduleName });
      this.reports = { ...this.reports, [moduleName]: lines || [] };
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    }
  }

  async run(action, parameters) {
    try {
      this.state = await action(parameters);
      // A blank value counts as on, which is how the setting ships.
      this.showNonprofit = this.state.showNonprofitModules !== false;
      this.errorMessage = undefined;
      return true;
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
      return false;
    }
  }

  messageFrom(error) {
    return error && error.body && error.body.message ? error.body.message : LOAD_ERROR;
  }
}
