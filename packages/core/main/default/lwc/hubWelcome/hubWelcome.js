import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import createHousehold from '@salesforce/apex/HubController.createHousehold';
import WELCOME_HEADING from '@salesforce/label/c.Core_HubHome_WelcomeHeading';
import NEW_HOUSEHOLD from '@salesforce/label/c.Core_HubHomeActions_NewHousehold';
import NEW_PERSON from '@salesforce/label/c.Core_HubHomeActions_NewPerson';
import RESUME from '@salesforce/label/c.Core_AutomationControl_ResumeButton';
import getSettingsLink from '@salesforce/apex/SettingsController.getSettingsLink';
import PATCH_WELCOME from '@salesforce/resourceUrl/BarnPatchWelcome';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const AUTOMATION_SECTION = 'Automation';

/**
 * The top of the BarnCRM home page, for everyone: the welcome, New Person and New Household,
 * and the paused automation notice. The other tiles are separate components on the Lightning
 * page, so an administrator can move or remove each one in the Lightning App Builder.
 *
 * New Person opens the standard Contact New form, so the org's own layout, duplicate and
 * validation rules apply and the household is made automatically (people-giving-7).
 * New Household creates the household in Apex and opens it. No user is given the Household
 * record type (ADR-0141), so the standard New form cannot make one.
 */
export default class HubWelcome extends NavigationMixin(LightningElement) {
  labels = {
    welcomeHeading: WELCOME_HEADING,
    get pausedBanner() {
      return helpText('Core', 'Core_HubHome_AutomationPausedBanner');
    },
    get patchAlt() {
      return helpText('Core', 'Core_HubHome_PatchAlt');
    },
    newHousehold: NEW_HOUSEHOLD,
    newPerson: NEW_PERSON
  };

  iconName = iconFor('BarnCRM_Home');
  // Patch, the BarnCRM mascot, waving beside the welcome (ADR-NEXT); hidden on small screens.
  patchUrl = PATCH_WELCOME;
  helpReady = isHelpLoaded('Core');
  model;
  errorMessage;
  createError;
  creating = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  // Cacheable, so every home page tile wiring it shares one server call.
  @wire(getHomeModel)
  wiredModel({ data, error }) {
    if (data) {
      this.model = data;
      this.errorMessage = undefined;
    } else if (error) {
      this.model = undefined;
      this.errorMessage = helpText('Core', 'Core_HubHome_LoadErrorMessage');
    }
  }

  /**
   * "Start with the setup checklist" only to the person who can finish it, and only while
   * there is something left to finish. Everyone else is told what the page is for.
   */
  get welcomeMessage() {
    const model = this.model;
    const setupPending =
      model &&
      model.canEdit &&
      !(model.stepsTotal > 0 && model.stepsCompleted === model.stepsTotal);
    return setupPending
      ? helpText('Core', 'Core_HubHome_WelcomeMessage')
      : helpText('Core', 'Core_HubHome_WelcomeEveryday');
  }

  get automationPaused() {
    return Boolean(this.model && this.model.automationPaused);
  }

  /** Resume is an administrator's action, on the Automation section of BarnCRM Settings. */
  get canResume() {
    return Boolean(this.model && this.model.canEdit);
  }

  get resumeLabel() {
    return this.canResume ? RESUME : undefined;
  }

  // The tab and the section key are qualified for the org's namespace in Apex.
  async handleResume() {
    try {
      const link = await getSettingsLink();
      this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: { apiName: link.tabApiName },
        state: { [link.sectionKey]: AUTOMATION_SECTION }
      });
    } catch {
      this.errorMessage = helpText('Core', 'Core_HubHome_LoadErrorMessage');
    }
  }

  /** Only for someone who can create contacts. */
  get showNewPersonButton() {
    return Boolean(this.model && this.model.canCreatePerson);
  }

  /** Only for someone who can create and edit accounts, in an org with the Household record type. */
  get showNewHouseholdButton() {
    return Boolean(this.model && this.model.canCreateHousehold);
  }

  /** One brand button on the card: New Person when it is there, New Household otherwise. */
  get newHouseholdVariant() {
    return this.showNewPersonButton ? 'neutral' : 'brand';
  }

  handleNewPerson() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Contact', actionName: 'new' }
    });
  }

  async handleNewHousehold() {
    if (this.creating) {
      return;
    }
    this.creating = true;
    this.createError = undefined;
    try {
      const recordId = await createHousehold();
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: {
          recordId,
          objectApiName: 'Account',
          actionName: 'view'
        }
      });
    } catch (error) {
      const message = error && error.body && error.body.message;
      this.createError =
        message ||
        helpText('Core', 'Core_HubHomeActions_NewHouseholdFailed').replace('{0}', '').trim();
    } finally {
      this.creating = false;
    }
  }
}
