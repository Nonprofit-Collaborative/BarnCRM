import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import WELCOME_HEADING from '@salesforce/label/c.Core_HubHome_WelcomeHeading';
import WELCOME_MESSAGE from '@salesforce/label/c.Core_HubHome_WelcomeMessage';
import WELCOME_MESSAGE_READY from '@salesforce/label/c.Core_HubHome_WelcomeMessageReady';
import PAUSED_BANNER from '@salesforce/label/c.Core_HubHome_AutomationPausedBanner';
import LOAD_ERROR from '@salesforce/label/c.Core_HubHome_LoadErrorMessage';
import NEW_HOUSEHOLD from '@salesforce/label/c.Core_HubHomeActions_NewHousehold';
import NEW_HOUSEHOLD_NAME_PLACEHOLDER from '@salesforce/label/c.Core_Households_NamePlaceholder';

const HOUSEHOLD_RECORD_TYPE = 'Household';

/**
 * The top of the BarnCRM home page, for everyone: the welcome, the New household button and
 * the paused automation banner. The other tiles are separate components on the Lightning page,
 * so an administrator can move or remove each one in the Lightning App Builder.
 */
export default class HubWelcome extends NavigationMixin(LightningElement) {
  labels = {
    welcomeHeading: WELCOME_HEADING,
    pausedBanner: PAUSED_BANNER,
    newHousehold: NEW_HOUSEHOLD
  };

  model;
  errorMessage;
  householdRecordTypeId;
  accountCreatable = false;

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

  @wire(getObjectInfo, { objectApiName: 'Account' })
  wiredAccountInfo({ data }) {
    if (!data) {
      this.householdRecordTypeId = undefined;
      this.accountCreatable = false;
      return;
    }
    const infos = data.recordTypeInfos || {};
    // Only a record type this user may use: without it the New form fails or opens with
    // another record type (as for people in #221).
    this.householdRecordTypeId = Object.keys(infos).find(
      (id) =>
        infos[id].available === true &&
        (infos[id].developerName === HOUSEHOLD_RECORD_TYPE ||
          infos[id].name === HOUSEHOLD_RECORD_TYPE)
    );
    this.accountCreatable = Boolean(data.createable);
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

  /** Hidden until the household record type is known and until Account is createable at all. */
  get showNewHouseholdButton() {
    return this.accountCreatable && !!this.householdRecordTypeId;
  }

  handleNewHousehold() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: {
        objectApiName: 'Account',
        actionName: 'new'
      },
      state: {
        recordTypeId: this.householdRecordTypeId,
        defaultFieldValues: encodeDefaultFieldValues({
          // Account.Name is required by the platform and the naming service overwrites it
          // once a member is added, so the New form gets the same placeholder rather than
          // making the user invent a name that will not stick.
          Name: NEW_HOUSEHOLD_NAME_PLACEHOLDER
        })
      }
    });
  }
}
