import { LightningElement, api } from 'lwc';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getAgenda from '@salesforce/apex/EventAgendaController.getAgenda';
import moveSession from '@salesforce/apex/EventAgendaController.moveSession';
import { whenText } from 'c/eventsModel';
import { NO_TRACK, UNSCHEDULED, clashesOf, columnsFor, daysOf } from 'c/eventAgendaModel';
import { createDragController } from 'c/barnDrag';
import { dragInstructions, dragMessages } from 'c/barnDragText';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import EventRecordModal from 'c/eventRecordModal';
import BarnConfirmModal from 'c/barnConfirmModal';

import AGENDA from '@salesforce/label/c.Events_EventTab_Agenda';
import NEW_TRACK from '@salesforce/label/c.Events_Agenda_NewTrack';
import NEW_SESSION from '@salesforce/label/c.Events_Agenda_NewSession';
import NO_TRACK_LABEL from '@salesforce/label/c.Events_Agenda_NoTrack';
import UNSCHEDULED_LABEL from '@salesforce/label/c.Events_Agenda_Unscheduled';
import ALL from '@salesforce/label/c.Core_DataJobs_ShowAll';
import WHEN from '@salesforce/label/c.Core_FieldAccess_ColWhen';
import EDIT from '@salesforce/label/c.Core_CmdtManager_EditAction';
import DELETE from '@salesforce/label/c.Core_Find_Delete';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import MOVE_TO from '@salesforce/label/c.Core_Shared_MoveTo';
import DATE_RANGE from '@salesforce/label/c.Core_Address_DateRange';
import ACTIONS_FOR from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';

const HELP_PACKAGES = ['Events', 'Core'];
const TRACK = 'Event_Track__c';
const SESSION = 'Event_Session__c';
const TRACK_FIELDS = ['Name', 'Sort_Order__c', 'Description__c'];
const SESSION_FIELDS = [
  'Name',
  'Track__c',
  'Start__c',
  'End__c',
  'Room__c',
  'Session_Type__c',
  'Status__c',
  'Capacity__c',
  'Description__c'
];
const MOVE_PREFIX = 'move:';

/** The other sessions' titles, for a clash note. */
const namesOf = (ids, names) => ids.map((id) => names.get(id)).join(', ');

/**
 * The Agenda tab of the event page (EV-04): the Agenda Builder. A column per track, then No
 * Track, with the chosen day's sessions by time. A session moves to another track by its menu
 * (Move to), by dragging its handle, or by keyboard on the handle (c/barnDrag: Space picks up,
 * arrows move, Space drops, Escape cancels), and only its track changes (R-ESN5). Sessions in one
 * room, or with one speaker, at overlapping times are flagged and never refused (R-ESN4).
 */
export default class EventAgenda extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  agenda;
  day = '';
  isLoading = true;
  errorMessage;
  dragState;
  liveText = '';
  drag;

  labels = {
    agenda: AGENDA,
    newTrack: NEW_TRACK,
    newSession: NEW_SESSION,
    when: WHEN,
    get intro() {
      return helpText('Events', 'Events_Agenda_Intro');
    },
    get empty() {
      return helpText('Events', 'Events_Agenda_Empty');
    },
    get emptyHeading() {
      return helpText('Events', 'Events_Agenda_EmptyHeading');
    }
  };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    this.drag = createDragController({
      root: this.template,
      layout: 'columns',
      // Read when spoken, not now: the help catalog may still be on its way.
      messages: {
        pickedUp: (name) => dragMessages().pickedUp(name),
        position: (zone, position, count) => dragMessages().position(zone, position, count),
        dropped: (name, zone) => dragMessages().dropped(name, zone),
        cancelled: (name) => dragMessages().cancelled(name)
      },
      announce: (text) => {
        this.liveText = text;
      },
      onChange: (state) => {
        this.dragState = state;
      },
      canDrop: (itemId, fromZone, toZone) => fromZone !== toZone,
      onDrop: ({ itemId, fromZone, toZone }) => {
        if (!toZone || fromZone === toZone) {
          return false;
        }
        this.moveTo(itemId, toZone);
        return true;
      }
    });
    this.load();
  }

  disconnectedCallback() {
    if (this.drag) {
      this.drag.destroy();
    }
  }

  async load() {
    this.isLoading = true;
    try {
      this.agenda = await getAgenda({ eventId: this.recordId });
      this.errorMessage = undefined;
      if (this.day && !this.days.includes(this.day)) {
        this.day = '';
      }
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Agenda_LoadFailed'));
      this.agenda = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  get sessions() {
    return (this.agenda && this.agenda.sessions) || [];
  }

  get tracks() {
    return (this.agenda && this.agenda.tracks) || [];
  }

  /** The confirmed sessions with their time and room, for the rating codes (EV-27). */
  get ratingSessions() {
    return this.sessions
      .filter((session) => session.status === 'Confirmed')
      .map((session) => ({
        id: session.id,
        name: session.name,
        room: session.room,
        whenText: whenText(session.startsAt, session.endsAt, {
          locale: LOCALE,
          timeZone: TIME_ZONE,
          range: DATE_RANGE
        })
      }));
  }

  get days() {
    return daysOf(this.sessions, TIME_ZONE);
  }

  get dayOptions() {
    const dayName = new Intl.DateTimeFormat(LOCALE, {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
      timeZone: 'UTC'
    });
    return [
      { label: ALL, value: '' },
      ...this.days.map((day) => ({
        label:
          day === UNSCHEDULED ? UNSCHEDULED_LABEL : dayName.format(new Date(`${day}T12:00:00Z`)),
        value: day
      }))
    ];
  }

  get canMove() {
    return Boolean(this.agenda && this.agenda.canMove);
  }

  get canAddTrack() {
    return Boolean(this.agenda && this.agenda.canAddTrack);
  }

  get canAddSession() {
    return Boolean(this.agenda && this.agenda.canAddSession);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get showBoard() {
    return Boolean(this.agenda) && (this.sessions.length > 0 || this.tracks.length > 0);
  }

  get showEmpty() {
    return !this.isLoading && !this.hasError && Boolean(this.agenda) && !this.showBoard;
  }

  get truncatedMessage() {
    return this.agenda && this.agenda.truncated
      ? helpText('Events', 'Events_Agenda_Truncated', this.sessions.length)
      : null;
  }

  get trackMenuItems() {
    return [
      { label: EDIT, value: 'edit' },
      { label: DELETE, value: 'delete' }
    ];
  }

  get dragHelp() {
    return dragInstructions();
  }

  /** The board as drawn: names, menus, clash notes and the drag highlight. */
  get columns() {
    const clashes = clashesOf(this.sessions);
    const names = new Map(this.sessions.map((session) => [session.id, session.name]));
    const columns = columnsFor(this.tracks, this.sessions, this.day, TIME_ZONE);
    const active = Boolean(this.dragState && this.dragState.active);
    return columns.map((column) => {
      const name = column.id === NO_TRACK ? NO_TRACK_LABEL : column.name;
      const isTarget =
        active && this.dragState.overZone === column.id && this.dragState.fromZone !== column.id;
      return {
        ...column,
        name,
        isTrack: column.id !== NO_TRACK,
        isEmpty: column.sessions.length === 0,
        menuLabel: format(ACTIONS_FOR, name),
        zoneClass:
          'agenda-column slds-box slds-box_x-small' + (isTarget ? ' agenda-zone_target' : ''),
        cards: column.sessions.map((session) =>
          this.card(session, column, columns, clashes.get(session.id), names, active)
        )
      };
    });
  }

  card(session, column, columns, clash, names, active) {
    const notes = [];
    if (clash && clash.room.length) {
      notes.push({
        key: `${session.id}-room`,
        text: helpText('Events', 'Events_Agenda_RoomClash', namesOf(clash.room, names))
      });
    }
    if (clash && clash.speaker.length) {
      notes.push({
        key: `${session.id}-speaker`,
        text: helpText('Events', 'Events_Agenda_SpeakerClash', namesOf(clash.speaker, names))
      });
    }
    const moves = columns
      .filter((other) => other.id !== column.id)
      .map((other) => ({
        label: format(MOVE_TO, other.id === NO_TRACK ? NO_TRACK_LABEL : other.name),
        value: MOVE_PREFIX + other.id
      }));
    const items = [{ label: EDIT, value: 'edit' }];
    if (this.canMove) {
      items.push(...moves);
    }
    items.push({ label: DELETE, value: 'delete' });
    const dragging = active && this.dragState.itemId === session.id;
    return {
      ...session,
      whenText: whenText(session.startsAt, session.endsAt, {
        locale: LOCALE,
        timeZone: TIME_ZONE,
        range: DATE_RANGE
      }),
      detailText: [session.sessionType, session.room].filter(Boolean).join(', '),
      ratingText: session.ratingCount
        ? helpText(
            'Events',
            'Events_Agenda_Rated',
            Number(session.averageRating).toFixed(1),
            session.ratingCount
          )
        : '',
      isCancelled: session.status === 'Cancelled',
      notes,
      hasNotes: notes.length > 0,
      menuItems: items,
      menuLabel: format(ACTIONS_FOR, session.name),
      cardClass:
        'agenda-card slds-item slds-var-p-around_x-small' +
        (dragging ? ' agenda-card_dragging' : '') +
        (notes.length ? ' agenda-card_clash' : '')
    };
  }

  handleDay(event) {
    this.day = event.detail.value;
  }

  handleDragPointerDown(event) {
    this.drag.pointerDown(event);
  }

  handleDragKeyDown(event) {
    this.drag.keyDown(event);
  }

  handleNewTrack() {
    this.openForm(TRACK, null, NEW_TRACK);
  }

  handleNewSession() {
    this.openForm(SESSION, null, NEW_SESSION);
  }

  handleTrackMenu(event) {
    const track = this.tracks.find((candidate) => candidate.id === event.target.dataset.id);
    if (track) {
      this.act(event.detail.value, TRACK, track.id, track.name);
    }
  }

  handleSessionMenu(event) {
    const session = this.sessions.find((candidate) => candidate.id === event.target.dataset.id);
    if (!session) {
      return;
    }
    const value = event.detail.value;
    if (value.startsWith(MOVE_PREFIX)) {
      this.moveTo(session.id, value.substring(MOVE_PREFIX.length));
      return;
    }
    this.act(value, SESSION, session.id, session.name);
  }

  handleOpenSession(event) {
    const session = this.sessions.find((candidate) => candidate.id === event.target.dataset.id);
    if (session) {
      this.act('edit', SESSION, session.id, session.name);
    }
  }

  act(value, objectName, recordId, name) {
    if (value === 'delete') {
      this.confirmDelete(recordId, name);
    } else {
      this.openForm(objectName, recordId, `${EDIT}: ${name}`);
    }
  }

  /** R-ESN5: only the track changes; the menu, the drag and the keyboard all end here. */
  async moveTo(sessionId, columnId) {
    try {
      await moveSession({ sessionId, trackId: columnId === NO_TRACK ? null : columnId });
      await this.load();
    } catch (error) {
      this.toast(messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')));
      await this.load();
    }
  }

  async openForm(objectName, recordId, label) {
    const saved = await EventRecordModal.open({
      label,
      size: 'small',
      objectApiName: objectName,
      recordId,
      fields: objectName === TRACK ? TRACK_FIELDS : SESSION_FIELDS,
      defaults: { Event__c: this.recordId }
    });
    if (saved) {
      await this.load();
    }
  }

  async confirmDelete(recordId, name) {
    const confirmed = await BarnConfirmModal.open({
      label: `${DELETE}: ${name}`,
      message: helpText('Events', 'Events_Shared_DeleteConfirm', name),
      confirmLabel: DELETE,
      cancelLabel: CANCEL,
      confirmVariant: 'destructive',
      size: 'small'
    });
    if (!confirmed) {
      return;
    }
    try {
      await deleteRecord(recordId);
      await this.load();
    } catch (error) {
      this.toast(messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')));
    }
  }

  toast(message) {
    this.dispatchEvent(new ShowToastEvent({ message, variant: 'error' }));
  }
}
