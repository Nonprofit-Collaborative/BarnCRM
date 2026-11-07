import { LightningElement, api } from 'lwc';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getAppointments from '@salesforce/apex/EventAppointmentsController.getAppointments';
import addSlots from '@salesforce/apex/EventAppointmentsController.addSlots';
import book from '@salesforce/apex/EventAppointmentsController.book';
import setStatus from '@salesforce/apex/EventAppointmentsController.setStatus';
import { whenText } from 'c/eventsModel';
import {
  generateSlots,
  groupByHost,
  hostClashes,
  nextActions,
  statusWord
} from 'c/eventAppointmentsModel';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import EventRecordModal from 'c/eventRecordModal';
import BarnConfirmModal from 'c/barnConfirmModal';

import APPOINTMENTS from '@salesforce/label/c.Events_EventTab_Appointments';
import EDIT from '@salesforce/label/c.Core_CmdtManager_EditAction';
import DELETE from '@salesforce/label/c.Core_Find_Delete';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import ACTIONS from '@salesforce/label/c.Core_Shared_Actions';
import ACTIONS_FOR from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';

const HELP_PACKAGES = ['Events', 'Core'];
const SLOT_FIELDS = [
  'Name',
  'Host__c',
  'Contact__c',
  'Start__c',
  'End__c',
  'Status__c',
  'Location__c',
  'Notes__c'
];

/**
 * The Appointments tab of the event page (EV-15): bookable slots per host. Add Slots cuts one
 * day window into slots for a host; Book puts a person in an open slot; the row menu moves a
 * slot between statuses. Two slots of one host at the same time are flagged, never refused.
 */
export default class EventAppointments extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  /** The slot whose person picker is open. */
  bookingId;
  form = { hostId: null, date: '', from: '09:00', to: '12:00', minutes: 20, location: '' };

  labels = {
    appointments: APPOINTMENTS,
    cancel: CANCEL,
    actions: ACTIONS
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
      this.data = await getAppointments({ eventId: this.recordId });
      this.errorMessage = undefined;
      if (!this.form.date && this.data.eventStart) {
        this.form = { ...this.form, date: this.localDate(this.data.eventStart) };
      }
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Appointments_LoadFailed'));
      this.data = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  localDate(iso) {
    return new Intl.DateTimeFormat('en-CA', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      timeZone: TIME_ZONE
    }).format(new Date(iso));
  }

  get text() {
    return {
      intro: helpText('Events', 'Events_Appointments_Intro'),
      empty: helpText('Events', 'Events_Appointments_Empty'),
      addTitle: helpText('Events', 'Events_Appointments_AddTitle'),
      day: helpText('Events', 'Events_Appointments_Day'),
      from: helpText('Events', 'Events_Appointments_From'),
      to: helpText('Events', 'Events_Appointments_To'),
      minutes: helpText('Events', 'Events_Appointments_Minutes'),
      add: helpText('Events', 'Events_Appointments_AddSlots'),
      pickPerson: helpText('Events', 'Events_Appointments_PickPerson')
    };
  }

  get fieldLabels() {
    return (this.data && this.data.fieldLabels) || {};
  }

  get canAdd() {
    return Boolean(this.data && this.data.canAdd);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get slots() {
    return ((this.data && this.data.slots) || []).map((slot) => ({
      ...slot,
      end: slot.finish
    }));
  }

  get preview() {
    return generateSlots({
      date: this.form.date,
      from: this.form.from,
      to: this.form.to,
      minutes: this.form.minutes,
      existing: this.slots,
      hostId: this.form.hostId
    });
  }

  get previewText() {
    const result = this.preview;
    if (result.invalid === 'date') {
      return helpText('Events', 'Events_Appointments_Invalid_Date');
    }
    if (result.invalid === 'times') {
      return helpText('Events', 'Events_Appointments_Invalid_Times');
    }
    if (result.invalid === 'length') {
      return helpText('Events', 'Events_Appointments_Invalid_Length');
    }
    let text = helpText(
      'Events',
      'Events_Appointments_Summary',
      String(result.slots.length),
      String(this.form.minutes)
    );
    if (result.skipped) {
      text += ` ${helpText('Events', 'Events_Appointments_Skipped', String(result.skipped))}`;
    }
    if (result.capped) {
      text += ` ${helpText('Events', 'Events_Appointments_Capped', String(result.slots.length))}`;
    }
    return text;
  }

  get outsideEvent() {
    const slots = this.preview.slots;
    const start = this.data && this.data.eventStart ? new Date(this.data.eventStart) : null;
    const end = this.data && this.data.eventEnd ? new Date(this.data.eventEnd) : null;
    return (
      slots.length > 0 &&
      ((start && new Date(slots[0].start) < start) ||
        (end && new Date(slots[slots.length - 1].end) > end))
    );
  }

  get outsideText() {
    return helpText('Events', 'Events_Appointments_Outside');
  }

  get cannotAdd() {
    return this.busy || !this.form.hostId || this.preview.slots.length === 0;
  }

  get groups() {
    const clashes = hostClashes(this.slots);
    const words = {
      book: helpText('Events', 'Events_Appointments_Book'),
      complete: helpText('Events', 'Events_Appointments_Complete'),
      noShow: helpText('Events', 'Events_Appointments_NoShow'),
      release: helpText('Events', 'Events_Appointments_Release'),
      cancel: helpText('Events', 'Events_Appointments_CancelSlot'),
      reopen: helpText('Events', 'Events_Appointments_Reopen')
    };
    return groupByHost(this.slots).map((group) => ({
      ...group,
      key: group.hostId || 'none',
      summary: helpText(
        'Events',
        'Events_Appointments_HostSummary',
        String(group.open),
        String(group.booked)
      ),
      slots: group.slots.map((slot) => {
        const items = nextActions(slot.status)
          .filter((action) => action !== 'book' || this.data.canBook)
          .map((action) => ({ label: words[action], value: action }));
        items.push({ label: EDIT, value: 'edit' }, { label: DELETE, value: 'delete' });
        return {
          ...slot,
          when: whenText(slot.start, slot.end, { locale: LOCALE, timeZone: TIME_ZONE }),
          badge: statusWord(slot.status),
          personHref: slot.contactId ? `/lightning/r/${slot.contactId}/view` : null,
          clash: clashes.has(slot.id),
          isBooking: this.bookingId === slot.id,
          menuLabel: format(ACTIONS_FOR, slot.name),
          menuItems: items
        };
      })
    }));
  }

  get clashText() {
    return helpText('Events', 'Events_Appointments_HostClash');
  }

  get hasGroups() {
    return this.groups.length > 0;
  }

  get showEmpty() {
    return !this.isLoading && !this.hasError && Boolean(this.data) && !this.hasGroups;
  }

  handleHost(event) {
    this.form = { ...this.form, hostId: event.detail.recordId || null };
  }

  handleField(event) {
    const field = event.target.dataset.field;
    this.form = { ...this.form, [field]: event.detail.value };
  }

  async handleAdd() {
    const slots = this.preview.slots.map((slot) => ({ start: slot.start, finish: slot.end }));
    await this.run(async () => {
      await addSlots({
        eventId: this.recordId,
        hostId: this.form.hostId,
        slotsJson: JSON.stringify(slots),
        location: this.form.location
      });
    });
  }

  handleMenu(event) {
    const id = event.target.dataset.id;
    const slot = this.slots.find((row) => row.id === id);
    if (!slot) {
      return;
    }
    switch (event.detail.value) {
      case 'book':
        this.bookingId = slot.id;
        break;
      case 'complete':
        this.run(() => setStatus({ appointmentId: id, status: 'Completed' }));
        break;
      case 'noShow':
        this.run(() => setStatus({ appointmentId: id, status: 'No-Show' }));
        break;
      case 'release':
      case 'reopen':
        this.run(() => setStatus({ appointmentId: id, status: 'Open' }));
        break;
      case 'cancel':
        this.run(() => setStatus({ appointmentId: id, status: 'Cancelled' }));
        break;
      case 'delete':
        this.confirmDelete(slot);
        break;
      default:
        this.edit(slot);
    }
  }

  async handlePerson(event) {
    const contactId = event.detail.recordId;
    const appointmentId = event.target.dataset.id;
    if (!contactId) {
      return;
    }
    this.bookingId = undefined;
    await this.run(() => book({ appointmentId, contactId }));
  }

  handleBookCancel() {
    this.bookingId = undefined;
  }

  async edit(slot) {
    const saved = await EventRecordModal.open({
      label: `${EDIT}: ${slot.name}`,
      size: 'small',
      objectApiName: 'Event_Appointment__c',
      recordId: slot.id,
      fields: SLOT_FIELDS
    });
    if (saved) {
      await this.load();
    }
  }

  async confirmDelete(slot) {
    const confirmed = await BarnConfirmModal.open({
      label: `${DELETE}: ${slot.name}`,
      message: helpText('Events', 'Events_Shared_DeleteConfirm', slot.name),
      confirmLabel: DELETE,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive',
      size: 'small'
    });
    if (confirmed) {
      await this.run(() => deleteRecord(slot.id));
    }
  }

  /** Runs a change, then reloads; a refusal shows in a toast in plain words. */
  async run(change) {
    this.busy = true;
    try {
      await change();
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          message: messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')),
          variant: 'error'
        })
      );
    } finally {
      this.busy = false;
    }
    await this.load();
  }
}
