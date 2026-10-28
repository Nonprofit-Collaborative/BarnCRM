import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import createHousehold from '@salesforce/apex/HubController.createHousehold';
import WELCOME_HEADING from '@salesforce/label/c.Core_HubHome_WelcomeHeading';
import WELCOME_MESSAGE from '@salesforce/label/c.Core_HubHome_WelcomeMessage';
import WELCOME_MESSAGE_READY from '@salesforce/label/c.Core_HubHome_WelcomeMessageReady';
import PAUSED_BANNER from '@salesforce/label/c.Core_HubHome_AutomationPausedBanner';
import LOAD_ERROR from '@salesforce/label/c.Core_HubHome_LoadErrorMessage';
import NEW_HOUSEHOLD from '@salesforce/label/c.Core_HubHomeActions_NewHousehold';
import NEW_HOUSEHOLD_FAILED from '@salesforce/label/c.Core_HubHomeActions_NewHouseholdFailed';

/**
 * The top of the BarnCRM home page, for everyone: the welcome, the New household button and
 * the paused automation banner. The other tiles are separate components on the Lightning page,
 * so an administrator can move or remove each one in the Lightning App Builder.
 *
 * New household creates the household in Apex and opens it. No user is given the Household
 * record type (ADR-0141), so the standard New form cannot make one.
 */
export default class HubWelcome extends NavigationMixin(LightningElement) {
  labels = {
    welcomeHeading: WELCOME_HEADING,
    pausedBanner: PAUSED_BANNER,
    newHousehold: NEW_HOUSEHOLD
  };

  model;
  errorMessage;
  createError;
  creating = false;

  // Cacheable, so every home page tile wiring it shares one server call.
  @wire(getHomeModel)
  wiredModel({ data, error }) {
    if (data) {
      this.model = data;
      this.errorMessage = undefined;
    } else if (error) {
      this.model = undefined;
      this.errorMessage = LOAD_ERROR;
    }
  }

  /**
   * "Start with the setup checklist" only to the person who can finish it, and only while
   * there is something left to finish. Everyone else is pointed at the tabs.
   */
  get welcomeMessage() {
    const model = this.model;
    const setupPending =
      model &&
      model.canEdit &&
      !(model.stepsTotal > 0 && model.stepsCompleted === model.stepsTotal);
    return setupPending ? WELCOME_MESSAGE : WELCOME_MESSAGE_READY;
  }

  get automationPaused() {
    return Boolean(this.model && this.model.automationPaused);
  }

  /** Only for someone who can create and edit accounts, in an org with the Household record type. */
  get showNewHouseholdButton() {
    return Boolean(this.model && this.model.canCreateHousehold);
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
      this.createError = message || NEW_HOUSEHOLD_FAILED.replace('{0}', '').trim();
    } finally {
      this.creating = false;
    }
  }
}
