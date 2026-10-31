import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getEnrollments from '@salesforce/apex/PersonEnrollmentsController.getEnrollments';

import TITLE from '@salesforce/label/c.Programs_Person_Title';
import EMPTY from '@salesforce/label/c.Programs_Person_Empty';
import STARTED from '@salesforce/label/c.Programs_Person_Started';
import ENDED from '@salesforce/label/c.Programs_Person_Ended';
import LOAD_FAILED from '@salesforce/label/c.Programs_Person_LoadFailed';
import REFRESH from '@salesforce/label/c.Programs_Person_Refresh';
import MORE_THAN_SHOWN from '@salesforce/label/c.Programs_Person_MoreThanShown';
import LOADING from '@salesforce/label/c.Programs_Loading';

import { canShow, enrollmentRows } from './enrollmentRows';

/**
 * The Programs card on a person (P-01): every enrollment they have, open ones first, with the
 * program, stage and dates. Read only. A household, an organization, or a user who cannot read
 * enrollments gets no card; a failed load shows a short message, never the error's own text.
 */
export default class PersonEnrollments extends NavigationMixin(LightningElement) {
  @api recordId;

  label = {
    title: TITLE,
    empty: EMPTY,
    started: STARTED,
    ended: ENDED,
    refresh: REFRESH,
    moreThanShown: MORE_THAN_SHOWN,
    loading: LOADING
  };

  result;
  loading = true;
  errorMessage;

  connectedCallback() {
    this.load();
  }

  load() {
    this.loading = true;
    return getEnrollments({ personId: this.recordId })
      .then((result) => {
        this.result = result;
        this.errorMessage = undefined;
      })
      .catch(() => {
        this.errorMessage = LOAD_FAILED;
      })
      .finally(() => {
        this.loading = false;
      });
  }

  /** A card for a person whose enrollments the user may see, or to say the load failed. */
  get showCard() {
    return !!this.errorMessage || canShow(this.result);
  }

  get rows() {
    return enrollmentRows(this.result);
  }

  get showEmpty() {
    return !this.loading && !this.errorMessage && this.rows.length === 0;
  }

  get moreThanShown() {
    return !!(this.result && this.result.moreThanShown);
  }

  handleRefresh() {
    return this.load();
  }

  handleOpen(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId: event.currentTarget.dataset.recordId, actionName: 'view' }
    });
  }
}
