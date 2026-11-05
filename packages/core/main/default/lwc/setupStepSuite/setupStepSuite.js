import { LightningElement, api } from 'lwc';
import EDITION from '@salesforce/label/c.Core_SuiteChoice_EditionLabel';
import INSTALL from '@salesforce/label/c.Core_SuiteChoice_InstallButton';
import READ_ABOUT from '@salesforce/label/c.Core_SuiteChoice_ReadAbout';
import CHECK_AGAIN from '@salesforce/label/c.Core_SuiteChoice_CheckAgain';
import NEW_TAB from '@salesforce/label/c.Core_Kit_NewTab';
import STANDARD_NAME from '@salesforce/label/c.Core_SuiteChoice_StandardName';
import NONPROFIT_NAME from '@salesforce/label/c.Core_SuiteChoice_NonprofitName';
import CHANGE_HELP from '@salesforce/label/c.Core_SuiteChoice_ChangeHelpLink';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const NONPROFIT_SUITE = 'Nonprofit';
const STANDARD_SUITE = 'Standard';
const EDITIONS_GUIDE =
  'https://github.com/Nonprofit-Collaborative/BarnCRM/blob/main/docs/admin-guide/editions.md';

/**
 * Step one: which edition (C-30). Saving it installs nothing: with the Nonprofit Edition
 * saved and Giving not here, the step links to Salesforce's installer in a new tab and
 * offers Check again, so the administrator installs Giving herself
 * (0072-suite-choice-is-the-first-setup-step.md). The edition is asked once, in first-run
 * setup (c/firstRunModal): this step shows that same answer read-only and links to how to
 * change it later, and never asks it a second time (ADR-0124).
 */
export default class SetupStepSuite extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  @api canEdit = false;

  labels = {
    edition: EDITION,
    get chooseInFirstRun() {
      return helpText('Core', 'Core_SuiteChoice_ChooseInFirstRun');
    },
    get givingInstalled() {
      return helpText('Core', 'Core_SuiteChoice_GivingInstalled');
    },
    get givingNeeded() {
      return helpText('Core', 'Core_SuiteChoice_GivingNeeded');
    },
    install: INSTALL,
    get installHelp() {
      return helpText('Core', 'Core_SuiteChoice_InstallHelp');
    },
    get noInstallLink() {
      return helpText('Core', 'Core_SuiteChoice_NoInstallLink');
    },
    readAbout: READ_ABOUT,
    checkAgain: CHECK_AGAIN,
    newTab: NEW_TAB,
    get chosenOnce() {
      return helpText('Core', 'Core_SuiteChoice_ChosenOnce');
    },
    changeHelp: CHANGE_HELP
  };

  changeHelpUrl = EDITIONS_GUIDE;

  _suite = {};

  @api
  get suite() {
    return this._suite;
  }

  set suite(value) {
    this._suite = value || {};
  }

  get giving() {
    return this._suite.giving || {};
  }

  /** The saved edition's name, or null while none is saved (the first-run window asks it). */
  get savedName() {
    const saved = this._suite.currentSuite;
    if (saved === STANDARD_SUITE) {
      return STANDARD_NAME;
    }
    return saved === NONPROFIT_SUITE ? NONPROFIT_NAME : null;
  }

  get isNonprofitSaved() {
    return this._suite.currentSuite === NONPROFIT_SUITE;
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

  handleCheckAgain() {
    this.dispatchEvent(new CustomEvent('checkagain'));
  }
}
