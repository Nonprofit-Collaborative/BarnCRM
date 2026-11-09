import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSeating from '@salesforce/apex/EventSeatingController.getSeating';
import saveTable from '@salesforce/apex/EventSeatingController.saveTable';
import deleteTable from '@salesforce/apex/EventSeatingController.deleteTable';
import assignSeats from '@salesforce/apex/EventSeatingController.assignSeats';
import saveNeeds from '@salesforce/apex/EventSeatingController.saveNeeds';
import { localIsoDate, messageFrom, saveBlob } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import {
  guestsAt,
  moveSeats,
  overflowAfter,
  seatingCsv,
  suggestSeating,
  tableCounts,
  unseated
} from 'c/eventSeatingModel';

import SEATING from '@salesforce/label/c.Events_EventTab_Seating';

const HELP_PACKAGES = ['Events', 'Core'];
const NO_TABLE = '';

/**
 * The Seating tab of the event page (EV-13): tables with capacity, host and optional sponsor, a
 * seating chart, a guest list to seat people (a party, the people on one registration, moves
 * together unless turned off), a warning when a table holds more people than it has seats,
 * dietary and access needs, a suggested seating for the people not yet seated, and the chart as
 * CSV. All arithmetic is in `eventSeatingModel`.
 */
export default class EventSeating extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  keepParty = true;
  tableForm;

  labels = {
    seating: SEATING,
    get intro() {
      return helpText('Events', 'Events_Seating_Intro');
    },
    get empty() {
      return helpText('Events', 'Events_Seating_Empty');
    },
    get emptyHeading() {
      return helpText('Events', 'Events_Seating_EmptyHeading');
    },
    get addTable() {
      return helpText('Events', 'Events_Seating_AddTable');
    },
    get suggest() {
      return helpText('Events', 'Events_Seating_Suggest');
    },
    get exportCsv() {
      return helpText('Events', 'Events_Seating_Export');
    },
    get keepParty() {
      return helpText('Events', 'Events_Seating_KeepParty');
    },
    get tableName() {
      return helpText('Events', 'Events_Seating_TableName');
    },
    get capacity() {
      return helpText('Events', 'Events_Seating_Capacity');
    },
    get host() {
      return helpText('Events', 'Events_Seating_Host');
    },
    get sponsor() {
      return helpText('Events', 'Events_Seating_Sponsor');
    },
    get noSponsor() {
      return helpText('Events', 'Events_Seating_NoSponsor');
    },
    get save() {
      return helpText('Events', 'Events_Seating_Save');
    },
    get cancel() {
      return helpText('Events', 'Events_Seating_Cancel');
    },
    get edit() {
      return helpText('Events', 'Events_Seating_Edit');
    },
    get remove() {
      return helpText('Events', 'Events_Seating_Remove');
    },
    get guests() {
      return helpText('Events', 'Events_Seating_Guests');
    },
    get guest() {
      return helpText('Events', 'Events_Seating_Guest');
    },
    get organization() {
      return helpText('Events', 'Events_Seating_Organization');
    },
    get table() {
      return helpText('Events', 'Events_Seating_Table');
    },
    get dietary() {
      return helpText('Events', 'Events_Seating_Dietary');
    },
    get access() {
      return helpText('Events', 'Events_Seating_Access');
    },
    get unseatedOption() {
      return helpText('Events', 'Events_Seating_NoTable');
    },
    get noGuests() {
      return helpText('Events', 'Events_Seating_NoGuests');
    },
    get truncated() {
      return helpText('Events', 'Events_Seating_Truncated');
    },
    get emptyTable() {
      return helpText('Events', 'Events_Seating_EmptyTable');
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
      this.data = await getSeating({ eventId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Seating_LoadFailed'));
      this.data = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  get tables() {
    return (this.data && this.data.tables) || [];
  }

  get guestList() {
    return (this.data && this.data.guests) || [];
  }

  get canEdit() {
    return Boolean(this.data && this.data.canEdit);
  }

  get readOnly() {
    return !this.canEdit;
  }

  get cannotSeat() {
    return this.busy || !this.canEdit;
  }

  get canAddTable() {
    return Boolean(this.data && this.data.canAddTable);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get truncated() {
    return Boolean(this.data && this.data.truncated);
  }

  get showEmpty() {
    return !this.isLoading && !this.hasError && Boolean(this.data) && !this.tables.length;
  }

  get hasTables() {
    return this.tables.length > 0;
  }

  get hasGuests() {
    return this.guestList.length > 0;
  }

  get showNoGuests() {
    return Boolean(this.data) && !this.hasGuests;
  }

  get cannotSuggest() {
    return this.busy || !this.hasTables || unseated(this.guestList).length === 0;
  }

  get cannotExport() {
    return !this.hasTables && !this.hasGuests;
  }

  get summaryText() {
    const seated = this.guestList.length - unseated(this.guestList).length;
    return helpText(
      'Events',
      'Events_Seating_Summary',
      seated,
      this.guestList.length,
      this.guestList.length - seated
    );
  }

  /** The tables with their counts and seated guests, ready to draw. */
  get chart() {
    return tableCounts(this.tables, this.guestList).map((table) => ({
      ...table,
      key: table.id,
      href: `/lightning/r/${table.id}/view`,
      seatsText: helpText('Events', 'Events_Seating_SeatsOf', table.seated, table.capacity),
      overText: table.isOver
        ? helpText('Events', 'Events_Seating_Over', table.over, table.name)
        : '',
      cardClass: table.isOver
        ? 'slds-box slds-box_x-small slds-theme_warning'
        : 'slds-box slds-box_x-small',
      hostText: table.hostName ? helpText('Events', 'Events_Seating_HostedBy', table.hostName) : '',
      sponsorText: table.sponsorName
        ? helpText('Events', 'Events_Seating_SponsoredBy', table.sponsorName)
        : '',
      guests: guestsAt(this.guestList, table.id).map((guest) => ({
        ...guest,
        noteText: [guest.dietary, guest.access].filter(Boolean).join('; ')
      })),
      hasGuests: table.seated > 0
    }));
  }

  get tableOptions() {
    return [
      { value: NO_TABLE, label: this.labels.unseatedOption },
      ...this.tables.map((table) => ({ value: table.id, label: table.name }))
    ];
  }

  get sponsorOptions() {
    return [
      { value: '', label: this.labels.noSponsor },
      ...((this.data && this.data.sponsors) || [])
    ];
  }

  get rows() {
    return this.guestList.map((guest) => ({
      ...guest,
      tableValue: guest.tableId || NO_TABLE,
      href: `/lightning/r/${guest.id}/view`
    }));
  }

  get showForm() {
    return Boolean(this.tableForm);
  }

  get cannotSaveTable() {
    return (
      this.busy ||
      !this.tableForm ||
      !String(this.tableForm.name || '').trim() ||
      !(Number(this.tableForm.capacity) >= 1)
    );
  }

  handleKeepParty(event) {
    this.keepParty = event.detail.checked;
  }

  handleAddTable() {
    this.tableForm = { name: '', capacity: 10, sponsorId: '' };
  }

  handleEditTable(event) {
    const table = this.tables.find((item) => item.id === event.currentTarget.dataset.id);
    if (table) {
      this.tableForm = {
        id: table.id,
        name: table.name,
        capacity: table.capacity,
        hostId: table.hostId,
        sponsorId: table.sponsorId || ''
      };
    }
  }

  handleTableField(event) {
    const field = event.currentTarget.dataset.field;
    const value = event.detail && event.detail.value !== undefined ? event.detail.value : '';
    this.tableForm = { ...this.tableForm, [field]: value };
  }

  handleHostPick(event) {
    this.tableForm = { ...this.tableForm, hostId: event.detail.recordId || null };
  }

  handleCancelTable() {
    this.tableForm = undefined;
  }

  async handleSaveTable() {
    const form = this.tableForm;
    await this.run(async () => {
      await saveTable({
        inputJson: JSON.stringify({
          id: form.id,
          eventId: this.recordId,
          name: form.name,
          capacity: Number(form.capacity),
          hostId: form.hostId || null,
          sponsorId: form.sponsorId || null
        })
      });
      this.tableForm = undefined;
    });
  }

  async handleDeleteTable(event) {
    const id = event.currentTarget.dataset.id;
    await this.run(() => deleteTable({ tableId: id }));
  }

  async handleSeat(event) {
    const guestId = event.currentTarget.dataset.id;
    const tableId = event.detail.value;
    const seats = moveSeats(this.guestList, guestId, tableId, this.keepParty);
    await this.seat(seats);
  }

  async handleSuggest() {
    const plan = suggestSeating(this.tables, this.guestList);
    if (plan.seats.length) {
      await this.seat(plan.seats);
    }
    if (plan.unplaced.length) {
      this.toast(helpText('Events', 'Events_Seating_Unplaced', plan.unplaced.length), 'warning');
    }
  }

  async seat(seats) {
    if (!seats.length) {
      return;
    }
    const overfull = overflowAfter(this.tables, this.guestList, seats);
    await this.run(async () => {
      await assignSeats({ eventId: this.recordId, seatsJson: JSON.stringify(seats) });
    });
    overfull.forEach((table) => {
      this.toast(helpText('Events', 'Events_Seating_OverWarning', table.name), 'warning');
    });
  }

  async handleNeeds(event) {
    const id = event.currentTarget.dataset.id;
    const field = event.currentTarget.dataset.field;
    const guest = this.guestList.find((item) => item.id === id);
    if (!guest) {
      return;
    }
    const value = event.target.value || '';
    const dietary = field === 'dietary' ? value : guest.dietary;
    const access = field === 'access' ? value : guest.access;
    if ((guest[field] || '') === value) {
      return;
    }
    await this.run(() => saveNeeds({ attendeeId: id, dietary, access }));
  }

  handleExport() {
    const blob = new Blob([seatingCsv(this.tables, this.guestList)], {
      type: 'text/csv;charset=utf-8;'
    });
    saveBlob(blob, `Event-Seating-${localIsoDate()}.csv`);
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
