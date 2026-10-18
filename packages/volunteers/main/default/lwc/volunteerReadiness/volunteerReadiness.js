import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getReadiness from '@salesforce/apex/VolunteerReadinessController.getReadiness';

import TITLE from '@salesforce/label/c.Volunteers_Readiness_Title';
import NOT_STARTED from '@salesforce/label/c.Volunteers_Readiness_NotStarted';
import CURRENT from '@salesforce/label/c.Volunteers_Readiness_Current';
import NOT_CURRENT from '@salesforce/label/c.Volunteers_Readiness_NotCurrent';
import COMPLETED from '@salesforce/label/c.Volunteers_Readiness_Completed';
import EXPIRES from '@salesforce/label/c.Volunteers_Readiness_Expires';
import LOAD_FAILED from '@salesforce/label/c.Volunteers_Readiness_LoadFailed';
import REFRESH from '@salesforce/label/c.Volunteers_Readiness_Refresh';

/**
 * Volunteer readiness on a person (canonical model R-VQ3): each requirement type's most recently
 * added row, or Not started, and whether it is current. Read only: it never blocks a sign-up or
 * hours. A user who cannot see requirements, or a household or organization, gets no card.
 */
export default class VolunteerReadiness extends NavigationMixin(LightningElement) {
  @api recordId;

  label = {
    title: TITLE,
    completed: COMPLETED,
    expires: EXPIRES,
    refresh: REFRESH
  };

  canSee = false;
  steps = [];
  errorMessage;
  loaded = false;
  wiredResult;

  @wire(getReadiness, { personId: '$recordId' })
  wiredReadiness(result) {
    this.wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.canSee = data.canSee === true;
      this.steps = (data.steps || []).map((step) => this.toRow(step));
      this.errorMessage = undefined;
      this.loaded = true;
    } else if (error) {
      // Shown only to someone the card is for; a failure is not a reason to hide that it failed.
      this.canSee = true;
      this.steps = [];
      this.errorMessage = LOAD_FAILED;
      this.loaded = true;
    }
  }

  toRow(step) {
    const started = Boolean(step.requirementId);
    return {
      ...step,
      key: step.type,
      started,
      url: started ? `/${step.requirementId}` : undefined,
      statusText: started ? step.statusLabel : NOT_STARTED,
      stateText: step.isCurrent ? CURRENT : NOT_CURRENT,
      stateClass: step.isCurrent
        ? 'slds-badge slds-theme_success state'
        : 'slds-badge slds-badge_lightest state'
    };
  }

  /** Nothing until the answer arrives, so a user the card is not for never sees it flash. */
  get showCard() {
    return this.loaded && this.canSee;
  }

  handleRefresh() {
    return refreshApex(this.wiredResult);
  }

  handleOpen(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId: event.currentTarget.dataset.recordId, actionName: 'view' }
    });
  }
}
