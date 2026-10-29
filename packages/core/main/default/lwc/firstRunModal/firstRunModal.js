import LightningModal from 'lightning/modal';
import { api } from 'lwc';
import finish from '@salesforce/apex/FirstRunController.finish';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
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
import CLOSE from '@salesforce/label/c.Core_FirstRun_Close';
import STANDARD_NAME from '@salesforce/label/c.Core_SuiteChoice_StandardName';
import NONPROFIT_NAME from '@salesforce/label/c.Core_SuiteChoice_NonprofitName';
import STANDARD_LINE from '@salesforce/label/c.Core_FirstRun_StandardLine';
import NONPROFIT_LINE from '@salesforce/label/c.Core_FirstRun_NonprofitLine';

const ALL = 'all';
const CHOOSE = 'choose';

/**
 * The first-run setup window (ADR-0124) as a platform modal, so focus, Escape and the dialog
 * semantics are the platform's. It cannot be closed until setup is finished: an administrator
 * picks the edition (two picker cards) and either every feature or the ones left ticked;
 * anyone else reads that an administrator needs to finish. Resolves `{ finished: true }`.
 * Opened by c/firstRunSetup with the state it read.
 */
export default class FirstRunModal extends LightningModal {
  /** FirstRunController.getState's answer. */
  @api state;

  labels = {
    title: TITLE,
    intro: INTRO,
    editionQuestion: EDITION_QUESTION,
    featuresQuestion: FEATURES_QUESTION,
    chooseHelp: CHOOSE_HELP,
    modulesNote: MODULES_NOTE,
    finish: FINISH,
    adminNeeded: ADMIN_NEEDED,
    close: CLOSE
  };

  editionOptions = [
    {
      value: 'Community',
      label: STANDARD_NAME,
      description: STANDARD_LINE,
      iconName: 'standard:household'
    },
    {
      value: 'Impact',
      label: NONPROFIT_NAME,
      description: NONPROFIT_LINE,
      iconName: 'standard:currency'
    }
  ];

  modeOptions = [
    { label: ALL_OPTION, value: ALL },
    { label: CHOOSE_OPTION, value: CHOOSE }
  ];

  edition;
  mode = ALL;
  unticked = new Set();
  busy = false;
  errorMessage;

  connectedCallback() {
    // Setup is not optional for an administrator: neither Escape nor the close button
    // dismisses the window (c/firstRunSetup also opens it with disableClose, which is what
    // makes the platform's close button disabled rather than merely inert). Someone who
    // cannot finish is never trapped: they read why and close it.
    this.disableClose = this.canFinish;
    this.edition = this.state && this.state.recommendedSuite;
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

  handleClose() {
    this.close();
  }

  async handleFinish() {
    const keys = this.features
      .filter((feature) => !this.isChoosing || feature.checked)
      .map((feature) => feature.key);
    this.busy = true;
    this.errorMessage = undefined;
    try {
      await finish({ suite: this.edition, featureKeys: keys });
      this.disableClose = false;
      this.close({ finished: true });
    } catch (error) {
      this.errorMessage =
        (error && error.body && error.body.message) || (error && error.message) || UNEXPECTED_ERROR;
    } finally {
      this.busy = false;
    }
  }
}
