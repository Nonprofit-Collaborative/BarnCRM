import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import countInstallProblems from '@salesforce/apex/CorePostInstall.countInstallProblems';
import WELCOME_HEADING from '@salesforce/label/c.Core_HubHome_WelcomeHeading';
import WELCOME_MESSAGE from '@salesforce/label/c.Core_HubHome_WelcomeMessage';
import CHECKLIST_HEADING from '@salesforce/label/c.Core_HubHome_ChecklistHeading';
import PAUSED_BANNER from '@salesforce/label/c.Core_HubHome_AutomationPausedBanner';
import ERROR_TILE_HEADING from '@salesforce/label/c.Core_HubHome_ErrorTileHeading';
import ERROR_TILE_LINK from '@salesforce/label/c.Core_HubHome_ErrorTileLinkLabel';
import INSTALL_COMPLETED from '@salesforce/label/c.Core_HubHome_InstallCompleted';
import INSTALL_PROBLEMS from '@salesforce/label/c.Core_HubHome_InstallProblems';
import QUICK_LINKS_HEADING from '@salesforce/label/c.Core_HubHome_QuickLinksHeading';
import QUICK_LINK_SETTINGS from '@salesforce/label/c.Core_HubHome_QuickLinkSettings';
import QUICK_LINK_HOUSEHOLDS from '@salesforce/label/c.Core_HubHome_QuickLinkHouseholds';
import QUICK_LINK_ORGANIZATIONS from '@salesforce/label/c.Core_HubHome_QuickLinkOrganizations';
import LOAD_ERROR from '@salesforce/label/c.Core_HubHome_LoadErrorMessage';
import SETUP_COMPLETE_HEADING from '@salesforce/label/c.Core_SetupAssistant_CompleteTileHeading';
import REOPEN_SETUP from '@salesforce/label/c.Core_SetupAssistant_ReopenButton';
import PROGRESS_FORMAT from '@salesforce/label/c.Core_SetupAssistant_ProgressFormat';
import ROLLUPS_HEADING from '@salesforce/label/c.Core_Rollups_FreshnessTitle';
import ROLLUPS_NEVER from '@salesforce/label/c.Core_Rollups_FreshnessNever';
import ROLLUPS_STALE from '@salesforce/label/c.Core_Rollups_FreshnessStale';
import ROLLUPS_LINK from '@salesforce/label/c.Core_Rollups_FreshnessLink';
import SEASONAL_HEADING from '@salesforce/label/c.Core_SeasonalAddress_HubTitle';
import SEASONAL_NEVER from '@salesforce/label/c.Core_SeasonalAddress_NeverRun';
import SEASONAL_NOT_SCHEDULED from '@salesforce/label/c.Core_SeasonalAddress_NotScheduled';
import SEASONAL_STALE from '@salesforce/label/c.Core_SeasonalAddress_Stale';
import SEASONAL_LINK from '@salesforce/label/c.Core_SeasonalAddress_HubLink';
import RECURRING_HEADING from '@salesforce/label/c.Core_HubHome_RecurringHeading';
import RECURRING_NEVER from '@salesforce/label/c.Core_HubHome_RecurringNever';
import RECURRING_LINK from '@salesforce/label/c.Core_HubHome_RecurringLink';
import NEW_HOUSEHOLD from '@salesforce/label/c.Core_HubHomeActions_NewHousehold';
import NEW_HOUSEHOLD_NAME_PLACEHOLDER from '@salesforce/label/c.Core_Households_NamePlaceholder';

const HOUSEHOLD_RECORD_TYPE = 'Household';

export default class HubHome extends NavigationMixin(LightningElement) {
  labels = {
    welcomeHeading: WELCOME_HEADING,
    welcomeMessage: WELCOME_MESSAGE,
    checklistHeading: CHECKLIST_HEADING,
    pausedBanner: PAUSED_BANNER,
    errorTileHeading: ERROR_TILE_HEADING,
    errorTileLink: ERROR_TILE_LINK,
    installCompleted: INSTALL_COMPLETED,
    installProblems: INSTALL_PROBLEMS,
    quickLinksHeading: QUICK_LINKS_HEADING,
    loadError: LOAD_ERROR,
    setupCompleteHeading: SETUP_COMPLETE_HEADING,
    reopenSetup: REOPEN_SETUP,
    rollupsHeading: ROLLUPS_HEADING,
    rollupsNever: ROLLUPS_NEVER,
    rollupsStale: ROLLUPS_STALE,
    rollupsLink: ROLLUPS_LINK,
    seasonalHeading: SEASONAL_HEADING,
    seasonalNever: SEASONAL_NEVER,
    seasonalNotScheduled: SEASONAL_NOT_SCHEDULED,
    seasonalStale: SEASONAL_STALE,
    seasonalLink: SEASONAL_LINK,
    recurringHeading: RECURRING_HEADING,
    recurringNever: RECURRING_NEVER,
    recurringLink: RECURRING_LINK,
    newHousehold: NEW_HOUSEHOLD
  };

  quickLinks = [
    { key: 'settings', label: QUICK_LINK_SETTINGS, url: '/lightning/n/Nonprofit_Settings' },
    { key: 'households', label: QUICK_LINK_HOUSEHOLDS, url: '/lightning/n/Households' },
    {
      key: 'organizations',
      label: QUICK_LINK_ORGANIZATIONS,
      url: '/lightning/n/Organizations'
    }
  ];

  errorLogUrl = '/lightning/o/Error_Log__c/list';
  rollupsUrl = '/lightning/n/Nonprofit_Settings';
  addressSettingsUrl = '/lightning/n/Nonprofit_Settings';
  importUrl = '/lightning/n/Import';

  /** The files that arrive regularly, oldest import first (R-IT6). */
  recurringSources = [];

  rollupsLastCalculated;
  rollupsStale = false;

  seasonalAddressLastRun;
  seasonalAddressLastRunSummary;
  seasonalAddressScheduled = false;
  seasonalAddressStale = false;

  stepsCompleted = 0;
  stepsTotal = 0;
  automationPaused = false;
  newErrorCount = 0;
  newErrorCountCapped = false;
  canEdit = false;
  errorMessage;
  setupReopened = false;

  // How many problems the install logged, or undefined for someone who cannot read the log.
  installProblemCount;

  householdRecordTypeId;
  accountCreatable = false;

  connectedCallback() {
    this.load();
  }

  @wire(getObjectInfo, { objectApiName: 'Account' })
  wiredAccountInfo({ data }) {
    if (!data) {
      this.householdRecordTypeId = undefined;
      this.accountCreatable = false;
      return;
    }
    const infos = data.recordTypeInfos || {};
    this.householdRecordTypeId = Object.keys(infos).find(
      (id) =>
        infos[id].developerName === HOUSEHOLD_RECORD_TYPE ||
        infos[id].name === HOUSEHOLD_RECORD_TYPE
    );
    this.accountCreatable = Boolean(data.createable);
  }

  /** Hidden until the household record type is known and until Account is createable at all. */
  get showNewHouseholdButton() {
    return this.accountCreatable && !!this.householdRecordTypeId;
  }

  /** The tile's number: the count, or the cap with a plus once there are more than it counts. */
  get errorCountText() {
    return this.newErrorCountCapped ? `${this.newErrorCount}+` : `${this.newErrorCount}`;
  }

  get hasErrors() {
    return this.newErrorCount > 0;
  }

  /**
   * A partly failed install used to look exactly like a good one: every step writes its
   * failure to the Error Log and carries on. One line says which it was, and only to a person
   * who can read the log, because a count they cannot see is not evidence either way.
   */
  get hasInstallStatus() {
    return this.installProblemCount !== undefined && this.installProblemCount !== null;
  }

  get installHadProblems() {
    return this.installProblemCount > 0;
  }

  get installStatusText() {
    return this.installHadProblems
      ? this.labels.installProblems.replace('{0}', this.installProblemCount)
      : this.labels.installCompleted;
  }

  get hasRollupTime() {
    return !!this.rollupsLastCalculated;
  }

  get hasSeasonalRun() {
    return !!this.seasonalAddressLastRun;
  }

  /**
   * The tile says one of two things when the swap is not running: not scheduled at all, which
   * is a choice somebody can make, or scheduled and overdue, which is a fault. Saying both at
   * once would be noise, so the missing schedule is only shown when there is no fault to show.
   */
  get seasonalNotScheduled() {
    return !this.seasonalAddressScheduled && !this.seasonalAddressStale;
  }

  /** The assistant is the home page until it is finished, and one click away after that. */
  get showAssistant() {
    return this.setupReopened || !this.setupComplete;
  }

  get setupComplete() {
    return this.stepsTotal > 0 && this.stepsCompleted === this.stepsTotal;
  }

  // The same translatable sentence the assistant shows, from the same label.
  get setupProgressText() {
    return PROGRESS_FORMAT.replace('{0}', this.stepsCompleted).replace('{1}', this.stepsTotal);
  }

  async load() {
    try {
      this.applyModel(await getHomeModel());
      this.errorMessage = undefined;
    } catch {
      this.errorMessage = this.labels.loadError;
    }
    // Optional like every tile: a count that cannot be read costs the page one line, not the page.
    try {
      this.installProblemCount = await countInstallProblems();
    } catch {
      this.installProblemCount = undefined;
    }
  }

  applyModel(model) {
    if (!model) {
      return;
    }
    this.stepsCompleted = model.stepsCompleted || 0;
    this.stepsTotal = model.stepsTotal || 0;
    this.automationPaused = Boolean(model.automationPaused);
    this.newErrorCount = model.newErrorCount || 0;
    this.newErrorCountCapped = Boolean(model.newErrorCountCapped);
    this.canEdit = Boolean(model.canEdit);
    this.rollupsLastCalculated = model.rollupsLastCalculated;
    this.rollupsStale = Boolean(model.rollupsStale);
    this.seasonalAddressLastRun = model.seasonalAddressLastRun;
    this.seasonalAddressLastRunSummary = model.seasonalAddressLastRunSummary;
    this.seasonalAddressScheduled = Boolean(model.seasonalAddressScheduled);
    this.seasonalAddressStale = Boolean(model.seasonalAddressStale);
    this.recurringSources = model.recurringSources || [];
  }

  get hasRecurringSources() {
    return this.recurringSources.length > 0;
  }

  /** The assistant reports its own progress, so the page collapses without reloading. */
  handleSetupChanged(event) {
    this.stepsCompleted = event.detail.stepsCompleted || 0;
    this.stepsTotal = event.detail.stepsTotal || 0;
    if (!event.detail.isComplete) {
      this.setupReopened = false;
    }
  }

  handleReopenSetup() {
    this.setupReopened = true;
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
