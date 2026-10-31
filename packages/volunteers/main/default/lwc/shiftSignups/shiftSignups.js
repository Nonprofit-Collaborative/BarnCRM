import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPanel from '@salesforce/apex/VolunteerShiftSignupsController.getPanel';
import addSignup from '@salesforce/apex/VolunteerShiftSignupsController.addSignup';
import setStatus from '@salesforce/apex/VolunteerShiftSignupsController.setStatus';

import TITLE from '@salesforce/label/c.Volunteers_Signups_Title';
import NEEDED from '@salesforce/label/c.Volunteers_Signups_Needed';
import FILLED from '@salesforce/label/c.Volunteers_Signups_Filled';
import REMAINING from '@salesforce/label/c.Volunteers_Signups_Remaining';
import ADD from '@salesforce/label/c.Volunteers_Signups_Add';
import PERSON from '@salesforce/label/c.Volunteers_Signups_Person';
import STATUS from '@salesforce/label/c.Volunteers_Signups_Status';
import ACTIONS from '@salesforce/label/c.Volunteers_Signups_Actions';
import SAVE from '@salesforce/label/c.Volunteers_Signups_Save';
import CANCEL from '@salesforce/label/c.Volunteers_Signups_Cancel';
import CAPTION from '@salesforce/label/c.Volunteers_Signups_Caption';
import STATUS_FOR from '@salesforce/label/c.Volunteers_Signups_StatusFor';
import ATTENDED from '@salesforce/label/c.Volunteers_Signups_Attended';
import MARK_ATTENDED from '@salesforce/label/c.Volunteers_Signups_MarkAttended';
import NO_SHOW from '@salesforce/label/c.Volunteers_Signups_NoShow';
import MARK_NO_SHOW from '@salesforce/label/c.Volunteers_Signups_MarkNoShow';
import EMPTY from '@salesforce/label/c.Volunteers_Signups_Empty';
import ADDED from '@salesforce/label/c.Volunteers_Signups_Added';
import CHANGED from '@salesforce/label/c.Volunteers_Signups_Changed';
import HOURS_WRITTEN from '@salesforce/label/c.Volunteers_Signups_HoursWritten';
import MORE_THAN_SHOWN from '@salesforce/label/c.Volunteers_Signups_MoreThanShown';
import ACTION_FAILED from '@salesforce/label/c.Volunteers_Signups_ActionFailed';
import NO_HOURS_WARNING from '@salesforce/label/c.Volunteers_Signups_NoHoursWarning';
import LOADING from '@salesforce/label/c.Volunteers_Loading';

const STATUS_SIGNED_UP = 'Signed up';
const STATUS_ATTENDED = 'Attended';
const STATUS_NO_SHOW = 'No show';
const MAX_SHOWN = 200;

function format(template, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), template);
}

/**
 * The Sign-ups panel on a shift (V-02): places filled and remaining, who is booked, adding a
 * person, and marking each one attended or a no show. Saves go through the sign-up automation,
 * so attendance writes the hours when the Attendance Creates Hours setting is on.
 */
export default class ShiftSignups extends NavigationMixin(LightningElement) {
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
    attended: ATTENDED,
    noShow: NO_SHOW,
    empty: EMPTY,
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
  /** The first load is still running. */
  loading = true;

  connectedCallback() {
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
      const target = this.template.querySelector(`[data-id="${this.focusTarget}"]`);
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
        this.errorMessage = this.messageFrom(error);
      })
      .finally(() => {
        this.loading = false;
      });
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

  get addDisabled() {
    return this.busy || this.showForm;
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
    return rows.map((row) => {
      const who = row.personName || row.name;
      return {
        ...row,
        displayName: who,
        href: `/lightning/r/Volunteer_Signup__c/${row.recordId}/view`,
        statusLabel: labelOf[row.status] || row.status,
        statusFor: format(STATUS_FOR, who),
        markAttended: format(MARK_ATTENDED, who),
        markNoShow: format(MARK_NO_SHOW, who),
        showAttended: this.canEdit && row.status !== STATUS_ATTENDED,
        showNoShow: this.canEdit && row.status !== STATUS_NO_SHOW
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
    this.focusTarget = 'person-picker';
  }

  handleCancel() {
    this.resetForm();
    this.focusTarget = 'add-button';
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
        this.focusTarget = 'result';
      })
      .catch((error) => {
        this.errorMessage = this.messageFrom(error);
        this.focusTarget = 'error-message';
      })
      .finally(() => {
        this.busy = false;
      });
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return ACTION_FAILED;
  }
}
