import { LightningElement, api } from 'lwc';
import EDITION from '@salesforce/label/c.Core_SuiteChoice_EditionLabel';
import COMMUNITY from '@salesforce/label/c.Core_SuiteChoice_CommunityOption';
import IMPACT from '@salesforce/label/c.Core_SuiteChoice_ImpactOption';
import CONFIRM from '@salesforce/label/c.Core_SetupAssistant_ConfirmButton';
import GIVING_INSTALLED from '@salesforce/label/c.Core_SuiteChoice_GivingInstalled';
import GIVING_NEEDED from '@salesforce/label/c.Core_SuiteChoice_GivingNeeded';
import INSTALL from '@salesforce/label/c.Core_SuiteChoice_InstallButton';
import INSTALL_HELP from '@salesforce/label/c.Core_SuiteChoice_InstallHelp';
import NO_INSTALL_LINK from '@salesforce/label/c.Core_SuiteChoice_NoInstallLink';
import READ_ABOUT from '@salesforce/label/c.Core_SuiteChoice_ReadAbout';
import CHECK_AGAIN from '@salesforce/label/c.Core_SuiteChoice_CheckAgain';
import NEW_TAB from '@salesforce/label/c.Core_SuiteChoice_NewTab';
import STANDARD_NAME from '@salesforce/label/c.Core_SuiteChoice_StandardName';
import NONPROFIT_NAME from '@salesforce/label/c.Core_SuiteChoice_NonprofitName';
import CHOSEN_ONCE from '@salesforce/label/c.Core_SuiteChoice_ChosenOnce';
import CHANGE_HELP from '@salesforce/label/c.Core_SuiteChoice_ChangeHelpLink';

const IMPACT_SUITE = 'Impact';
const COMMUNITY_SUITE = 'Community';
const EDITIONS_GUIDE =
  'https://github.com/Nonprofit-Collaborative/BarnCRM/blob/main/docs/admin-guide/editions.md';

/**
 * Step one: which edition (C-30). Saving it installs nothing: with the Nonprofit Edition
 * saved and Giving not here, the step links to Salesforce's installer in a new tab and
 * offers Check again, so the administrator installs Giving herself
 * (0072-suite-choice-is-the-first-setup-step.md). The edition is chosen once: once saved,
 * the step shows it read-only and links to how to change it later (ADR-NEXT).
 */
export default class SetupStepSuite extends LightningElement {
  @api canEdit = false;

  chosen;

  labels = {
    edition: EDITION,
    confirm: CONFIRM,
    givingInstalled: GIVING_INSTALLED,
    givingNeeded: GIVING_NEEDED,
    install: INSTALL,
    installHelp: INSTALL_HELP,
    noInstallLink: NO_INSTALL_LINK,
    readAbout: READ_ABOUT,
    checkAgain: CHECK_AGAIN,
    newTab: NEW_TAB,
    chosenOnce: CHOSEN_ONCE,
    changeHelp: CHANGE_HELP
  };

  changeHelpUrl = EDITIONS_GUIDE;

  options = [
    { label: COMMUNITY, value: COMMUNITY_SUITE },
    { label: IMPACT, value: IMPACT_SUITE }
  ];

  _suite = {};

  @api
  get suite() {
    return this._suite;
  }

  set suite(value) {
    this._suite = value || {};
    this.chosen = this._suite.currentSuite || this._suite.recommendedSuite;
  }

  get isReadOnly() {
    return !this.canEdit;
  }

  get giving() {
    return this._suite.giving || {};
  }

  /** The saved edition's name, or null while none is saved and the choice is still offered. */
  get savedName() {
    const saved = this._suite.currentSuite;
    if (saved === COMMUNITY_SUITE) {
      return STANDARD_NAME;
    }
    return saved === IMPACT_SUITE ? NONPROFIT_NAME : null;
  }

  get isImpactSaved() {
    return this._suite.currentSuite === IMPACT_SUITE;
  }

  get givingPresent() {
    return Boolean(this.giving.present);
  }

  get installUrl() {
    return this.giving.installUrl;
  }

  get docsUrl() {
    return this.giving.docsUrl;
  }

  handleChange(event) {
    this.chosen = event.detail.value;
  }

  handleConfirm() {
    this.dispatchEvent(new CustomEvent('confirm', { detail: { suite: this.chosen } }));
  }

  handleCheckAgain() {
    this.dispatchEvent(new CustomEvent('checkagain'));
  }
}
