import { LightningElement, api } from 'lwc';
import { RefreshEvent } from 'lightning/refresh';
import LOCALE from '@salesforce/i18n/locale';
import getSchedule from '@salesforce/apex/SessionScheduleController.getSchedule';
import getTakenDays from '@salesforce/apex/SessionScheduleController.getTakenDays';
import scheduleSessions from '@salesforce/apex/SessionScheduleController.scheduleSessions';
import saveRepeatingSchedule from '@salesforce/apex/SessionScheduleController.saveRepeatingSchedule';

import TITLE from '@salesforce/label/c.Programs_Schedule_Title';
import SERVICE from '@salesforce/label/c.Programs_Log_Service';
import FROM_DATE from '@salesforce/label/c.Core_SetupChanges_From';
import TO_DATE from '@salesforce/label/c.Core_SetupChanges_To';
import WEEKDAYS from '@salesforce/label/c.Programs_Schedule_Weekdays';
import START_TIME from '@salesforce/label/c.Programs_Schedule_StartTime';
import END_TIME from '@salesforce/label/c.Programs_Schedule_EndTime';
import SCHEDULE from '@salesforce/label/c.Programs_Schedule_Schedule';
import SAVE_REPEATING from '@salesforce/label/c.Programs_Schedule_SaveRepeating';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

import {
  countMessage,
  format,
  newAndSkipped,
  previewMessage,
  sessionDates,
  timesInOrder,
  weekdayOptions
} from './schedule';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * The Schedule Sessions panel on a cohort or a program (P-11, R-SE4): one Scheduled session of a
 * service for each chosen weekday between two dates. The dates are worked out in `schedule.js`;
 * the server checks the service and the count again. Days that already have a session of the
 * service for the same cohort are read from the server, counted in the preview and skipped.
 * Save as Repeating Schedule keeps the same pattern as a session schedule (modules-24, R-SS6),
 * which creates its sessions now and keeps adding them each night.
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
    endTime: END_TIME,
    schedule: SCHEDULE,
    saveRepeating: SAVE_REPEATING,
    get noServices() {
      return helpText('Programs', 'Programs_Schedule_NoServices');
    },
    loading: LOADING
  };

  schedule;
  serviceId;
  fromDate;
  toDate;
  chosenWeekdays = [];
  startTime;
  endTime;
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
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Schedule'));
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
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Schedule'));
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

  get canSaveSchedule() {
    return !!(this.schedule && this.schedule.canSaveSchedule);
  }

  /** A schedule needs a service, the dates, a day and times in order; days taken are fine. */
  get saveRepeatingDisabled() {
    return (
      this.busy ||
      !this.serviceId ||
      !timesInOrder(this.startTime, this.endTime) ||
      this.planned.problem !== null
    );
  }

  get intro() {
    if (!this.schedule) {
      return '';
    }
    return this.schedule.cohortId
      ? format(helpText('Programs', 'Programs_Schedule_IntroCohort'), this.schedule.cohortName)
      : helpText('Programs', 'Programs_Schedule_IntroProgram');
  }

  get serviceOptions() {
    return (this.schedule && this.schedule.services) || [];
  }

  get planned() {
    return sessionDates(this.fromDate, this.toDate, this.chosenWeekdays);
  }

  get preview() {
    if (!timesInOrder(this.startTime, this.endTime)) {
      return helpText('Programs', 'Programs_Schedule_EndBeforeStart');
    }
    return previewMessage(
      this.planned,
      {
        chooseDates: helpText('Programs', 'Programs_Schedule_ChooseDates'),
        chooseWeekdays: helpText('Programs', 'Programs_Schedule_ChooseWeekdays'),
        tooMany: helpText('Programs', 'Programs_Schedule_TooMany'),
        none: helpText('Programs', 'Programs_Schedule_PreviewNone'),
        one: helpText('Programs', 'Programs_Schedule_PreviewOne'),
        many: helpText('Programs', 'Programs_Schedule_PreviewMany'),
        skipped: helpText('Programs', 'Programs_Schedule_Skipped')
      },
      this.takenDays
    );
  }

  get scheduleDisabled() {
    const planned = this.planned;
    return (
      this.busy ||
      !this.serviceId ||
      !timesInOrder(this.startTime, this.endTime) ||
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

  handleEndTimeChange(event) {
    this.clearMessages();
    this.endTime = event.target.value || undefined;
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
      startTime: this.startTime || null,
      endTime: this.endTime || null
    })
      .then((schedule) => {
        this.schedule = schedule;
        this.resultMessage = countMessage(schedule.created, schedule.skipped || 0, {
          one: helpText('Programs', 'Programs_Schedule_CreatedOne'),
          many: helpText('Programs', 'Programs_Schedule_CreatedMany'),
          skipped: helpText('Programs', 'Programs_Schedule_Skipped')
        });
        this.chosenWeekdays = [];
        this.dispatchEvent(new RefreshEvent());
        return this.loadTaken();
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Schedule'));
      })
      .finally(() => {
        this.busy = false;
      });
  }

  handleSaveRepeating() {
    if (this.saveRepeatingDisabled) {
      return Promise.resolve();
    }
    this.clearMessages();
    this.busy = true;
    return saveRepeatingSchedule({
      recordId: this.recordId,
      serviceId: this.serviceId,
      fromDate: this.fromDate,
      toDate: this.toDate,
      weekdays: this.chosenWeekdays,
      startTime: this.startTime || null,
      endTime: this.endTime || null
    })
      .then((schedule) => {
        this.schedule = schedule;
        this.resultMessage = helpText(
          'Programs',
          'Programs_Schedule_SavedRepeating',
          schedule.created || 0
        );
        this.chosenWeekdays = [];
        this.dispatchEvent(new RefreshEvent());
        return this.loadTaken();
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, helpText('Programs', 'Programs_Fail_Schedule'));
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
