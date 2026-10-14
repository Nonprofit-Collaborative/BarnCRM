import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getState from '@salesforce/apex/FirstRunController.getState';
import finish from '@salesforce/apex/FirstRunController.finish';
import TITLE from '@salesforce/label/c.Core_FirstRun_Title';
import INTRO from '@salesforce/label/c.Core_FirstRun_Intro';
import EDITION_QUESTION from '@salesforce/label/c.Core_FirstRun_EditionQuestion';
import FEATURES_QUESTION from '@salesforce/label/c.Core_FirstRun_FeaturesQuestion';
import ALL_OPTION from '@salesforce/label/c.Core_FirstRun_AllOption';
import CHOOSE_OPTION from '@salesforce/label/c.Core_FirstRun_ChooseOption';
import CHOOSE_HELP from '@salesforce/label/c.Core_FirstRun_ChooseHelp';
import MODULES_NOTE from '@salesforce/label/c.Core_FirstRun_ModulesNote';
import FINISH from '@salesforce/label/c.Core_FirstRun_Finish';
import ADMIN_NEEDED from '@salesforce/label/c.Core_FirstRun_AdminNeeded';
import LOAD_ERROR from '@salesforce/label/c.Core_FirstRun_LoadError';
import COMMUNITY from '@salesforce/label/c.Core_SuiteChoice_CommunityOption';
import IMPACT from '@salesforce/label/c.Core_SuiteChoice_ImpactOption';

const SETTINGS_TAB = 'BarnCRM_Settings';
const GENERAL_SECTION = 'General';
const ALL = 'all';
const CHOOSE = 'choose';

/**
 * First-run setup (ADR-NEXT): a blocking window on BarnCRM Home and BarnCRM Settings until setup
 * is finished (the server decides; a saved edition is pre-selected). Focus stays inside it. An administrator picks the edition and either every feature or the ones
 * left ticked, then lands on General; anyone else is told an administrator needs to finish.
 * It installs no module. Fires `setupfinished` so the page behind it can reload.
 */
export default class FirstRunSetup extends NavigationMixin(LightningElement) {
  labels = {
    title: TITLE,
    intro: INTRO,
    editionQuestion: EDITION_QUESTION,
    featuresQuestion: FEATURES_QUESTION,
    chooseHelp: CHOOSE_HELP,
    modulesNote: MODULES_NOTE,
    finish: FINISH,
    adminNeeded: ADMIN_NEEDED
  };

  editionOptions = [
    { label: COMMUNITY, value: 'Community' },
    { label: IMPACT, value: 'Impact' }
  ];

  modeOptions = [
    { label: ALL_OPTION, value: ALL },
    { label: CHOOSE_OPTION, value: CHOOSE }
  ];

  state;
  edition;
  mode = ALL;
  unticked = new Set();
  busy = false;
  errorMessage;
  loadError;
  focused = false;

  async connectedCallback() {
    try {
      this.state = await getState();
      this.edition = this.state && this.state.recommendedSuite;
    } catch (error) {
      // A page that cannot tell is not blocked (the window shows only when setup is known to
      // be unfinished), but it says so above the page rather than failing silently.
      this.state = undefined;
      this.loadError = messageOf(error) || LOAD_ERROR;
    }
  }

  /** Puts focus in the window the first time it shows, so the keyboard starts inside it. */
  renderedCallback() {
    if (!this.show || this.focused) {
      return;
    }
    this.focused = true;
    const first = this.focusables()[0] || this.dialog();
    if (first) {
      first.focus();
    }
  }

  get show() {
    return Boolean(this.state && this.state.needsSetup);
  }

  dialog() {
    return this.template.querySelector('[data-id="first-run"]');
  }

  /** The window's controls in order, skipping a disabled one. */
  focusables() {
    return Array.from(
      this.template.querySelectorAll('lightning-radio-group, lightning-input, lightning-button')
    ).filter((control) => !control.disabled);
  }

  /** Keeps Tab and Shift+Tab inside the window: the page behind it cannot be used. */
  handleKeyDown(event) {
    if (event.key !== 'Tab') {
      return;
    }
    const controls = this.focusables();
    if (controls.length === 0) {
      event.preventDefault();
      this.dialog().focus();
      return;
    }
    const first = controls[0];
    const last = controls[controls.length - 1];
    const current = controls.find((control) => control === event.target);
    if (event.shiftKey && (!current || current === first)) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && (!current || current === last)) {
      event.preventDefault();
      first.focus();
    }
  }

  get canFinish() {
    return Boolean(this.state && this.state.canFinish);
  }

  get isChoosing() {
    return this.mode === CHOOSE;
  }

  get features() {
    return ((this.state && this.state.features) || []).map((feature) => ({
      ...feature,
      checked: feature.isOn || !this.unticked.has(feature.key),
      disabled: feature.isOn || this.busy
    }));
  }

  get finishDisabled() {
    return this.busy || !this.edition;
  }

  handleEdition(event) {
    this.edition = event.detail.value;
  }

  handleMode(event) {
    this.mode = event.detail.value;
  }

  handleFeature(event) {
    const key = event.target.dataset.key;
    const unticked = new Set(this.unticked);
    if (event.target.checked) {
      unticked.delete(key);
    } else {
      unticked.add(key);
    }
    this.unticked = unticked;
  }

  async handleFinish() {
    const keys = this.features
      .filter((feature) => !this.isChoosing || feature.checked)
      .map((feature) => feature.key);
    this.busy = true;
    this.errorMessage = undefined;
    try {
      this.state = await finish({ suite: this.edition, featureKeys: keys });
      this.dispatchEvent(new CustomEvent('setupfinished'));
      this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: { apiName: SETTINGS_TAB },
        state: { c__section: GENERAL_SECTION }
      });
    } catch (error) {
      this.errorMessage = messageOf(error);
    } finally {
      this.busy = false;
    }
  }
}

function messageOf(error) {
  return (error && error.body && error.body.message) || (error && error.message) || '';
}
