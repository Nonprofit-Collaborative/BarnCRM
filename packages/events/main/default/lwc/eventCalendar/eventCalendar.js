import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import FIRST_DAY_OF_WEEK from '@salesforce/i18n/firstDayOfWeek';
import getCalendar from '@salesforce/apex/EventCalendarController.getCalendar';
import {
  ALL,
  EVENT_FORMATS,
  EVENT_STATUSES,
  dayKey,
  entriesFrom,
  filterEntries,
  firstDayFrom,
  icsFileName,
  icsFor,
  listDays,
  monthWeeks,
  shiftAnchor,
  viewRange,
  weekDays,
  weekdayOrder
} from 'c/eventCalendarModel';
import { statusWord, whenText } from 'c/eventsModel';
import { format, messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const HELP_PACKAGES = ['Events', 'Core'];
const VIEW_MONTH = 'month';
const VIEW_WEEK = 'week';
const VIEW_LIST = 'list';

/**
 * The Event Calendar tab (EV-19): events, and optionally their sessions, as a month, a week or a
 * list, filtered by status and format; an entry opens its record, and the list view gives each
 * entry a calendar file (.ics) built in the browser. No outside service.
 *
 * The days each view shows, the filters, the day an entry falls on in the person's time zone and
 * the .ics text come from the framework-free `eventCalendarModel`; this component draws them.
 */
export default class EventCalendar extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded(HELP_PACKAGES);
  icon = iconFor('Events_Calendar');
  view = VIEW_MONTH;
  anchor;
  today;
  status = ALL;
  format = ALL;
  showSessions = false;
  entries = [];
  truncated = false;
  isLoading = true;
  errorMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    this.today = dayKey(new Date(), TIME_ZONE);
    this.anchor = this.today;
    this.load();
  }

  get firstDay() {
    return firstDayFrom(FIRST_DAY_OF_WEEK);
  }

  async load() {
    this.isLoading = true;
    const range = viewRange(this.view, this.anchor, this.firstDay);
    try {
      const calendar = await getCalendar({
        fromDate: range.from,
        toDate: range.to,
        includeSessions: this.showSessions
      });
      this.entries = entriesFrom(calendar, TIME_ZONE);
      this.truncated = Boolean(calendar.truncated);
      this.today = calendar.today || this.today;
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Calendar_LoadFailed'));
      this.entries = [];
      this.truncated = false;
    } finally {
      this.isLoading = false;
    }
  }

  get labels() {
    return {
      intro: helpText('Events', 'Events_Calendar_Intro'),
      previous: helpText('Events', 'Events_Calendar_Previous'),
      next: helpText('Events', 'Events_Calendar_Next'),
      today: helpText('Events', 'Events_Calendar_Today'),
      view: helpText('Events', 'Events_Calendar_View'),
      status: helpText('Events', 'Events_Calendar_Status'),
      format: helpText('Events', 'Events_Calendar_Format'),
      sessions: helpText('Events', 'Events_Calendar_ShowSessions'),
      empty: helpText('Events', 'Events_Calendar_Empty'),
      emptyHeading: helpText('Events', 'Events_Calendar_EmptyHeading'),
      open: helpText('Events', 'Events_Calendar_Open'),
      download: helpText('Events', 'Events_Calendar_Download'),
      truncated: helpText('Events', 'Events_Calendar_Truncated'),
      session: helpText('Events', 'Events_Calendar_Session')
    };
  }

  get viewOptions() {
    return [
      { label: helpText('Events', 'Events_Calendar_Month'), value: VIEW_MONTH },
      { label: helpText('Events', 'Events_Calendar_Week'), value: VIEW_WEEK },
      { label: helpText('Events', 'Events_Calendar_List'), value: VIEW_LIST }
    ];
  }

  get statusOptions() {
    return [
      { label: helpText('Events', 'Events_Calendar_AllStatuses'), value: ALL },
      ...EVENT_STATUSES.map((value) => ({ label: value, value }))
    ];
  }

  get formatOptions() {
    return [
      { label: helpText('Events', 'Events_Calendar_AllFormats'), value: ALL },
      ...EVENT_FORMATS.map((value) => ({ label: value, value }))
    ];
  }

  get isMonth() {
    return this.view === VIEW_MONTH;
  }

  get isWeek() {
    return this.view === VIEW_WEEK;
  }

  get isList() {
    return this.view === VIEW_LIST;
  }

  get showGrid() {
    return this.isMonth || this.isWeek;
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get showTruncated() {
    return this.truncated;
  }

  get anchorDate() {
    return new Date(`${this.anchor}T00:00:00Z`);
  }

  get title() {
    const zone = { timeZone: 'UTC' };
    if (this.isWeek) {
      const days = this.weekOfDays;
      const day = new Intl.DateTimeFormat(LOCALE, { month: 'short', day: 'numeric', ...zone });
      const first = new Date(`${days[0].date}T00:00:00Z`);
      const last = new Date(`${days[6].date}T00:00:00Z`);
      return format(
        helpText('Events', 'Events_Calendar_WeekOf'),
        day.format(first),
        day.format(last)
      );
    }
    return new Intl.DateTimeFormat(LOCALE, { month: 'long', year: 'numeric', ...zone }).format(
      this.anchorDate
    );
  }

  get filtered() {
    return filterEntries(this.entries, {
      status: this.status,
      format: this.format,
      sessions: this.showSessions
    });
  }

  get weekdays() {
    const names = new Intl.DateTimeFormat(LOCALE, { weekday: 'short', timeZone: 'UTC' });
    // 2023-01-01 was a Sunday, so day n of the week is January 1 + n.
    return weekdayOrder(this.firstDay).map((day) => ({
      key: String(day),
      name: names.format(new Date(Date.UTC(2023, 0, 1 + day)))
    }));
  }

  get weeks() {
    if (!this.isMonth || !this.anchor) {
      return [];
    }
    const date = this.anchorDate;
    return monthWeeks(
      date.getUTCFullYear(),
      date.getUTCMonth() + 1,
      this.filtered,
      this.today,
      this.firstDay
    ).map((week) => ({
      ...week,
      days: week.days.map((day) => this.decorateDay(day))
    }));
  }

  get weekOfDays() {
    return weekDays(this.anchor, this.filtered, this.today, this.firstDay);
  }

  get weekColumns() {
    if (!this.isWeek) {
      return [];
    }
    const heading = new Intl.DateTimeFormat(LOCALE, {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
      timeZone: 'UTC'
    });
    return this.weekOfDays.map((day) => ({
      ...this.decorateDay(day),
      heading: heading.format(new Date(`${day.date}T00:00:00Z`))
    }));
  }

  get listGroups() {
    if (!this.isList) {
      return [];
    }
    const range = viewRange(VIEW_LIST, this.anchor, this.firstDay);
    const heading = new Intl.DateTimeFormat(LOCALE, {
      weekday: 'long',
      month: 'long',
      day: 'numeric',
      timeZone: 'UTC'
    });
    return listDays(range.from, range.to, this.filtered, this.today).map((day) => ({
      key: day.key,
      heading: heading.format(new Date(`${day.date}T00:00:00Z`)),
      isToday: day.isToday,
      items: day.items.map((item) => this.decorateListItem(item))
    }));
  }

  get showEmpty() {
    return !this.isLoading && !this.hasError && this.filtered.length === 0;
  }

  decorateDay(day) {
    return {
      ...day,
      cellClass: [
        'barn-day',
        day.inMonth ? '' : 'barn-day_outside',
        day.isToday ? 'barn-day_today' : '',
        day.items.length ? '' : 'barn-day_empty'
      ]
        .filter(Boolean)
        .join(' '),
      items: day.items.map((item) => this.decorateItem(item))
    };
  }

  whenOf(item) {
    return whenText(item.startsAt, item.endsAt, { locale: LOCALE, timeZone: TIME_ZONE });
  }

  decorateItem(item) {
    const sessionNote = item.kind === 'session' ? ` (${this.labels.session})` : '';
    return {
      ...item,
      itemClass: [
        'barn-item slds-size_full',
        `barn-item_${item.kind}`,
        item.status === 'Cancelled' ? 'barn-item_cancelled' : ''
      ]
        .filter(Boolean)
        .join(' '),
      text: `${item.continues ? '↪ ' : ''}${item.name}${sessionNote}`,
      title: `${item.name}${sessionNote}: ${this.whenOf(item)}${item.place ? `, ${item.place}` : ''}${
        item.status ? ` (${item.status})` : ''
      }`
    };
  }

  decorateListItem(item) {
    return {
      ...item,
      when: this.whenOf(item),
      badge: statusWord(item.status),
      kindLabel: item.kind === 'session' ? item.typeLabel || this.labels.session : item.typeLabel,
      eventNote:
        item.kind === 'session' && item.eventName
          ? format(helpText('Events', 'Events_Calendar_OfEvent'), item.eventName)
          : '',
      openLabel: `${this.labels.open}: ${item.name}`,
      downloadLabel: `${this.labels.download}: ${item.name}`
    };
  }

  handleView(event) {
    this.view = event.detail.value;
    this.load();
  }

  handleStatus(event) {
    this.status = event.detail.value;
  }

  handleFormat(event) {
    this.format = event.detail.value;
  }

  handleSessions(event) {
    this.showSessions = event.detail.checked;
    this.load();
  }

  handlePrevious() {
    this.anchor = shiftAnchor(this.view, this.anchor, -1);
    this.load();
  }

  handleNext() {
    this.anchor = shiftAnchor(this.view, this.anchor, 1);
    this.load();
  }

  handleToday() {
    this.anchor = dayKey(new Date(), TIME_ZONE);
    this.load();
  }

  handleOpen(event) {
    const { recordId, object } = event.currentTarget.dataset;
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId, objectApiName: object, actionName: 'view' }
    });
  }

  /** Builds the .ics text in the browser and hands it to the person as a file. */
  handleDownload(event) {
    const entry = this.entries.find((one) => one.key === event.currentTarget.dataset.key);
    if (!entry) {
      return;
    }
    const blob = new Blob([icsFor([entry])], { type: 'text/calendar;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = icsFileName(entry);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
  }
}
