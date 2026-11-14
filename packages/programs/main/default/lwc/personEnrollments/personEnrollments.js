import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getEnrollments from '@salesforce/apex/PersonEnrollmentsController.getEnrollments';

import TITLE from '@salesforce/label/c.Core_Settings_NavGroup_Programs';
import STARTED from '@salesforce/label/c.Core_DataJobs_Started';
import ENDED from '@salesforce/label/c.Core_EraseAction_Ended';
import REFRESH from '@salesforce/label/c.Core_OrgOptimizer_Refresh';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import LAST_SERVICE from '@salesforce/label/c.Programs_Person_LastService';
import SERVICES_ATTENDED from '@salesforce/label/c.Programs_Person_ServicesAttended';
import ENROLL from '@salesforce/label/c.Programs_Enroll';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import ENROLLMENT from '@salesforce/schema/Enrollment__c';
import ENROLLMENT_CONTACT from '@salesforce/schema/Enrollment__c.Contact__c';
import ENROLLMENT_ACCOUNT from '@salesforce/schema/Enrollment__c.Account__c';

import { canShow, enrollmentRows, lastService } from './enrollmentRows';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/** Contact ids start with this key prefix; any other person is a person account. */
const CONTACT_PREFIX = '003';

/**
 * The Programs card on a person (P-01): every enrollment they have, open ones first, with the
 * program, stage and dates. A household, an organization, or a user who cannot read
 * enrollments gets no card; a failed load shows a short message, never the error's own text.
 * Enroll (D-200 R1), for someone who may create enrollments, opens a new enrollment with the
 * person filled in.
 */
export default class PersonEnrollments extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Programs');

  @api recordId;

  label = {
    title: TITLE,
    get empty() {
      return helpText('Programs', 'Programs_Person_Empty');
    },
    started: STARTED,
    ended: ENDED,
    refresh: REFRESH,
    get moreThanShown() {
      return helpText('Programs', 'Programs_Person_MoreThanShown');
    },
    loading: LOADING,
    lastService: LAST_SERVICE,
    enroll: ENROLL
  };

  result;
  loading = true;
  errorMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Programs').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  load() {
    this.loading = true;
    return getEnrollments({ personId: this.recordId })
      .then((result) => {
        this.result = result;
        this.errorMessage = undefined;
      })
      .catch(() =>
        // The message is in the help catalog (modules-1); never the error's own text.
        loadHelp('Programs').then(() => {
          this.errorMessage = helpText('Programs', 'Programs_Fail_PersonCard');
        })
      )
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

  /** The last service line (P-05), or null when the person has attended none. */
  get lastService() {
    return lastService(this.result, SERVICES_ATTENDED);
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

  get canEnroll() {
    return !!(this.result && this.result.canSee && this.result.canEnroll);
  }

  handleEnroll() {
    const personField = String(this.recordId).startsWith(CONTACT_PREFIX)
      ? ENROLLMENT_CONTACT
      : ENROLLMENT_ACCOUNT;
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: ENROLLMENT.objectApiName, actionName: 'new' },
      state: {
        defaultFieldValues: encodeDefaultFieldValues({ [personField.fieldApiName]: this.recordId })
      }
    });
  }

  handleOpen(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId: event.currentTarget.dataset.recordId, actionName: 'view' }
    });
  }
}
