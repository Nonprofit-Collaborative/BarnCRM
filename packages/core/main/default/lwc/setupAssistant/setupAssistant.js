import { LightningElement, api } from 'lwc';
import getState from '@salesforce/apex/SetupAssistantController.getState';
import completeStep from '@salesforce/apex/SetupAssistantController.completeStep';
import skipStep from '@salesforce/apex/SetupAssistantController.skipStep';
import resetSetup from '@salesforce/apex/SetupAssistantController.reset';
import applyCoexistence from '@salesforce/apex/SetupAssistantController.applyCoexistence';
import saveStepValues from '@salesforce/apex/SetupAssistantController.saveStepValues';
import assignAccess from '@salesforce/apex/SetupAssistantController.assignAccess';

import HEADING from '@salesforce/label/c.Core_SetupAssistant_Heading';
import PROGRESS_LABEL from '@salesforce/label/c.Core_SetupAssistant_ProgressLabel';
import STEP_COUNTER from '@salesforce/label/c.Core_SetupAssistant_StepCounterLabel';
import DONE_BADGE from '@salesforce/label/c.Core_SetupAssistant_DoneBadge';
import TODO_BADGE from '@salesforce/label/c.Core_SetupAssistant_ToDoBadge';
import SKIPPED_BADGE from '@salesforce/label/c.Core_SetupAssistant_SkippedBadge';
import NEXT from '@salesforce/label/c.Core_SetupAssistant_NextButton';
import BACK from '@salesforce/label/c.Core_SetupAssistant_BackButton';
import SKIP from '@salesforce/label/c.Core_SetupAssistant_SkipButton';
import FINISH from '@salesforce/label/c.Core_SetupAssistant_FinishButton';
import SAVE from '@salesforce/label/c.Core_SetupAssistant_SaveButton';
import READ_ONLY from '@salesforce/label/c.Core_SetupAssistant_ReadOnlyNotice';
import RULE_SETTING from '@salesforce/label/c.Core_SetupAssistant_RuleSetting';
import RULE_ACTION from '@salesforce/label/c.Core_SetupAssistant_RuleAction';
import LOAD_ERROR from '@salesforce/label/c.Core_SetupAssistant_LoadErrorMessage';
import COMPLETE_HEADING from '@salesforce/label/c.Core_SetupAssistant_CompleteHeading';
import ELAPSED from '@salesforce/label/c.Core_SetupAssistant_ElapsedLabel';
import REOPEN from '@salesforce/label/c.Core_SetupAssistant_ReopenButton';
import USER_LABEL from '@salesforce/label/c.Core_SetupAssistant_UserLabel';
import ROLE_LABEL from '@salesforce/label/c.Core_SetupAssistant_RoleLabel';
import GIVE_ACCESS from '@salesforce/label/c.Core_SetupAssistant_GiveAccessButton';
import ACCESS_GRANTED from '@salesforce/label/c.Core_SetupAssistant_AccessGrantedMessage';
import CREATE_USER from '@salesforce/label/c.Core_SetupAssistant_CreateUserLink';
import LOAD_SAMPLE from '@salesforce/label/c.Core_SetupAssistant_LoadSampleButton';
import IMPORT_BUTTON from '@salesforce/label/c.Core_SetupAssistant_ImportButton';
import IMPORT_MISSING from '@salesforce/label/c.Core_SetupAssistant_ImportMissingNotice';
import NAMING_UNAVAILABLE from '@salesforce/label/c.Core_SetupAssistant_NamingUnavailableNotice';
import SAMPLE_UNAVAILABLE from '@salesforce/label/c.Core_SetupAssistant_SampleDataUnavailableNotice';
import START_AGAIN from '@salesforce/label/c.Core_SetupAssistant_StartAgainButton';
import OPEN_SECTION from '@salesforce/label/c.Core_SetupAssistant_OpenSectionButton';
import PROGRESS_FORMAT from '@salesforce/label/c.Core_SetupAssistant_ProgressFormat';

const CREATE_USER_URL = '/lightning/setup/ManageUsers/home';
// The tabs the assistant links to. Both are unprefixed today; they are revisited when a
// namespace is assigned (Decision D-01), which is recorded in the integration file.
const IMPORT_URL = '/lightning/n/Import';
const SETTINGS_PAGE = '/lightning/n/Nonprofit_Settings';

/**
 * The guided Setup Assistant: one step open at a time, Back and Next, Skip for now, and it
 * opens on the step Maria stopped at. Steps that belong to another feature render that
 * feature's component dynamically, so a step whose module is not installed shows a notice
 * instead of breaking the page. A step's fields, including the ones a module adds, come from
 * Apex and are shown by one field panel (ADR-0059, C-29).
 */
export default class SetupAssistant extends LightningElement {
  /** Set by the Hub home page when Maria asked to reopen a finished setup. */
  @api reopened = false;

  reopenedHere = false;
  // Set when Maria clicks Finish on the last step, so a setup she reopened collapses back
  // to the completion screen rather than sitting on step eight with nowhere to go.
  finishedHere = false;
  state;
  activeIndex = 0;
  errorMessage;
  namingType;
  sampleDataType;
  importsTried = false;
  focusStepHeading = false;
  showSampleData = false;
  chosenUserId;
  chosenRole;
  accessGranted = false;
  userFilter = { criteria: [{ fieldPath: 'IsActive', operator: 'eq', value: true }] };

  labels = {
    heading: HEADING,
    progress: PROGRESS_LABEL,
    stepCounter: STEP_COUNTER,
    next: NEXT,
    back: BACK,
    skip: SKIP,
    finish: FINISH,
    save: SAVE,
    readOnly: READ_ONLY,
    completeHeading: COMPLETE_HEADING,
    elapsed: ELAPSED,
    reopen: REOPEN,
    user: USER_LABEL,
    role: ROLE_LABEL,
    giveAccess: GIVE_ACCESS,
    accessGranted: ACCESS_GRANTED,
    createUser: CREATE_USER,
    loadSample: LOAD_SAMPLE,
    importButton: IMPORT_BUTTON,
    importMissing: IMPORT_MISSING,
    namingUnavailable: NAMING_UNAVAILABLE,
    sampleUnavailable: SAMPLE_UNAVAILABLE,
    startAgain: START_AGAIN,
    openSection: OPEN_SECTION
  };

  createUserUrl = CREATE_USER_URL;
  importUrl = IMPORT_URL;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.applyState(await getState(), true);
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    }
  }

  applyState(state, moveToFirstUnfinished) {
    if (!state) {
      return;
    }
    this.state = state;
    if (moveToFirstUnfinished) {
      this.activeIndex = this.firstUnfinishedIndex(state);
      this.finishedHere = false;
    }
    this.importComponents();
    this.dispatchEvent(
      new CustomEvent('setupchanged', {
        detail: {
          stepsCompleted: state.stepsCompleted,
          stepsTotal: state.stepsTotal,
          isComplete: state.isComplete
        }
      })
    );
  }

  // A skipped step is not a finished step, so a later visit opens on it again, which is what
  // the admin guide promises. Skipping only moves past it for the rest of this sitting.
  // With nothing left unfinished the assistant is being reopened, and the admin guide says
  // that opens on the first step, not on the last one.
  firstUnfinishedIndex(state) {
    const steps = state.steps || [];
    const index = steps.findIndex((step) => !step.completed);
    return index < 0 ? 0 : index;
  }

  // The two panels Core itself ships are imported by name, written out literally so the
  // compiler can see the specifier (ADR-0020). A build without one shows that step's notice
  // rather than an empty panel. A module's own screen is reached by navigation instead,
  // because Core cannot import from a package that depends on it.
  async importComponents() {
    if (this.importsTried) {
      return;
    }
    this.importsTried = true;
    this.namingType = await this.tryImport(() => import('c/householdNamingSettings'));
    this.sampleDataType = await this.tryImport(() => import('c/sampleDataManager'));
  }

  async tryImport(loader) {
    try {
      const module = await loader();
      return module.default;
    } catch {
      return undefined;
    }
  }

  get steps() {
    return (this.state && this.state.steps) || [];
  }

  get canEdit() {
    return Boolean(this.state && this.state.canEdit);
  }

  get isReadOnly() {
    return Boolean(this.state) && !this.state.canEdit;
  }

  get activeStep() {
    return this.steps[this.activeIndex];
  }

  get activeKey() {
    return this.activeStep ? this.activeStep.key : undefined;
  }

  get ruleText() {
    if (!this.activeStep) {
      return '';
    }
    return this.activeStep.completionRule === 'Setting' ? RULE_SETTING : RULE_ACTION;
  }

  // "{0} of {1}" is a translatable sentence, not punctuation, so the wording is a label.
  get progressText() {
    return this.state
      ? PROGRESS_FORMAT.replace('{0}', this.state.stepsCompleted).replace(
          '{1}',
          this.state.stepsTotal
        )
      : '';
  }

  get counterText() {
    return this.state ? `${this.activeIndex + 1} / ${this.state.stepsTotal}` : '';
  }

  get showCompletionScreen() {
    if (!this.state || !this.state.isComplete) {
      return false;
    }
    return this.finishedHere || (!this.reopened && !this.reopenedHere);
  }

  get showPanels() {
    return Boolean(this.state) && !this.showCompletionScreen;
  }

  get isFirstStep() {
    return this.activeIndex === 0;
  }

  get isLastStep() {
    return this.state ? this.activeIndex >= this.state.stepsTotal - 1 : true;
  }

  get forwardLabel() {
    return this.isLastStep ? this.labels.finish : this.labels.next;
  }

  get summaryRows() {
    return this.steps.map((step) => ({
      ...step,
      badge: step.completed ? DONE_BADGE : step.skipped ? SKIPPED_BADGE : TODO_BADGE,
      badgeClass: step.completed ? 'slds-badge slds-theme_success' : 'slds-badge slds-badge_inverse'
    }));
  }

  get elapsedText() {
    return this.state &&
      this.state.elapsedMinutes !== null &&
      this.state.elapsedMinutes !== undefined
      ? String(this.state.elapsedMinutes)
      : '';
  }

  get isCoexistenceStep() {
    return this.activeKey === 'coexistence';
  }

  get isNamingStep() {
    return this.activeKey === 'naming';
  }

  get isAccessStep() {
    return this.activeKey === 'access';
  }

  get isModulesStep() {
    return this.activeKey === 'modules';
  }

  get isDataStep() {
    return this.activeKey === 'data';
  }

  get importAvailable() {
    return Boolean(this.state && this.state.importAvailable);
  }

  get roleOptions() {
    return ((this.state && this.state.roles) || []).map((role) => ({
      label: role.label || role.developerName || role,
      value: role.developerName || role
    }));
  }

  /** The fields this step declares, whichever package declared them. */
  get stepFields() {
    return (this.activeStep && this.activeStep.fields) || [];
  }

  get hasStepFields() {
    return this.stepFields.length > 0;
  }

  get modules() {
    return (this.state && this.state.modules) || [];
  }

  get coexistence() {
    return (this.state && this.state.coexistence) || {};
  }

  /** The settings section this step's answers live in afterwards, for the Open in Settings link. */
  get sectionUrl() {
    const section = this.activeStep && this.activeStep.target ? this.activeStep.target : '';
    return `${SETTINGS_PAGE}?c__section=${encodeURIComponent(section)}`;
  }

  get showNamingPanel() {
    return Boolean(this.namingType);
  }

  get showSampleDataPanel() {
    return this.showSampleData && Boolean(this.sampleDataType);
  }

  get sampleDataUnavailable() {
    return this.showSampleData && !this.sampleDataType;
  }

  handleBack() {
    if (this.activeIndex > 0) {
      this.moveTo(this.activeIndex - 1);
    }
  }

  // Nothing moves on until the save has answered, so an error is never reported about a step
  // Maria has already left.
  async handleForward() {
    if (this.canEdit && this.activeStep && this.activeStep.completionRule === 'Action') {
      await this.call(completeStep, { stepKey: this.activeKey }, false, () => this.advance());
      return;
    }
    this.advance();
  }

  async handleSkip() {
    if (!this.canEdit) {
      this.advance();
      return;
    }
    await this.call(skipStep, { stepKey: this.activeKey }, false, () => this.advance());
  }

  advance() {
    if (!this.isLastStep) {
      this.moveTo(this.activeIndex + 1);
    } else {
      this.reopenedHere = false;
      this.finishedHere = true;
    }
  }

  moveTo(index) {
    this.activeIndex = index;
    this.focusStepHeading = true;
    this.finishedHere = false;
  }

  /** Start setup again: the recorded progress is forgotten, the settings are not. */
  handleReset() {
    this.reopenedHere = true;
    this.call(resetSetup, {}, true);
  }

  handleReopen() {
    this.reopenedHere = true;
    this.moveTo(0);
  }

  /** Moves focus to the new step's heading, so a screen reader announces the change. */
  renderedCallback() {
    if (!this.focusStepHeading) {
      return;
    }
    const heading = this.template.querySelector('[data-id="step-label"]');
    if (heading) {
      this.focusStepHeading = false;
      heading.focus();
    }
  }

  handleCoexistenceConfirm(event) {
    this.call(applyCoexistence, { mode: event.detail.mode }, false, () => this.advance());
  }

  handleNamingSaved() {
    this.call(completeStep, { stepKey: 'naming' }, false);
  }

  // A step that asks one question moves on once it is answered; a step with several answers
  // (the organization step) stays open so Maria can fill in the rest. The step says which.
  handleFieldsSave(event) {
    const step = this.activeStep;
    if (!step) {
      return;
    }
    const afterwards = step.advanceOnSave ? () => this.advance() : undefined;
    this.call(
      saveStepValues,
      { stepKey: step.key, values: event.detail.values },
      false,
      afterwards
    );
  }

  handleUserChange(event) {
    this.chosenUserId = event.detail.recordId;
  }

  handleRoleChange(event) {
    this.chosenRole = event.detail.value;
  }

  handleAssignAccess() {
    this.call(
      assignAccess,
      { userId: this.chosenUserId, roleDeveloperName: this.chosenRole },
      false,
      () => {
        this.accessGranted = true;
        this.chosenUserId = undefined;
        // Recorded in a call of its own: the role is a setup object write, and the step's
        // progress cannot be saved in the same transaction as one.
        this.call(completeStep, { stepKey: 'access' }, false);
        // The picker holds its own selection, so clearing the property is not enough:
        // the admin guide promises the person box empties for the next colleague.
        const picker = this.template.querySelector('[data-id="user-picker"]');
        if (picker && typeof picker.clearSelection === 'function') {
          picker.clearSelection();
        }
      }
    );
  }

  handleShowSampleData() {
    this.showSampleData = true;
  }

  async call(action, parameters, moveToFirstUnfinished, afterwards) {
    try {
      this.applyState(await action(parameters), Boolean(moveToFirstUnfinished));
      this.errorMessage = undefined;
      if (afterwards) {
        afterwards();
      }
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    }
  }

  messageFrom(error) {
    return error && error.body && error.body.message ? error.body.message : LOAD_ERROR;
  }
}
