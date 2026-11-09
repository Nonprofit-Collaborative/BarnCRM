import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getEvents from '@salesforce/apex/EventsHomeController.getEvents';
import repeatEvent from '@salesforce/apex/EventsHomeController.repeatEvent';
import { statusWord, whenText } from 'c/eventsModel';
import { format, messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import EventRepeatModal from 'c/eventRepeatModal';

import NEW_EVENT from '@salesforce/label/c.Events_Home_NewEvent';
import UPCOMING from '@salesforce/label/c.Events_Home_Upcoming';
import PAST from '@salesforce/label/c.Events_Home_Past';
import REPEAT_EVENT from '@salesforce/label/c.Events_Home_RepeatEvent';
import WHERE from '@salesforce/label/c.Events_Home_Where';
import ONLINE from '@salesforce/label/c.Events_Home_Online';
import WHEN from '@salesforce/label/c.Core_FieldAccess_ColWhen';
import DATE_RANGE from '@salesforce/label/c.Core_Address_DateRange';
import OPEN from '@salesforce/label/c.Core_Shared_Open';
import ACTIONS from '@salesforce/label/c.Core_Shared_Actions';
import ACTIONS_FOR from '@salesforce/label/c.Core_HouseholdMembersPanel_ActionsFor';

const HELP_PACKAGES = ['Events', 'Core'];
const ACTION_OPEN = 'open';
const ACTION_REPEAT = 'repeat';
const VIEW_UPCOMING = 'upcoming';
const VIEW_PAST = 'past';

/** A record's page in Lightning, for a link's href; a click navigates in place instead. */
const recordHref = (recordId) => `/lightning/r/${recordId}/view`;

/**
 * The Events page (EV-01, canonical model 29EV1): the events coming up, soonest first, or those
 * that are over, each with its dates, status, format and place, a link to open it and a menu to
 * repeat it (R-EV4). New Event opens the standard new event form.
 *
 * Dates in words and status words come from the framework-free `eventsModel`; the list comes
 * from `EventsHomeController`. Only a person who may create events sees New Event and Repeat
 * Event.
 */
export default class EventsHome extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded(HELP_PACKAGES);

  labels = {
    newEvent: NEW_EVENT,
    when: WHEN,
    where: WHERE,
    actions: ACTIONS,
    get intro() {
      return helpText('Events', 'Events_Home_Intro');
    }
  };

  icon = iconFor('Events_Home');

  viewOptions = [
    { label: UPCOMING, value: VIEW_UPCOMING },
    { label: PAST, value: VIEW_PAST }
  ];

  view = VIEW_UPCOMING;
  home;
  rows = [];
  isLoading = true;
  errorMessage;

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
      this.home = await getEvents({ view: this.view });
      this.errorMessage = undefined;
      this.rows = (this.home.events || []).map((event) => this.decorate(event));
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Home_LoadFailed'));
      this.rows = [];
    } finally {
      this.isLoading = false;
    }
  }

  /** What the template needs on each row, which it cannot compute itself. */
  decorate(event) {
    const items = [{ label: OPEN, value: ACTION_OPEN }];
    if (this.canCreate) {
      items.push({ label: REPEAT_EVENT, value: ACTION_REPEAT });
    }
    return {
      ...event,
      href: recordHref(event.id),
      whenText: whenText(event.startsAt, event.endsAt, {
        locale: LOCALE,
        timeZone: TIME_ZONE,
        range: DATE_RANGE
      }),
      statusWord: statusWord(event.status),
      whereText: event.venueName || (event.onlineLink ? ONLINE : ''),
      menuLabel: format(ACTIONS_FOR, event.name),
      menuItems: items
    };
  }

  get fieldLabels() {
    return (this.home && this.home.fieldLabels) || {};
  }

  get title() {
    return (this.home && this.home.title) || '';
  }

  get canCreate() {
    return Boolean(this.home && this.home.canCreate);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  get showEmpty() {
    return !this.isLoading && !this.hasError && !this.hasRows;
  }

  get emptyMessage() {
    return this.view === VIEW_PAST
      ? helpText('Events', 'Events_Home_EmptyPast')
      : helpText('Events', 'Events_Home_EmptyUpcoming');
  }

  get emptyHeading() {
    return this.view === VIEW_PAST
      ? helpText('Events', 'Events_Home_EmptyPastHeading')
      : helpText('Events', 'Events_Home_EmptyUpcomingHeading');
  }

  get truncatedMessage() {
    return this.home && this.home.truncated
      ? helpText('Events', 'Events_Home_Truncated', this.rows.length)
      : null;
  }

  handleView(event) {
    this.view = event.detail.value;
    this.load();
  }

  handleNewEvent() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Event__c', actionName: 'new' }
    });
  }

  /** An event's name is a link; a plain click opens the event in place. */
  handleOpen(event) {
    event.preventDefault();
    this.openRecord(event.currentTarget.dataset.id);
  }

  openRecord(recordId) {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId, objectApiName: 'Event__c', actionName: 'view' }
    });
  }

  handleMenu(event) {
    const eventId = event.target.dataset.id;
    if (event.detail.value === ACTION_REPEAT) {
      this.startRepeat(eventId);
    } else {
      this.openRecord(eventId);
    }
  }

  /** Repeat Event (R-EV4): the dialog works out the dates; the server makes the copies. */
  async startRepeat(eventId) {
    const row = this.rows.find((candidate) => candidate.id === eventId);
    if (!row) {
      return;
    }
    const result = await EventRepeatModal.open({
      label: `${REPEAT_EVENT}: ${row.name}`,
      size: 'small',
      eventName: row.name,
      startsAt: row.startsAt
    });
    if (!result || !result.starts || result.starts.length === 0) {
      return;
    }
    try {
      const made = await repeatEvent({ eventId, starts: result.starts });
      this.toast(helpText('Events', 'Events_Repeat_Done', made), 'success');
      await this.load();
    } catch (error) {
      this.toast(messageFrom(error, helpText('Events', 'Events_Shared_NotSaved')), 'error');
    }
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }
}
