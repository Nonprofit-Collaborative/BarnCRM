import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getLadder from '@salesforce/apex/DonorLevelController.getLadder';
import recalculate from '@salesforce/apex/DonorLevelController.recalculate';

import TITLE from '@salesforce/label/c.Giving_DonorLevels_Title';
import INTRO from '@salesforce/label/c.Giving_DonorLevels_Intro';
import MEASURED_ON from '@salesforce/label/c.Giving_DonorLevels_MeasuredOn';
import LAST_RECALCULATED from '@salesforce/label/c.Giving_DonorLevels_LastRecalculated';
import NEVER_RECALCULATED from '@salesforce/label/c.Giving_DonorLevels_NeverRecalculated';
import OFF from '@salesforce/label/c.Giving_DonorLevels_Off';
import EMPTY from '@salesforce/label/c.Giving_DonorLevels_Empty';
import NEW_LEVEL from '@salesforce/label/c.Giving_DonorLevels_NewLevel';
import RECALCULATE from '@salesforce/label/c.Giving_DonorLevels_Recalculate';
import RECALCULATE_STARTED from '@salesforce/label/c.Giving_DonorLevels_RecalculateStarted';
import COLUMN_LEVEL from '@salesforce/label/c.Giving_DonorLevels_ColumnLevel';
import COLUMN_FROM from '@salesforce/label/c.Giving_DonorLevels_ColumnFrom';
import COLUMN_UP_TO from '@salesforce/label/c.Giving_DonorLevels_ColumnUpTo';
import COLUMN_DONORS from '@salesforce/label/c.Giving_DonorLevels_ColumnDonors';
import COLUMN_ACTIVE from '@salesforce/label/c.Giving_DonorLevels_ColumnActive';
import TOP_OF_LADDER from '@salesforce/label/c.Giving_DonorLevels_TopOfLadder';
import INACTIVE from '@salesforce/label/c.Giving_DonorLevels_Inactive';
import ACTION_FAILED from '@salesforce/label/c.Giving_DonorLevels_ActionFailed';
import { bodyMessage } from 'c/findCsv';

/**
 * The ladder, as Maria reads it: every rung lowest first, how many donors are on each, what the
 * levels are measured on, when everybody was last placed, and the button that places them now.
 *
 * The rungs themselves are edited as records, so this page navigates to them rather than carrying
 * a second editor (ADR-0028).
 */
export default class DonorLevels extends NavigationMixin(LightningElement) {
  labels = {
    title: TITLE,
    intro: INTRO,
    measuredOn: MEASURED_ON,
    lastRecalculated: LAST_RECALCULATED,
    never: NEVER_RECALCULATED,
    off: OFF,
    empty: EMPTY,
    newLevel: NEW_LEVEL,
    recalculate: RECALCULATE,
    columnLevel: COLUMN_LEVEL,
    columnFrom: COLUMN_FROM,
    columnUpTo: COLUMN_UP_TO,
    columnDonors: COLUMN_DONORS,
    columnActive: COLUMN_ACTIVE,
    topOfLadder: TOP_OF_LADDER,
    inactive: INACTIVE
  };

  ladder;
  wiredLadder;
  errorMessage;
  noticeMessage;
  busy = false;

  @wire(getLadder)
  wiredResult(result) {
    this.wiredLadder = result;
    if (result.data) {
      this.ladder = result.data;
      this.errorMessage = undefined;
    }
    if (result.error) {
      this.errorMessage = bodyMessage(result.error, ACTION_FAILED);
    }
  }

  get hasLadder() {
    return !!(this.ladder && this.ladder.rungs && this.ladder.rungs.length);
  }

  get isEmpty() {
    return !!this.ladder && !this.hasLadder;
  }

  get showOffNotice() {
    return !!this.ladder && this.ladder.enabled === false;
  }

  get sourceFieldLabel() {
    return this.ladder ? this.ladder.sourceFieldLabel : '';
  }

  get lastRecalculatedText() {
    if (!this.ladder || !this.ladder.lastRecalculated) {
      return this.labels.never;
    }
    return new Date(this.ladder.lastRecalculated).toLocaleString();
  }

  /**
   * The rungs with the two things a raw record cannot say: the top rung has no ceiling, and an
   * inactive rung is still shown so that nobody wonders where it went.
   */
  get rungs() {
    if (!this.hasLadder) {
      return [];
    }
    return this.ladder.rungs.map((rung) => ({
      ...rung,
      isTopOfLadder: rung.maximumAmount === null || rung.maximumAmount === undefined,
      activeText: rung.active ? '' : this.labels.inactive
    }));
  }

  get recalculateDisabled() {
    return this.busy || !this.ladder || !this.ladder.canRecalculate || !this.ladder.enabled;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get hasNotice() {
    return !!this.noticeMessage;
  }

  handleNewLevel() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Donor_Level__c', actionName: 'new' }
    });
  }

  handleOpenRung(event) {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: {
        recordId: event.currentTarget.dataset.recordId,
        objectApiName: 'Donor_Level__c',
        actionName: 'view'
      }
    });
  }

  handleRecalculate() {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    return recalculate()
      .then(() => {
        this.noticeMessage = RECALCULATE_STARTED;
        return refreshApex(this.wiredLadder);
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
