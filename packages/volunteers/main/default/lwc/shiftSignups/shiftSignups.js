import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPanel from '@salesforce/apex/VolunteerShiftSignupsController.getPanel';
import addSignup from '@salesforce/apex/VolunteerShiftSignupsController.addSignup';
import setStatus from '@salesforce/apex/VolunteerShiftSignupsController.setStatus';
import closeShift from '@salesforce/apex/VolunteerShiftSignupsController.closeShift';
import BarnConfirmModal from 'c/barnConfirmModal';

import TITLE from '@salesforce/label/c.Volunteers_Signups_Title';
import NEEDED from '@salesforce/label/c.Volunteers_Signups_Needed';
import FILLED from '@salesforce/label/c.Volunteers_Signups_Filled';
import REMAINING from '@salesforce/label/c.Volunteers_Signups_Remaining';
import ADD from '@salesforce/label/c.Volunteers_Signups_Add';
import PERSON from '@salesforce/label/c.Core_Section_Person';
import STATUS from '@salesforce/label/c.Core_ImportRow_StatusLabel';
import ACTIONS from '@salesforce/label/c.Core_Shared_Attendance';
import SAVE from '@salesforce/label/c.Core_Kit_Save';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import CHANGE from '@salesforce/label/c.Core_Import_ChangesKind';
import CAPTION from '@salesforce/label/c.Volunteers_Signups_Caption';
import STATUS_FOR from '@salesforce/label/c.Volunteers_Signups_StatusFor';
import ATTENDED from '@salesforce/label/c.Volunteers_Signups_Attended';
import MARK_ATTENDED from '@salesforce/label/c.Volunteers_Signups_MarkAttended';
import NO_SHOW from '@salesforce/label/c.Volunteers_Signups_NoShow';
import MARK_NO_SHOW from '@salesforce/label/c.Volunteers_Signups_MarkNoShow';
import CLOSE_SHIFT from '@salesforce/label/c.Volunteers_Signups_CloseShift';
import CLOSE_MARK_NO_SHOW from '@salesforce/label/c.Volunteers_Signups_CloseMarkNoShow';
import CLOSE_KEEP from '@salesforce/label/c.Volunteers_Signups_CloseKeep';
import ADDED from '@salesforce/label/c.Volunteers_Signups_Added';
import CHANGED from '@salesforce/label/c.Core_Format_PairSentence';
import HOURS_WRITTEN from '@salesforce/label/c.Volunteers_Signups_HoursWritten';
import MORE_THAN_SHOWN from '@salesforce/label/c.Volunteers_Signups_MoreThanShown';
import NO_HOURS_WARNING from '@salesforce/label/c.Volunteers_Signups_NoHoursWarning';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';
import { bodyMessage, format } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const STATUS_SIGNED_UP = 'Signed up';
const STATUS_ATTENDED = 'Attended';
const STATUS_NO_SHOW = 'No show';
const MAX_SHOWN = 200;
/** Each sign-up status as a word of the status vocabulary (ux-kit.md, Visual Standard). */
const TONES = {
  'Signed up': 'neutral',
  Confirmed: 'info',
  Attended: 'done',
  'No show': 'warning',
  Cancelled: 'inactive'
};
const CHOICE_NO_SHOW = 'noShow';
const CHOICE_KEEP = 'keep';

/**
 * The Sign-ups panel on a shift (V-02): places filled and remaining, who is booked, adding a
 * person, marking each one attended or a no show, and closing the shift. Before the shift starts
 * each row offers its status picker; once it has started, Attended and No Show lead and the
 * picker is one Change away (modules-13). Saves go through the sign-up automation, so attendance
 * writes the hours when the Attendance Creates Hours setting is on.
 */
export default class ShiftSignups extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Volunteers');

  @api recordId;

  labels = {
    title: TITLE,
    needed: NEEDED,
    filled: FILLED,
    remaining: REMAINING,
    add: ADD,
    person: PERSON,
    status: STATUS,
    actions: ACTIONS,
    save: SAVE,
    cancel: CANCEL,
    change: CHANGE,
    attended: ATTENDED,
    noShow: NO_SHOW,
    closeShift: CLOSE_SHIFT,
    get empty() {
      return helpText('Volunteers', 'Volunteers_Signups_Empty');
    },
    loading: LOADING
  };

  panel;
  busy = false;
  showForm = false;
  draftPersonId;
  draftStatus = STATUS_SIGNED_UP;
  errorMessage;
  resultMessage;
  resultIsWarning = false;
  focusTarget;
  /** Sign-ups whose status picker was opened with Change after the shift started. */
  changingIds = [];
  /** The first load is still running. */
  loading = true;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Volunteers').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
    // Suggested Volunteers on the same page tells this panel when it signs someone up (V-11).
    window.addEventListener('barnshiftsignupschanged', this.handleSignupsChanged);
  }

  disconnectedCallback() {
    window.removeEventListener('barnshiftsignupschanged', this.handleSignupsChanged);
  }

  handleSignupsChanged = (event) => {
    if (event.detail && event.detail.shiftId === this.recordId) {
      this.load();
    }
  };

  renderedCallback() {
    if (this.focusTarget) {
      const target = this.template.querySelector(this.focusTarget);
      if (target) {
        this.focusTarget = undefined;
        target.focus();
      }
    }
  }

  load() {
    return getPanel({ shiftId: this.recordId })
      .then((panel) => {
        this.panel = panel;
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, this.actionFailed);
      })
      .finally(() => {
        this.loading = false;
      });
  }

  get actionFailed() {
    return helpText('Volunteers', 'Volunteers_Signups_ActionFailed');
  }

  get loaded() {
    return !!this.panel;
  }

  get showSpinner() {
    return this.loading || this.busy;
  }

  get canAdd() {
    return !!(this.panel && this.panel.canAdd);
  }

  get canEdit() {
    return !!(this.panel && this.panel.canEdit);
  }

  get canClose() {
    return !!(this.panel && this.panel.canClose);
  }

  get started() {
    return !!(this.panel && this.panel.shiftStarted);
  }

  /** Attendance leads once the shift has started (modules-13). */
  get showAttendance() {
    return this.canEdit && this.started;
  }

  get hasMeter() {
    return !!(this.panel && this.panel.volunteersNeeded > 0);
  }

  get addDisabled() {
    return this.busy || this.showForm;
  }

  get showEmptyAdd() {
    return this.canAdd && !this.showForm;
  }

  get saveDisabled() {
    return this.busy || !this.draftPersonId;
  }

  get statusOptions() {
    return this.panel ? this.panel.statusOptions : [];
  }

  get personObjectApiName() {
    return this.panel && this.panel.hasPersonAccounts ? 'Account' : 'Contact';
  }

  /** In a person account org, only person accounts: an organization is never a volunteer. */
  get personFilter() {
    if (!this.panel || !this.panel.personFilterField) {
      return undefined;
    }
    return { criteria: [{ fieldPath: this.panel.personFilterField, operator: 'eq', value: true }] };
  }

  get signups() {
    const rows = this.panel ? this.panel.signups : [];
    const labelOf = {};
    this.statusOptions.forEach((option) => {
      labelOf[option.value] = option.label;
    });
    const attendance = this.showAttendance;
    return rows.map((row) => {
      const who = row.personName || row.name;
      const changing = this.changingIds.includes(row.recordId);
      return {
        ...row,
        displayName: who,
        href: `/lightning/r/Volunteer_Signup__c/${row.recordId}/view`,
        statusLabel: labelOf[row.status] || row.status,
        tone: TONES[row.status] || 'neutral',
        statusFor: format(STATUS_FOR, who),
        markAttended: format(MARK_ATTENDED, who),
        markNoShow: format(MARK_NO_SHOW, who),
        showPicker: this.canEdit && (!attendance || changing),
        showChange: attendance && !changing,
        showAttended: attendance && row.status !== STATUS_ATTENDED,
        showNoShow: attendance && row.status !== STATUS_NO_SHOW
      };
    });
  }

  get hasSignups() {
    return this.signups.length > 0;
  }

  get isEmpty() {
    return this.loaded && !this.hasSignups;
  }

  get caption() {
    return format(CAPTION, this.panel ? this.panel.shiftName : '');
  }

  get moreThanShownText() {
    return format(MORE_THAN_SHOWN, MAX_SHOWN);
  }

  get hasError() {
    return !!this.errorMessage;
  }

  // ------------------------------------------------------------------------------- adding

  handleShowForm() {
    this.showForm = true;
    this.errorMessage = undefined;
    this.focusTarget = '[data-id="person-picker"]';
  }

  handleCancel() {
    this.resetForm();
    this.focusTarget = '[data-id="add-button"]';
  }

  handlePersonChange(event) {
    this.draftPersonId = event.detail ? event.detail.recordId : undefined;
  }

  handleDraftStatusChange(event) {
    this.draftStatus = event.detail.value;
  }

  handleSave() {
    return this.run(
      addSignup({
        shiftId: this.recordId,
        personId: this.draftPersonId,
        status: this.draftStatus
      }),
      () => {
        this.resetForm();
        return { text: ADDED };
      }
    );
  }

  resetForm() {
    this.showForm = false;
    this.draftPersonId = undefined;
    this.draftStatus = STATUS_SIGNED_UP;
  }

  /** The person's name opens the sign-up record, where its Notes can be edited or it deleted. */
  handleOpenSignup(event) {
    event.preventDefault();
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: {
        recordId: event.currentTarget.dataset.recordId,
        objectApiName: 'Volunteer_Signup__c',
        actionName: 'view'
      }
    });
  }

  // ----------------------------------------------------------------------- changing status

  /** Change: shows this row's status picker, and moves focus to it. */
  handleChangeStatus(event) {
    const recordId = event.target.dataset.recordId;
    this.changingIds = [...this.changingIds, recordId];
    this.focusTarget = `.status-picker[data-record-id="${recordId}"]`;
  }

  handleStatusChange(event) {
    return this.changeStatus(event.target.dataset.recordId, event.detail.value);
  }

  handleMarkAttended(event) {
    return this.changeStatus(event.target.dataset.recordId, STATUS_ATTENDED);
  }

  handleMarkNoShow(event) {
    return this.changeStatus(event.target.dataset.recordId, STATUS_NO_SHOW);
  }

  changeStatus(signupId, status) {
    const row = this.signups.find((candidate) => candidate.recordId === signupId);
    const who = row ? row.personName || row.name : '';
    return this.run(setStatus({ signupId, status }), (panel) => {
      this.changingIds = this.changingIds.filter((id) => id !== signupId);
      const option = panel.statusOptions.find((candidate) => candidate.value === status);
      const changed = format(CHANGED, who, option ? option.label : status);
      if (panel.hoursWritten) {
        return { text: `${changed} ${HOURS_WRITTEN}` };
      }
      // Attended with no hours entry at all (a shift with no end time, or the setting off):
      // say so by name, because nothing else tells the coordinator the hours are missing.
      if (status === STATUS_ATTENDED && !panel.hoursExist) {
        return { text: `${changed} ${format(NO_HOURS_WARNING, who)}`, warning: true };
      }
      return { text: changed };
    });
  }

  // ------------------------------------------------------------------------- closing

  /**
   * Close Shift (modules-12): asks first, offering to mark the people still Signed up or
   * Confirmed as No Show, then sets the shift to Completed.
   */
  async handleCloseShift() {
    const open = this.panel.openCount || 0;
    const offerNoShow = open > 0 && this.canEdit;
    const answer = await BarnConfirmModal.open(
      offerNoShow
        ? {
            label: CLOSE_SHIFT,
            size: 'small',
            choicesLabel:
              open === 1
                ? helpText('Volunteers', 'Volunteers_Signups_CloseQuestionOne')
                : helpText('Volunteers', 'Volunteers_Signups_CloseQuestion', open),
            choices: [
              { label: CLOSE_MARK_NO_SHOW, value: CHOICE_NO_SHOW },
              { label: CLOSE_KEEP, value: CHOICE_KEEP }
            ],
            choice: CHOICE_NO_SHOW,
            confirmLabel: CLOSE_SHIFT,
            cancelLabel: CANCEL
          }
        : {
            label: CLOSE_SHIFT,
            size: 'small',
            message: helpText('Volunteers', 'Volunteers_Signups_CloseConfirm'),
            confirmLabel: CLOSE_SHIFT,
            cancelLabel: CANCEL
          }
    );
    if (!answer) {
      this.focusTarget = '[data-id="close-shift"]';
      return undefined;
    }
    const markNoShow = offerNoShow && answer.choice === CHOICE_NO_SHOW;
    return this.run(closeShift({ shiftId: this.recordId, markNoShow }), () => ({
      text: markNoShow
        ? helpText('Volunteers', 'Volunteers_Signups_ClosedNoShow')
        : helpText('Volunteers', 'Volunteers_Signups_Closed')
    }));
  }

  /**
   * Runs one save, shows the panel it returns, and announces what happened once, in the status
   * region (a failure in the alert region); a toast as well would be read out twice.
   */
  run(call, describe) {
    this.busy = true;
    this.errorMessage = undefined;
    return call
      .then((panel) => {
        this.panel = panel;
        const outcome = describe(panel);
        this.resultMessage = outcome.text;
        this.resultIsWarning = outcome.warning === true;
        this.focusTarget = '[data-id="result"]';
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, this.actionFailed);
        this.focusTarget = '[data-id="error-message"]';
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
