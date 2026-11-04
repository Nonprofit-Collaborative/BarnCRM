import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import CASE_NOTE from '@salesforce/schema/Case_Note__c';
import NOTE_ENROLLMENT from '@salesforce/schema/Case_Note__c.Enrollment__c';
import NOTE_GOAL from '@salesforce/schema/Case_Note__c.Goal__c';
import getPlan from '@salesforce/apex/ServicePlanController.getPlan';
import getOutcomes from '@salesforce/apex/ServicePlanController.getOutcomes';
import saveGoal from '@salesforce/apex/ServicePlanController.saveGoal';
import saveStep from '@salesforce/apex/ServicePlanController.saveStep';
import markReviewed from '@salesforce/apex/ServicePlanController.markReviewed';

import TITLE from '@salesforce/label/c.Programs_Plan_Title';
import ADD_GOAL from '@salesforce/label/c.Programs_Plan_AddGoal';
import EDIT_GOAL from '@salesforce/label/c.Programs_Plan_EditGoal';
import GOAL from '@salesforce/label/c.Programs_Plan_Goal';
import DESCRIPTION from '@salesforce/label/c.Core_Shared_Description';
import STATUS from '@salesforce/label/c.Core_ImportRow_StatusLabel';
import TARGET_DATE from '@salesforce/label/c.Core_Shared_TargetDate';
import ASSIGNED_TO from '@salesforce/label/c.Core_Shared_AssignedTo';
import NEXT_REVIEW from '@salesforce/label/c.Programs_Plan_NextReview';
import OUTCOME from '@salesforce/label/c.Core_Import_ResultsOutcome';
import NO_OUTCOME from '@salesforce/label/c.Core_Shared_NoOutcome';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import TARGET from '@salesforce/label/c.Programs_Plan_Target';
import ASSIGNED from '@salesforce/label/c.Programs_Plan_Assigned';
import NEXT_REVIEW_ON from '@salesforce/label/c.Programs_Plan_NextReviewOn';
import LAST_REVIEWED_ON from '@salesforce/label/c.Programs_Plan_LastReviewedOn';
import CLOSED_ON from '@salesforce/label/c.Programs_Plan_ClosedOn';
import REVIEW_DUE from '@salesforce/label/c.Programs_Plan_ReviewDue';
import WORKS_TOWARD from '@salesforce/label/c.Programs_Plan_WorksToward';
import OUTCOME_MISSING from '@salesforce/label/c.Programs_Plan_OutcomeMissing';
import STEPS_DONE from '@salesforce/label/c.Core_SetupAssistant_ProgressFormat';
import NEW_STEP from '@salesforce/label/c.Programs_Plan_NewStep';
import NEW_STEP_FOR from '@salesforce/label/c.Programs_Plan_NewStepFor';
import ADD_STEP from '@salesforce/label/c.Core_Shared_AddStep';
import MARK_REVIEWED from '@salesforce/label/c.Programs_Plan_MarkReviewed';
import SAVE_REVIEW from '@salesforce/label/c.Programs_Plan_SaveReview';
import NOTES from '@salesforce/label/c.Programs_Plan_Notes';
import MORE_NOTES from '@salesforce/label/c.Programs_Plan_MoreNotes';
import NEW_NOTE from '@salesforce/label/c.Programs_Plan_NewNote';
import SAVED from '@salesforce/label/c.Core_Shared_Saved';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

import {
  REVIEW_MONTHS,
  addMonths,
  goalCards,
  goalDraft,
  goalPayload,
  newStep,
  outcomeOptions,
  stepToggle,
  todayIn
} from './plan';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * The Service Plan panel on an enrollment (P-10, canonical model 29ZA3): the participant's goals,
 * the steps toward each, reviews and the case notes about each goal. Every save goes through the
 * server in user mode and returns the whole plan, which the framework-free `plan.js` orders and
 * labels. Works the same on a phone.
 */
export default class ServicePlan extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Programs');

  @api recordId;

  labels = {
    title: TITLE,
    get empty() {
      return helpText('Programs', 'Programs_Plan_Empty');
    },
    addGoal: ADD_GOAL,
    editGoal: EDIT_GOAL,
    goal: GOAL,
    description: DESCRIPTION,
    status: STATUS,
    targetDate: TARGET_DATE,
    assignedTo: ASSIGNED_TO,
    nextReview: NEXT_REVIEW,
    outcome: OUTCOME,
    save: SAVE,
    cancel: CANCEL,
    reviewDue: REVIEW_DUE,
    outcomeMissing: OUTCOME_MISSING,
    addStep: ADD_STEP,
    markReviewed: MARK_REVIEWED,
    saveReview: SAVE_REVIEW,
    get reviewIntro() {
      return helpText('Programs', 'Programs_Plan_ReviewIntro');
    },
    notes: NOTES,
    newNote: NEW_NOTE,
    newStep: NEW_STEP,
    loading: LOADING
  };

  plan;
  outcomes = [];
  /** The goal form's values while it is open; `editingId` is null for a new goal. */
  draft;
  editingId;
  /** The goal whose review form is open, and the next review date offered. */
  reviewingId;
  nextReview;
  /** Typed new step names, by goal. */
  stepNames = {};
  busy = false;
  loading = true;
  errorMessage;
  resultMessage;

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
    return getPlan({ enrollmentId: this.recordId })
      .then((plan) => {
        this.plan = plan;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Plan'));
      })
      .finally(() => {
        this.loading = false;
      });
  }

  get today() {
    return todayIn(TIME_ZONE);
  }

  get showSpinner() {
    return this.loading || this.busy;
  }

  get loaded() {
    return !!this.plan;
  }

  get canEdit() {
    return !!(this.plan && this.plan.canEdit);
  }

  get canAddNote() {
    return !!(this.plan && this.plan.canAddNote);
  }

  get goals() {
    const cards = goalCards(
      this.plan,
      this.today,
      {
        target: TARGET,
        assigned: ASSIGNED,
        nextReviewOn: NEXT_REVIEW_ON,
        lastReviewedOn: LAST_REVIEWED_ON,
        closedOn: CLOSED_ON,
        worksToward: WORKS_TOWARD,
        stepsDone: STEPS_DONE,
        moreNotes: MORE_NOTES,
        newStepFor: NEW_STEP_FOR
      },
      LOCALE
    );
    return cards.map((card) => ({
      ...card,
      open: !card.closed,
      reviewing: this.reviewingId === card.id,
      stepName: this.stepNames[card.id] || ''
    }));
  }

  get isEmpty() {
    return this.loaded && this.goals.length === 0 && !this.addingGoal;
  }

  get addingGoal() {
    return !!this.draft && !this.editingId;
  }

  get showAddGoal() {
    return this.canEdit && !this.draft;
  }

  get statusOptions() {
    return ((this.plan && this.plan.goalStatuses) || []).map(({ label, value }) => ({
      label,
      value
    }));
  }

  get showOutcome() {
    return !!(this.plan && this.plan.outcomesAvailable);
  }

  get outcomeChoices() {
    return outcomeOptions(this.outcomes, NO_OUTCOME);
  }

  get controlsDisabled() {
    return this.busy || this.loading;
  }

  // ------------------------------------------------------------------------- goals

  openGoalForm(goalId) {
    this.clearMessages();
    this.reviewingId = undefined;
    this.editingId = goalId || null;
    this.draft = goalDraft(this.plan, goalId);
    if (this.showOutcome) {
      getOutcomes({ enrollmentId: this.recordId })
        .then((outcomes) => {
          this.outcomes = outcomes || [];
        })
        .catch(() => {
          this.outcomes = [];
        });
    }
  }

  handleAddGoal() {
    this.openGoalForm(null);
  }

  handleEditGoal(event) {
    this.openGoalForm(event.target.dataset.goal);
  }

  get formTitle() {
    if (!this.draft) {
      return '';
    }
    return this.editingId ? `${EDIT_GOAL}: ${this.draft.name}` : ADD_GOAL;
  }

  handleDraftChange(event) {
    const field = event.target.dataset.field;
    const value =
      event.detail && event.detail.recordId !== undefined
        ? event.detail.recordId
        : event.detail && event.detail.value !== undefined
          ? event.detail.value
          : event.target.value;
    this.draft = { ...this.draft, [field]: value };
  }

  handleCancel() {
    this.draft = undefined;
    this.editingId = undefined;
    this.reviewingId = undefined;
  }

  handleSaveGoal() {
    const payload = goalPayload(this.draft, this.recordId, this.showOutcome);
    return this.run(() => saveGoal({ goalJson: JSON.stringify(payload) })).then((ok) => {
      if (ok) {
        this.draft = undefined;
        this.editingId = undefined;
      }
    });
  }

  // ------------------------------------------------------------------------- steps

  handleStepNameChange(event) {
    this.stepNames = { ...this.stepNames, [event.target.dataset.goal]: event.target.value };
  }

  handleAddStep(event) {
    const goalId = event.target.dataset.goal;
    const step = newStep(goalId, this.stepNames[goalId]);
    if (!step) {
      return Promise.resolve();
    }
    return this.run(() => saveStep({ stepJson: JSON.stringify(step) })).then((ok) => {
      if (ok) {
        this.stepNames = { ...this.stepNames, [goalId]: '' };
      }
    });
  }

  handleStepToggle(event) {
    const step = stepToggle(event.target.dataset.step, event.target.checked);
    return this.run(() => saveStep({ stepJson: JSON.stringify(step) }));
  }

  // ------------------------------------------------------------------------- reviews and notes

  handleOpenReview(event) {
    this.clearMessages();
    this.draft = undefined;
    this.editingId = undefined;
    this.reviewingId = event.target.dataset.goal;
    this.nextReview = addMonths(this.today, REVIEW_MONTHS);
  }

  handleNextReviewChange(event) {
    this.nextReview = event.target.value || null;
  }

  handleSaveReview() {
    const goalId = this.reviewingId;
    return this.run(() => markReviewed({ goalId, nextReviewDate: this.nextReview || null })).then(
      (ok) => {
        if (ok) {
          this.reviewingId = undefined;
        }
      }
    );
  }

  handleNewNote(event) {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: CASE_NOTE.objectApiName, actionName: 'new' },
      state: {
        defaultFieldValues: encodeDefaultFieldValues({
          [NOTE_ENROLLMENT.fieldApiName]: this.recordId,
          [NOTE_GOAL.fieldApiName]: event.target.dataset.goal
        })
      }
    });
  }

  handleOpenNote(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId: event.currentTarget.dataset.note, actionName: 'view' }
    });
  }

  // ------------------------------------------------------------------------- helpers

  clearMessages() {
    this.errorMessage = undefined;
    this.resultMessage = undefined;
  }

  /** Runs a save that returns the plan; resolves true when it worked. */
  run(call) {
    this.clearMessages();
    this.busy = true;
    return call()
      .then((plan) => {
        this.plan = plan;
        this.resultMessage = SAVED;
        return true;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Plan'));
        return false;
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
