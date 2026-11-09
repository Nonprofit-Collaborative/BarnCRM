import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRegistrations from '@salesforce/apex/EventRegistrationsController.getRegistrations';
import register from '@salesforce/apex/EventRegistrationsController.register';
import setStatus from '@salesforce/apex/EventRegistrationsController.setStatus';
import cancelRegistration from '@salesforce/apex/EventRegistrationsController.cancelRegistration';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import BarnConfirmModal from 'c/barnConfirmModal';
import {
  actionsFor,
  buildRequest,
  canSubmit,
  statusWord,
  summarize
} from 'c/eventRegistrationsModel';

import REGISTRATIONS from '@salesforce/label/c.Events_EventTab_Registrations';
import NEW_REGISTRATION from '@salesforce/label/c.Events_Registrations_New';
import REGISTER from '@salesforce/label/c.Events_Registrations_Register';
import ADD_GUEST from '@salesforce/label/c.Events_Registrations_AddGuest';
import EXISTING_PERSON from '@salesforce/label/c.Events_Registrations_ExistingPerson';
import MARK_ATTENDED from '@salesforce/label/c.Events_Registrations_MarkAttended';
import MARK_NO_SHOW from '@salesforce/label/c.Events_Registrations_MarkNoShow';
import MARK_REGISTERED from '@salesforce/label/c.Events_Registrations_MarkRegistered';
import MOVE_OFF_WAITLIST from '@salesforce/label/c.Events_Registrations_MoveOffWaitlist';
import CANCEL_ATTENDEE from '@salesforce/label/c.Events_Registrations_CancelAttendee';
import CANCEL_REGISTRATION from '@salesforce/label/c.Events_Registrations_CancelRegistration';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import ACTIONS from '@salesforce/label/c.Core_Shared_Actions';
import ACTIONS_FOR from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';

const HELP_PACKAGES = ['Events'];
const ACTION_LABELS = {
  markAttended: MARK_ATTENDED,
  markNoShow: MARK_NO_SHOW,
  markRegistered: MARK_REGISTERED,
  moveOffWaitlist: MOVE_OFF_WAITLIST,
  cancelAttendee: CANCEL_ATTENDEE,
  cancelRegistration: CANCEL_REGISTRATION
};

/**
 * The Registrations tab of the event page (EV-02): the event's attendees with their ticket,
 * price and status, and New Registration, which registers a chosen or typed person and any
 * guests by hand. People are matched to Core people on the server, never duplicated. Works
 * whether or not BarnCRM Forms is installed.
 */
export default class EventRegistrations extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  formOpen = false;
  form = { guests: [] };
  guestKey = 0;

  labels = {
    registrations: REGISTRATIONS,
    newRegistration: NEW_REGISTRATION,
    register: REGISTER,
    addGuest: ADD_GUEST,
    existingPerson: EXISTING_PERSON,
    cancel: CANCEL,
    actions: ACTIONS,
    get intro() {
      return helpText('Events', 'Events_Registrations_Intro');
    },
    get empty() {
      return helpText('Events', 'Events_Registrations_Empty');
    },
    get truncated() {
      return helpText('Events', 'Events_Registrations_Truncated');
    }
  };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.data = await getRegistrations({ eventId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Registrations_LoadFailed'));
      this.data = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  /** Field labels by object, from the server's `Object.Field` map. */
  get fieldLabels() {
    const flat = (this.data && this.data.fieldLabels) || {};
    const pick = (prefix) => {
      const out = {};
      Object.keys(flat)
        .filter((key) => key.startsWith(`${prefix}.`))
        .forEach((key) => {
          out[key.slice(prefix.length + 1)] = flat[key];
        });
      return out;
    };
    return {
      Contact: pick('Contact'),
      Attendee: pick('Event_Attendee__c'),
      Registration: pick('Event_Registration__c')
    };
  }

  get currencyCode() {
    return this.data && this.data.currencyCode;
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get truncated() {
    return Boolean(this.data && this.data.truncated);
  }

  get showNewButton() {
    return Boolean(this.data && this.data.canRegister) && !this.formOpen;
  }

  get summary() {
    return summarize(this.data && this.data.attendees, this.data && this.data.capacity);
  }

  get hasSummary() {
    return Boolean(this.data) && this.hasRows;
  }

  get summaryText() {
    const summary = this.summary;
    if (summary.seatsLeft === null) {
      return helpText(
        'Events',
        'Events_Registrations_Summary',
        summary.seated,
        summary.waitlisted,
        summary.attended
      );
    }
    return helpText(
      'Events',
      'Events_Registrations_SummarySeats',
      summary.seated,
      summary.waitlisted,
      summary.attended,
      summary.seatsLeft
    );
  }

  get ticketOptions() {
    return (this.data && this.data.tickets) || [];
  }

  get hasTickets() {
    return this.ticketOptions.length > 0;
  }

  get showTypedPerson() {
    return !this.form.contactId;
  }

  get guestRows() {
    return this.form.guests.map((guest, index) => ({
      ...guest,
      index,
      removeLabel: `${REMOVE}: ${[guest.firstName, guest.lastName].filter(Boolean).join(' ')}`
    }));
  }

  get cannotRegister() {
    return this.busy || !canSubmit(this.form);
  }

  get rows() {
    const attendees = (this.data && this.data.attendees) || [];
    const canChange = Boolean(this.data && this.data.canChange);
    return attendees.map((attendee) => {
      const menuItems = canChange
        ? actionsFor(attendee).map((action) => ({
            value: action.value,
            label: ACTION_LABELS[action.value]
          }))
        : [];
      return {
        ...attendee,
        href: attendee.contactId ? `/lightning/r/${attendee.contactId}/view` : null,
        registrationHref: `/lightning/r/${attendee.registrationId}/view`,
        statusWord: statusWord(attendee.status),
        menuLabel: format(ACTIONS_FOR, attendee.name),
        menuItems,
        hasMenu: menuItems.length > 0
      };
    });
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return !this.isLoading && !this.hasError && Boolean(this.data) && !this.hasRows;
  }

  handleOpenForm() {
    this.form = { guests: [], ticketTypeId: this.hasTickets ? this.ticketOptions[0].value : null };
    this.formOpen = true;
  }

  handleCloseForm() {
    this.formOpen = false;
  }

  handlePick(event) {
    this.form = { ...this.form, contactId: event.detail.recordId || null };
  }

  handleField(event) {
    this.form = { ...this.form, [event.target.dataset.field]: event.detail.value };
  }

  handleGuestField(event) {
    const index = Number(event.target.dataset.index);
    const field = event.target.dataset.field;
    const guests = this.form.guests.map((guest, i) => {
      return i === index ? { ...guest, [field]: event.detail.value } : guest;
    });
    this.form = { ...this.form, guests };
  }

  handleAddGuest() {
    this.guestKey += 1;
    const guest = { key: `guest-${this.guestKey}`, ticketTypeId: this.form.ticketTypeId || null };
    this.form = { ...this.form, guests: [...this.form.guests, guest] };
  }

  handleRemoveGuest(event) {
    const index = Number(event.currentTarget.dataset.index);
    this.form = { ...this.form, guests: this.form.guests.filter((guest, i) => i !== index) };
  }

  async handleRegister() {
    const request = buildRequest(this.recordId, this.form);
    await this.run(async () => {
      const result = await register({ requestJson: JSON.stringify(request) });
      this.formOpen = false;
      this.toast(
        helpText('Events', 'Events_Registrations_Done', result.registered, result.waitlisted),
        'success'
      );
      if (result.alreadyRegistered && result.alreadyRegistered.length) {
        this.toast(
          helpText('Events', 'Events_Registrations_Skipped', result.alreadyRegistered.join(', ')),
          'info'
        );
      }
    });
  }

  async handleMenu(event) {
    const attendee = this.rows.find((row) => row.id === event.target.dataset.id);
    if (!attendee) {
      return;
    }
    const action = actionsFor(attendee).find((item) => item.value === event.detail.value);
    if (!action) {
      return;
    }
    if (action.value === 'cancelRegistration') {
      const confirmed = await BarnConfirmModal.open({
        label: `${CANCEL_REGISTRATION}: ${attendee.registrationName}`,
        message: helpText(
          'Events',
          'Events_Registrations_CancelConfirm',
          attendee.registrationName
        ),
        confirmLabel: CANCEL_REGISTRATION,
        cancelLabel: CANCEL,
        confirmVariant: 'destructive',
        size: 'small'
      });
      if (confirmed) {
        await this.run(() => cancelRegistration({ registrationId: attendee.registrationId }));
      }
      return;
    }
    await this.run(() => setStatus({ attendeeId: attendee.id, status: action.target }));
  }

  /** Runs a change, then reloads; a refusal shows in a toast in plain words. */
  async run(change) {
    this.busy = true;
    try {
      await change();
    } catch (error) {
      this.toast(messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')), 'error');
    } finally {
      this.busy = false;
    }
    await this.load();
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
