import { LightningElement, api } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import getEdition from '@salesforce/apex/SetupAssistantController.getEdition';
import changeEdition from '@salesforce/apex/SetupAssistantController.changeEdition';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import STANDARD_NAME from '@salesforce/label/c.Core_SuiteChoice_StandardName';
import NONPROFIT_NAME from '@salesforce/label/c.Core_SuiteChoice_NonprofitName';
import CHANGE_TOGGLE from '@salesforce/label/c.Core_Edition_ChangeToggle';
import TO_STANDARD from '@salesforce/label/c.Core_Edition_SwitchToStandard';
import TO_NONPROFIT from '@salesforce/label/c.Core_Edition_SwitchToNonprofit';
import CONFIRM_TITLE from '@salesforce/label/c.Core_Edition_ConfirmTitle';
import CONFIRM_BUTTON from '@salesforce/label/c.Core_Edition_ChangeToggle';
import CANCEL_BUTTON from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const STANDARD = 'Standard';
const NONPROFIT = 'Nonprofit';

/**
 * The console's Edition row (ADR-0124): the edition chosen once in the Setup Assistant, shown
 * read-only, with a collapsed Change edition disclosure for those who may change settings.
 * Each switch asks for confirmation first, saying what changes.
 */
export default class EditionSetting extends LightningElement {
  helpReady = isHelpLoaded('Core');

  labels = {
    get notChosen() {
      return helpText('Core', 'Core_Edition_NotChosen');
    },
    changeToggle: CHANGE_TOGGLE,
    get changeIntro() {
      return helpText('Core', 'Core_Edition_ChangeIntro');
    },
    get saved() {
      return helpText('Core', 'Core_Edition_Saved');
    }
  };

  current;
  canEdit = false;
  loaded = false;
  errorMessage;
  savedMessage;
  isSaving = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  /** The console calls this after first-run setup finishes, because this row stays mounted. */
  @api
  refresh() {
    this.errorMessage = undefined;
    return this.load();
  }

  async load() {
    try {
      this.apply(await getEdition());
    } catch (error) {
      this.errorMessage = messageOf(error);
    }
  }

  apply(model) {
    this.current = model && model.currentSuite;
    this.canEdit = Boolean(model && model.canEdit);
    this.loaded = true;
  }

  get editionName() {
    if (this.current === STANDARD) {
      return STANDARD_NAME;
    }
    return this.current === NONPROFIT ? NONPROFIT_NAME : null;
  }

  get switches() {
    const all = [
      { value: STANDARD, label: TO_STANDARD },
      { value: NONPROFIT, label: TO_NONPROFIT }
    ];
    return all.filter((option) => option.value !== this.current);
  }

  async handleSwitch(event) {
    const target = event.target.dataset.value;
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: CONFIRM_TITLE,
      message:
        target === NONPROFIT
          ? helpText('Core', 'Core_Edition_ConfirmToNonprofit')
          : helpText('Core', 'Core_Edition_ConfirmToStandard'),
      confirmLabel: CONFIRM_BUTTON,
      cancelLabel: CANCEL_BUTTON
    });
    if (!confirmed) {
      return;
    }
    this.isSaving = true;
    this.errorMessage = undefined;
    this.savedMessage = undefined;
    try {
      this.apply(await changeEdition({ suite: target }));
      this.savedMessage = helpText('Core', 'Core_Edition_Saved');
    } catch (error) {
      this.errorMessage = messageOf(error);
    } finally {
      this.isSaving = false;
    }
  }
}

function messageOf(error) {
  return (
    (error && error.body && error.body.message) || (error && error.message) || UNEXPECTED_ERROR
  );
}
