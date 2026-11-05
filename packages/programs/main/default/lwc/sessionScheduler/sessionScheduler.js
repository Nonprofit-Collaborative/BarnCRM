import { LightningElement, api } from 'lwc';
import { RefreshEvent } from 'lightning/refresh';
import LOCALE from '@salesforce/i18n/locale';
import getSchedule from '@salesforce/apex/SessionScheduleController.getSchedule';
import getTakenDays from '@salesforce/apex/SessionScheduleController.getTakenDays';
import scheduleSessions from '@salesforce/apex/SessionScheduleController.scheduleSessions';

import TITLE from '@salesforce/label/c.Programs_Schedule_Title';
import INTRO_COHORT from '@salesforce/label/c.Programs_Schedule_IntroCohort';
import SERVICE from '@salesforce/label/c.Programs_Log_Service';
import FROM_DATE from '@salesforce/label/c.Core_SetupChanges_From';
import TO_DATE from '@salesforce/label/c.Core_SetupChanges_To';
import WEEKDAYS from '@salesforce/label/c.Programs_Schedule_Weekdays';
import START_TIME from '@salesforce/label/c.Programs_Schedule_StartTime';
import SCHEDULE from '@salesforce/label/c.Programs_Schedule_Schedule';
import NO_SERVICES from '@salesforce/label/c.Programs_Schedule_NoServices';
import CHOOSE_DATES from '@salesforce/label/c.Programs_Schedule_ChooseDates';
import CHOOSE_WEEKDAYS from '@salesforce/label/c.Programs_Schedule_ChooseWeekdays';
import PREVIEW_NONE from '@salesforce/label/c.Programs_Schedule_PreviewNone';
import PREVIEW_ONE from '@salesforce/label/c.Programs_Schedule_PreviewOne';
import PREVIEW_MANY from '@salesforce/label/c.Programs_Schedule_PreviewMany';
import TOO_MANY from '@salesforce/label/c.Programs_Schedule_TooMany';
import CREATED_ONE from '@salesforce/label/c.Programs_Schedule_CreatedOne';
import CREATED_MANY from '@salesforce/label/c.Programs_Schedule_CreatedMany';
import SKIPPED from '@salesforce/label/c.Programs_Schedule_Skipped';
import ACTION_FAILED from '@salesforce/label/c.Programs_Schedule_ActionFailed';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

import {
  countMessage,
  format,
  newAndSkipped,
  previewMessage,
  sessionDates,
  weekdayOptions
} from './schedule';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * The Schedule Sessions panel on a cohort or a program (P-11, R-SE4): one Scheduled session of a
 * service for each chosen weekday between two dates. The dates are worked out in `schedule.js`;
 * the server checks the service and the count again. Days that already have a session of the
 * service for the same cohort are read from the server, counted in the preview and skipped.
 */
export default class SessionScheduler extends LightningElement {
  helpReady = isHelpLoaded('Programs');

  @api recordId;

  labels = {
    title: TITLE,
    service: SERVICE,
    from: FROM_DATE,
    to: TO_DATE,
    weekdays: WEEKDAYS,
    startTime: START_TIME,
    schedule: SCHEDULE,
    noServices: NO_SERVICES,
    loading: LOADING
  };

  schedule;
  serviceId;
  fromDate;
  toDate;
  chosenWeekdays = [];
  startTime;
  /** ISO dates in the chosen range that already have a session (R-SE4). */
  takenDays = [];
  takenRequest = 0;
  loading = true;
  busy = false;
  errorMessage;
  resultMessage;

  weekdayOptions = weekdayOptions(LOCALE);

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Programs').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  load() {
    this.loading = true;
    return getSchedule({ recordId: this.recordId })
      .then((schedule) => {
        this.schedule = schedule;
        const services = schedule.services || [];
        this.serviceId = services.length === 1 ? services[0].value : undefined;
        this.fromDate = schedule.startDate || undefined;
        this.toDate = schedule.endDate || undefined;
        return this.loadTaken();
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.loading = false;
      });
  }

  /** Reads the days of the range that already have a session; a later read wins. */
  loadTaken() {
    const request = ++this.takenRequest;
    if (!this.serviceId || !this.fromDate || !this.toDate) {
      this.takenDays = [];
      return Promise.resolve();
    }
    return getTakenDays({
      recordId: this.recordId,
      serviceId: this.serviceId,
      fromDate: this.fromDate,
      toDate: this.toDate
    })
      .then((days) => {
        if (request === this.takenRequest) {
          this.takenDays = days || [];
        }
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      });
  }

  get showSpinner() {
    return this.loading || this.busy;
  }

  get canSchedule() {
    return !!(this.schedule && this.schedule.canSchedule && this.hasServices);
  }

  get hasServices() {
    return !!(this.schedule && this.schedule.services && this.schedule.services.length > 0);
  }

  get noServices() {
    return !!this.schedule && !this.hasServices;
  }

  get intro() {
    if (!this.schedule) {
      return '';
    }
    return this.schedule.cohortId
      ? format(INTRO_COHORT, this.schedule.cohortName)
      : helpText('Programs', 'Programs_Schedule_IntroProgram');
  }

  get serviceOptions() {
    return (this.schedule && this.schedule.services) || [];
  }

  get planned() {
    return sessionDates(this.fromDate, this.toDate, this.chosenWeekdays);
  }

  get preview() {
    return previewMessage(
      this.planned,
      {
        chooseDates: CHOOSE_DATES,
        chooseWeekdays: CHOOSE_WEEKDAYS,
        tooMany: TOO_MANY,
        none: PREVIEW_NONE,
        one: PREVIEW_ONE,
        many: PREVIEW_MANY,
        skipped: SKIPPED
      },
      this.takenDays
    );
  }

  get scheduleDisabled() {
    const planned = this.planned;
    return (
      this.busy ||
      !this.serviceId ||
      planned.problem !== null ||
      planned.tooMany ||
      newAndSkipped(planned.dates, this.takenDays).toCreate === 0
    );
  }

  handleServiceChange(event) {
    this.clearMessages();
    this.serviceId = event.detail.value;
    return this.loadTaken();
  }

  handleFromChange(event) {
    this.clearMessages();
    this.fromDate = event.target.value || undefined;
    return this.loadTaken();
  }

  handleToChange(event) {
    this.clearMessages();
    this.toDate = event.target.value || undefined;
    return this.loadTaken();
  }

  handleWeekdaysChange(event) {
    this.clearMessages();
    this.chosenWeekdays = event.detail.value || [];
  }

  handleStartTimeChange(event) {
    this.clearMessages();
    this.startTime = event.target.value || undefined;
  }

  handleSchedule() {
    const planned = this.planned;
    if (this.scheduleDisabled) {
      return Promise.resolve();
    }
    this.clearMessages();
    this.busy = true;
    return scheduleSessions({
      recordId: this.recordId,
      serviceId: this.serviceId,
      dates: planned.dates,
      startTime: this.startTime || null
    })
      .then((schedule) => {
        this.schedule = schedule;
        this.resultMessage = countMessage(schedule.created, schedule.skipped || 0, {
          one: CREATED_ONE,
          many: CREATED_MANY,
          skipped: SKIPPED
        });
        this.chosenWeekdays = [];
        this.dispatchEvent(new RefreshEvent());
        return this.loadTaken();
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, ACTION_FAILED);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  clearMessages() {
    this.errorMessage = undefined;
    this.resultMessage = undefined;
  }
}
