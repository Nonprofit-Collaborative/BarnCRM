import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import { iconFor } from 'c/barnIcons';
import HEADING from '@salesforce/label/c.Core_HubHome_ErrorTileHeading';
import ERRORS from '@salesforce/label/c.Core_OrgOptimizer_Errors';
import LINK from '@salesforce/label/c.Core_ErrorLogTile_ViewAll';
import INSTALL_COMPLETED from '@salesforce/label/c.Core_HubHome_InstallCompleted';
import INSTALL_PROBLEMS from '@salesforce/label/c.Core_HubHome_InstallProblems';
import ALL_CLEAR from '@salesforce/label/c.Core_OrgOptimizer_BadgeAllClear';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * Errors to review on the BarnCRM home page: how many new errors are waiting (capped, so a
 * flooded log never slows the page) as a stat tile, with an All Clear badge at none, and
 * whether the install itself logged any problems.
 */
export default class HubErrors extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  labels = { heading: HEADING, errors: ERRORS, link: LINK, allClear: ALL_CLEAR };
  iconName = iconFor('Error_Log__c');
  loaded = false;

  newErrorCount = 0;
  newErrorCountCapped = false;
  errorMessage;

  // How many problems the install logged, or null or undefined for someone who cannot read
  // the log. It arrives in the home model, the one server call the tiles share (ADMIN-8).
  installProblemCount;

  @wire(getHomeModel)
  wiredModel({ data, error }) {
    if (data) {
      this.newErrorCount = data.newErrorCount || 0;
      this.newErrorCountCapped = Boolean(data.newErrorCountCapped);
      this.installProblemCount = data.installProblemCount;
      this.loaded = true;
      this.errorMessage = undefined;
    } else if (error) {
      this.errorMessage = helpText('Core', 'Core_HubHome_LoadErrorMessage');
    }
  }

  /** Nothing new to review, once the count has arrived. */
  get allClear() {
    return this.loaded && this.newErrorCount === 0;
  }

  /** The tile's figure: the count, or the cap with a plus once there are more than it counts. */
  get errorCountValue() {
    return this.newErrorCountCapped ? `${this.newErrorCount}+` : this.newErrorCount;
  }

  /**
   * A partly failed install looks exactly like a good one: every step writes its failure to
   * the Error Log and carries on. One line says which it was, and only to a person who can
   * read the log, because a count they cannot see is not evidence either way.
   */
  get hasInstallStatus() {
    return this.installProblemCount !== undefined && this.installProblemCount !== null;
  }

  get installHadProblems() {
    return this.installProblemCount > 0;
  }

  get installStatusText() {
    return this.installHadProblems
      ? INSTALL_PROBLEMS.replace('{0}', this.installProblemCount)
      : INSTALL_COMPLETED;
  }

  handleOpenErrorLog() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Error_Log__c', actionName: 'list' },
      state: { filterName: 'New_Errors' }
    });
  }
}
