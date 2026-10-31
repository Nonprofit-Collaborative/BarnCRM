import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRoster from '@salesforce/apex/ProgramRosterController.getRoster';
import enroll from '@salesforce/apex/ProgramRosterController.enroll';
import setStage from '@salesforce/apex/ProgramRosterController.setStage';

import TITLE from '@salesforce/label/c.Programs_Roster_Title';
import ENROLL from '@salesforce/label/c.Programs_Roster_Enroll';
import PERSON from '@salesforce/label/c.Programs_Roster_Person';
import STAGE from '@salesforce/label/c.Programs_Roster_Stage';
import START_DATE from '@salesforce/label/c.Programs_Roster_StartDate';
import END_DATE from '@salesforce/label/c.Programs_Roster_EndDate';
import SAVE from '@salesforce/label/c.Programs_Roster_Save';
import CANCEL from '@salesforce/label/c.Programs_Roster_Cancel';
import SHOW_ENDED from '@salesforce/label/c.Programs_Roster_ShowEnded';
import CAPTION from '@salesforce/label/c.Programs_Roster_Caption';
import STAGE_FOR from '@salesforce/label/c.Programs_Roster_StageFor';
import EMPTY from '@salesforce/label/c.Programs_Roster_Empty';
import ADDED from '@salesforce/label/c.Programs_Roster_Added';
import CHANGED from '@salesforce/label/c.Programs_Roster_Changed';
import MORE_THAN_SHOWN from '@salesforce/label/c.Programs_Roster_MoreThanShown';
import ACTION_FAILED from '@salesforce/label/c.Programs_Roster_ActionFailed';
import LOADING from '@salesforce/label/c.Programs_Loading';

import { format, rosterRows, stageFigures, stageLabel, stageOptions } from './roster';
import { bodyMessage } from 'c/findCsv';

const STAGE_ENROLLED = 'Enrolled';
const MAX_SHOWN = 200;

/**
 * The Program Roster panel on a program (P-01): how many people are at each stage, who is
 * enrolled, enrolling a person and moving them through the stages. Saves go through the
 * enrollment automation, so one open enrollment per person per program and the stage dates apply.
 */
export default class ProgramRoster extends NavigationMixin(LightningElement) {
  @api recordId;

  labels = {
    title: TITLE,
    enroll: ENROLL,
    person: PERSON,
    stage: STAGE,
    startDate: START_DATE,
    endDate: END_DATE,
    save: SAVE,
    cancel: CANCEL,
    showEnded: SHOW_ENDED,
    empty: EMPTY,
    loading: LOADING
  };

  roster;
  showEnded = false;
  busy = false;
  showForm = false;
  draftPersonId;
  draftStage = STAGE_ENROLLED;
  errorMessage;
  resultMessage;
  focusTarget;
  /** The first load is still running. */
  loading = true;

  connectedCallback() {
    this.load();
  }

  renderedCallback() {
    if (this.focusTarget) {
      const target = this.template.querySelector(`[data-id="${this.focusTarget}"]`);
      if (target) {
        this.focusTarget = undefined;
        target.focus();
      }
    }
  }

  load() {
    return getRoster({ programId: this.recordId, showEnded: this.showEnded })
      .then((roster) => {
        this.roster = roster;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.loading = false;
      });
  }

  get loaded() {
    return !!this.roster;
  }

  get showSpinner() {
    return this.loading || this.busy;
  }

  get canAdd() {
    return !!(this.roster && this.roster.canAdd);
  }

  get canEdit() {
    return !!(this.roster && this.roster.canEdit);
  }

  get addDisabled() {
    return this.busy || this.showForm;
  }

  get saveDisabled() {
    return this.busy || !this.draftPersonId;
  }

  get figures() {
    return stageFigures(this.roster);
  }

  get stageOptions() {
    return stageOptions(this.roster);
  }

  get personObjectApiName() {
    return this.roster && this.roster.hasPersonAccounts ? 'Account' : 'Contact';
  }

  /** In a person account org, only person accounts: an organization is never a participant. */
  get personFilter() {
    if (!this.roster || !this.roster.personFilterField) {
      return undefined;
    }
    return {
      criteria: [{ fieldPath: this.roster.personFilterField, operator: 'eq', value: true }]
    };
  }

  get enrollments() {
    return rosterRows(this.roster, STAGE_FOR);
  }

  get hasEnrollments() {
    return this.enrollments.length > 0;
  }

  get isEmpty() {
    return this.loaded && !this.hasEnrollments;
  }

  get caption() {
    return format(CAPTION, this.roster ? this.roster.programName : '');
  }

  get moreThanShown() {
    return !!(this.roster && this.roster.moreThanShown);
  }

  get moreThanShownText() {
    return format(MORE_THAN_SHOWN, MAX_SHOWN);
  }

  get hasError() {
    return !!this.errorMessage;
  }

  // ---------------------------------------------------------------------------- listing

  handleShowEndedChange(event) {
    this.showEnded = event.target.checked;
    this.busy = true;
    this.errorMessage = undefined;
    return this.load().finally(() => {
      this.busy = false;
    });
  }

  // ---------------------------------------------------------------------------- enrolling

  handleShowForm() {
    this.showForm = true;
    this.errorMessage = undefined;
    this.focusTarget = 'person-picker';
  }

  handleCancel() {
    this.resetForm();
    this.focusTarget = 'enroll-button';
  }

  handlePersonChange(event) {
    this.draftPersonId = event.detail ? event.detail.recordId : undefined;
  }

  handleDraftStageChange(event) {
    this.draftStage = event.detail.value;
  }

  handleSave() {
    return this.run(
      enroll({
        programId: this.recordId,
        personId: this.draftPersonId,
        stage: this.draftStage,
        showEnded: this.showEnded
      }),
      () => {
        this.resetForm();
        return ADDED;
      }
    );
  }

  resetForm() {
    this.showForm = false;
    this.draftPersonId = undefined;
    this.draftStage = STAGE_ENROLLED;
  }

  /** The person's name opens the enrollment record, where its dates can be corrected. */
  handleOpenEnrollment(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: {
        recordId: event.currentTarget.dataset.recordId,
        objectApiName: 'Enrollment__c',
        actionName: 'view'
      }
    });
  }

  // ------------------------------------------------------------------------ changing stage

  handleStageChange(event) {
    const enrollmentId = event.target.dataset.recordId;
    const stage = event.detail.value;
    const row = this.enrollments.find((candidate) => candidate.recordId === enrollmentId);
    const who = row ? row.displayName : '';
    return this.run(setStage({ enrollmentId, stage, showEnded: this.showEnded }), (roster) =>
      format(CHANGED, who, stageLabel(roster, stage))
    );
  }

  /**
   * Runs one save, shows the roster it returns, and announces what happened once, in the status
   * region (a failure in the alert region).
   */
  run(call, describe) {
    this.busy = true;
    this.errorMessage = undefined;
    return call
      .then((roster) => {
        this.roster = roster;
        this.resultMessage = describe(roster);
        this.focusTarget = 'result';
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
        this.focusTarget = 'error-message';
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
