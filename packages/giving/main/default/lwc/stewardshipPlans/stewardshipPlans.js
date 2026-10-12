import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getPage from '@salesforce/apex/StewardshipPlanController.getPage';
import saveTemplate from '@salesforce/apex/StewardshipPlanController.saveTemplate';
import setActive from '@salesforce/apex/StewardshipPlanController.setActive';
import saveStep from '@salesforce/apex/StewardshipPlanController.saveStep';
import deleteStep from '@salesforce/apex/StewardshipPlanController.deleteStep';
import reorderSteps from '@salesforce/apex/StewardshipPlanController.reorderSteps';

import TITLE from '@salesforce/label/c.Giving_Stewardship_Title';
import INTRO from '@salesforce/label/c.Giving_Stewardship_Intro';
import RUNNING_NOTICE from '@salesforce/label/c.Giving_Stewardship_RunningNotice';
import READ_ONLY_NOTICE from '@salesforce/label/c.Giving_Stewardship_ReadOnlyNotice';
import EMPTY from '@salesforce/label/c.Giving_Stewardship_Empty';
import NEW_PLAN from '@salesforce/label/c.Giving_Stewardship_NewPlan';
import EDIT_PLAN from '@salesforce/label/c.Giving_Stewardship_EditPlan';
import TURN_ON from '@salesforce/label/c.Giving_Stewardship_TurnOn';
import TURN_OFF from '@salesforce/label/c.Giving_Stewardship_TurnOff';
import COLUMN_PLAN from '@salesforce/label/c.Giving_Stewardship_ColumnPlan';
import COLUMN_EVENT from '@salesforce/label/c.Giving_Stewardship_ColumnEvent';
import COLUMN_STEPS from '@salesforce/label/c.Giving_Stewardship_ColumnSteps';
import COLUMN_RUNNING from '@salesforce/label/c.Giving_Stewardship_ColumnRunning';
import COLUMN_ACTIVE from '@salesforce/label/c.Giving_Stewardship_ColumnActive';
import ACTIVE from '@salesforce/label/c.Giving_Stewardship_Active';
import INACTIVE from '@salesforce/label/c.Giving_Stewardship_Inactive';
import FIELD_NAME from '@salesforce/label/c.Giving_Stewardship_FieldName';
import FIELD_EVENT from '@salesforce/label/c.Giving_Stewardship_FieldEvent';
import FIELD_MINIMUM from '@salesforce/label/c.Giving_Stewardship_FieldMinimum';
import FIELD_MINIMUM_HELP from '@salesforce/label/c.Giving_Stewardship_FieldMinimumHelp';
import FIELD_DESCRIPTION from '@salesforce/label/c.Giving_Stewardship_FieldDescription';
import STEPS_HEADING from '@salesforce/label/c.Giving_Stewardship_StepsHeading';
import NO_STEPS from '@salesforce/label/c.Giving_Stewardship_NoSteps';
import SELECT_PLAN from '@salesforce/label/c.Giving_Stewardship_SelectPlan';
import ADD_STEP from '@salesforce/label/c.Giving_Stewardship_AddStep';
import MOVE_UP from '@salesforce/label/c.Giving_Stewardship_MoveUp';
import MOVE_DOWN from '@salesforce/label/c.Giving_Stewardship_MoveDown';
import REMOVE_STEP from '@salesforce/label/c.Giving_Stewardship_RemoveStep';
import STEP_SUBJECT from '@salesforce/label/c.Giving_Stewardship_StepSubject';
import STEP_SUBJECT_HELP from '@salesforce/label/c.Giving_Stewardship_StepSubjectHelp';
import STEP_DAYS from '@salesforce/label/c.Giving_Stewardship_StepDays';
import STEP_ASSIGN from '@salesforce/label/c.Giving_Stewardship_StepAssign';
import STEP_USER from '@salesforce/label/c.Giving_Stewardship_StepUser';
import STEP_PRIORITY from '@salesforce/label/c.Giving_Stewardship_StepPriority';
import STEP_COMMENTS from '@salesforce/label/c.Giving_Stewardship_StepComments';
import SAVE from '@salesforce/label/c.Giving_Stewardship_Save';
import CANCEL from '@salesforce/label/c.Giving_Stewardship_Cancel';
import SAVED from '@salesforce/label/c.Giving_Stewardship_Saved';
import ACTION_FAILED from '@salesforce/label/c.Giving_Stewardship_ErrorActionFailed';

const EMPTY_TEMPLATE = {
  recordId: null,
  name: '',
  triggerEvent: 'Manual',
  minimumAmount: null,
  description: '',
  active: false
};

const EMPTY_STEP = {
  recordId: null,
  subject: '',
  daysAfterStart: 0,
  assignTo: 'Record owner',
  assignedUserId: null,
  priority: 'Normal',
  comments: ''
};

/**
 * Stewardship plans, as an administrator manages them: the plans she has written down, the steps
 * each one lays out, the order they come in, and the switch that turns a plan on.
 *
 * The page carries the editing rather than sending her to object tabs, because a plan and its
 * steps are one idea and every setting belongs in the console. It says out loud, next to the
 * steps, that editing a plan does not reach into plans already running (R-SP7), because that is
 * the question an administrator asks the moment she changes a step.
 */
export default class StewardshipPlans extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    runningNotice: RUNNING_NOTICE,
    readOnlyNotice: READ_ONLY_NOTICE,
    empty: EMPTY,
    newPlan: NEW_PLAN,
    editPlan: EDIT_PLAN,
    turnOn: TURN_ON,
    turnOff: TURN_OFF,
    columnPlan: COLUMN_PLAN,
    columnEvent: COLUMN_EVENT,
    columnSteps: COLUMN_STEPS,
    columnRunning: COLUMN_RUNNING,
    columnActive: COLUMN_ACTIVE,
    active: ACTIVE,
    inactive: INACTIVE,
    fieldName: FIELD_NAME,
    fieldEvent: FIELD_EVENT,
    fieldMinimum: FIELD_MINIMUM,
    fieldMinimumHelp: FIELD_MINIMUM_HELP,
    fieldDescription: FIELD_DESCRIPTION,
    stepsHeading: STEPS_HEADING,
    noSteps: NO_STEPS,
    selectPlan: SELECT_PLAN,
    addStep: ADD_STEP,
    moveUp: MOVE_UP,
    moveDown: MOVE_DOWN,
    removeStep: REMOVE_STEP,
    stepSubject: STEP_SUBJECT,
    stepSubjectHelp: STEP_SUBJECT_HELP,
    stepDays: STEP_DAYS,
    stepAssign: STEP_ASSIGN,
    stepUser: STEP_USER,
    stepPriority: STEP_PRIORITY,
    stepComments: STEP_COMMENTS,
    save: SAVE,
    cancel: CANCEL
  };

  page;
  wiredPage;
  errorMessage;
  noticeMessage;
  busy = false;
  selectedId;
  templateDraft;
  stepDraft;

  @wire(getPage)
  wiredResult(result) {
    this.wiredPage = result;
    if (result.data) {
      this.page = result.data;
      this.errorMessage = undefined;
      if (this.selectedId && !result.data.templates.some((t) => t.recordId === this.selectedId)) {
        this.selectedId = undefined;
      }
    }
    if (result.error) {
      this.errorMessage = this.messageFrom(result.error);
    }
  }

  get canEdit() {
    return !!(this.page && this.page.canEdit);
  }

  /** Every editing control is disabled while a save is in flight, and for a reader. */
  get cannotEdit() {
    return !this.canEdit || this.busy;
  }

  get showReadOnlyNotice() {
    return !!this.page && !this.page.canEdit;
  }

  get hasTemplates() {
    return !!(this.page && this.page.templates && this.page.templates.length);
  }

  get isEmpty() {
    return !!this.page && !this.hasTemplates;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get hasNotice() {
    return !!this.noticeMessage;
  }

  get triggerEvents() {
    return this.page ? this.page.triggerEvents : [];
  }

  get assignToOptions() {
    return this.page ? this.page.assignTo : [];
  }

  get priorityOptions() {
    return this.page ? this.page.priorities : [];
  }

  get userOptions() {
    return this.page ? this.page.assignableUsers : [];
  }

  /** The plans, with the two things a raw row cannot say: which one is open, and on or off. */
  get templates() {
    if (!this.hasTemplates) {
      return [];
    }
    return this.page.templates.map((template) => ({
      ...template,
      stepCount: template.steps ? template.steps.length : 0,
      activeText: template.active ? this.labels.active : this.labels.inactive,
      toggleLabel: template.active ? this.labels.turnOff : this.labels.turnOn,
      isSelected: template.recordId === this.selectedId,
      rowClass:
        template.recordId === this.selectedId
          ? 'slds-is-selected slds-hint-parent'
          : 'slds-hint-parent'
    }));
  }

  get selectedTemplate() {
    if (!this.hasTemplates || !this.selectedId) {
      return undefined;
    }
    return this.page.templates.find((template) => template.recordId === this.selectedId);
  }

  get hasSelection() {
    return !!this.selectedTemplate;
  }

  /** The steps of the open plan, with the first and last marked so they cannot move off the end. */
  get steps() {
    const template = this.selectedTemplate;
    if (!template || !template.steps) {
      return [];
    }
    const last = template.steps.length - 1;
    return template.steps.map((step, index) => ({
      ...step,
      position: index + 1,
      isFirst: index === 0,
      isLast: index === last,
      assigneeText: step.assignedUserName ? step.assignedUserName : step.assignTo
    }));
  }

  get hasSteps() {
    return this.steps.length > 0;
  }

  get showTemplateForm() {
    return !!this.templateDraft;
  }

  get showStepForm() {
    return !!this.stepDraft;
  }

  get runningPlansText() {
    const template = this.selectedTemplate;
    return template ? String(template.runningPlans) : '0';
  }

  handleSelect(event) {
    this.selectedId = event.currentTarget.dataset.recordId;
    this.stepDraft = undefined;
  }

  handleNewPlan() {
    this.clearMessages();
    this.templateDraft = { ...EMPTY_TEMPLATE };
  }

  handleEditPlan(event) {
    this.clearMessages();
    const recordId = event.currentTarget.dataset.recordId;
    const template = this.page.templates.find((row) => row.recordId === recordId);
    this.selectedId = recordId;
    this.templateDraft = template ? { ...template } : { ...EMPTY_TEMPLATE };
  }

  handleTemplateField(event) {
    const field = event.currentTarget.dataset.field;
    const value =
      field === 'active' ? event.target.checked : event.detail ? event.detail.value : undefined;
    this.templateDraft = { ...this.templateDraft, [field]: value };
  }

  handleCancelTemplate() {
    this.templateDraft = undefined;
  }

  handleSaveTemplate() {
    const draft = this.templateDraft;
    return this.run(
      saveTemplate({
        template: {
          recordId: draft.recordId,
          name: draft.name,
          triggerEvent: draft.triggerEvent,
          minimumAmount: draft.minimumAmount === '' ? null : draft.minimumAmount,
          description: draft.description,
          active: draft.active === true
        }
      }).then((recordId) => {
        this.selectedId = recordId;
        this.templateDraft = undefined;
      })
    );
  }

  handleToggleActive(event) {
    const recordId = event.currentTarget.dataset.recordId;
    const template = this.page.templates.find((row) => row.recordId === recordId);
    return this.run(setActive({ templateId: recordId, active: !(template && template.active) }));
  }

  handleAddStep() {
    this.clearMessages();
    this.stepDraft = { ...EMPTY_STEP };
  }

  handleEditStep(event) {
    this.clearMessages();
    const recordId = event.currentTarget.dataset.recordId;
    const step = this.steps.find((row) => row.recordId === recordId);
    this.stepDraft = step ? { ...step } : { ...EMPTY_STEP };
  }

  handleStepField(event) {
    const field = event.currentTarget.dataset.field;
    this.stepDraft = {
      ...this.stepDraft,
      [field]: event.detail ? event.detail.value : undefined
    };
  }

  handleCancelStep() {
    this.stepDraft = undefined;
  }

  handleSaveStep() {
    const draft = this.stepDraft;
    return this.run(
      saveStep({
        templateId: this.selectedId,
        step: {
          recordId: draft.recordId,
          subject: draft.subject,
          daysAfterStart: draft.daysAfterStart === '' ? 0 : draft.daysAfterStart,
          assignTo: draft.assignTo,
          assignedUserId: draft.assignedUserId ? draft.assignedUserId : null,
          priority: draft.priority,
          comments: draft.comments
        }
      }).then(() => {
        this.stepDraft = undefined;
      })
    );
  }

  handleDeleteStep(event) {
    return this.run(deleteStep({ stepId: event.currentTarget.dataset.recordId }));
  }

  handleMoveUp(event) {
    return this.move(event.currentTarget.dataset.recordId, -1);
  }

  handleMoveDown(event) {
    return this.move(event.currentTarget.dataset.recordId, 1);
  }

  /** Swaps one step with its neighbour and sends the whole order back, so it is one update. */
  move(recordId, offset) {
    const ids = this.steps.map((step) => step.recordId);
    const from = ids.indexOf(recordId);
    const to = from + offset;
    if (from < 0 || to < 0 || to >= ids.length) {
      return Promise.resolve();
    }
    ids[from] = ids[to];
    ids[to] = recordId;
    return this.run(reorderSteps({ templateId: this.selectedId, stepIds: ids }));
  }

  /** Every write goes through here, so one place says what happened and refreshes the page. */
  run(pending) {
    this.busy = true;
    this.clearMessages();
    return pending
      .then(() => refreshApex(this.wiredPage))
      .then(() => {
        this.noticeMessage = SAVED;
      })
      .catch((error) => {
        this.errorMessage = this.messageFrom(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  clearMessages() {
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return ACTION_FAILED;
  }
}
