import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getVolunteers from '@salesforce/apex/EventVolunteersController.getVolunteers';
import addJob from '@salesforce/apex/EventVolunteersController.addJob';
import addShift from '@salesforce/apex/EventVolunteersController.addShift';
import { whenText } from 'c/eventsModel';
import { fillState, fillWord, shiftDefaults, shiftProblem, totals } from 'c/eventVolunteersModel';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import SAVE from '@salesforce/label/c.Core_Kit_Save';

const HELP_PACKAGES = ['Events'];

/**
 * The Volunteers section of the event page's Details tab (EV-08): the event's volunteer jobs and
 * shifts, kept in Volunteers and reached through Core. With Volunteers absent it draws nothing.
 * New Job adds a job for the event; Add Shift adds a shift to a job inside the event's dates.
 */
export default class EventVolunteers extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  newJobName = '';
  /** The job whose Add Shift form is open, with the values typed so far. */
  shiftForm;

  labels = { save: SAVE, cancel: CANCEL };

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
      this.data = await getVolunteers({ eventId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Volunteers_LoadFailed'));
      this.data = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  get text() {
    return {
      title: helpText('Events', 'Events_Volunteers_Title'),
      intro: helpText('Events', 'Events_Volunteers_Intro'),
      empty: helpText('Events', 'Events_Volunteers_Empty'),
      emptyHeading: helpText('Events', 'Events_Volunteers_EmptyHeading'),
      jobName: helpText('Events', 'Events_Volunteers_JobName'),
      addJob: helpText('Events', 'Events_Volunteers_AddJob'),
      addShift: helpText('Events', 'Events_Volunteers_AddShift'),
      from: helpText('Events', 'Events_Volunteers_From'),
      to: helpText('Events', 'Events_Volunteers_To'),
      needed: helpText('Events', 'Events_Volunteers_Needed'),
      noShifts: helpText('Events', 'Events_Volunteers_NoShifts')
    };
  }

  /** Nothing at all is drawn unless a module keeps volunteer jobs. */
  get isAvailable() {
    return Boolean(this.data && this.data.available);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get showSection() {
    return this.helpReady && (this.isAvailable || this.hasError);
  }

  get summary() {
    const sum = totals(this.data && this.data.jobs);
    return format(
      helpText('Events', 'Events_Volunteers_Summary'),
      String(sum.jobs),
      String(sum.shifts),
      String(sum.filled),
      String(sum.needed)
    );
  }

  get jobs() {
    const jobs = (this.data && this.data.jobs) || [];
    return jobs.map((job) => ({
      ...job,
      hasShifts: job.shifts.length > 0,
      isAddingShift: Boolean(this.shiftForm && this.shiftForm.jobId === job.id),
      shifts: job.shifts.map((shift) => {
        const state = fillState(shift.filled, shift.needed);
        return {
          ...shift,
          when: whenText(shift.startTime, shift.endTime, { locale: LOCALE, timeZone: TIME_ZONE }),
          fill: format(
            helpText('Events', 'Events_Volunteers_Filled'),
            String(shift.filled || 0),
            String(shift.needed || 0)
          ),
          badge: fillWord(state)
        };
      })
    }));
  }

  get hasJobs() {
    return this.jobs.length > 0;
  }

  get showEmpty() {
    return this.isAvailable && !this.isLoading && !this.hasJobs;
  }

  get cannotAddJob() {
    return this.busy || !this.newJobName.trim();
  }

  get shiftProblemText() {
    if (!this.shiftForm) {
      return '';
    }
    const problem = shiftProblem(this.shiftForm, this.data.eventStart, this.data.eventEnd);
    if (problem === 'times') {
      return helpText('Events', 'Events_Volunteers_Problem_Times');
    }
    if (problem === 'needed') {
      return helpText('Events', 'Events_Volunteers_Problem_Needed');
    }
    return problem === 'outside' ? helpText('Events', 'Events_Volunteers_Problem_Outside') : '';
  }

  /** A shift outside the event's dates only warns: setup the day before is ordinary. */
  get cannotSaveShift() {
    if (this.busy || !this.shiftForm) {
      return true;
    }
    const problem = shiftProblem(this.shiftForm, this.data.eventStart, this.data.eventEnd);
    return Boolean(problem) && problem !== 'outside';
  }

  handleJobName(event) {
    this.newJobName = event.detail.value;
  }

  async handleAddJob() {
    await this.run(async () => {
      await addJob({ eventId: this.recordId, name: this.newJobName, description: null });
      this.newJobName = '';
    });
  }

  handleOpenShift(event) {
    this.shiftForm = {
      jobId: event.target.dataset.id,
      ...shiftDefaults(this.data.eventStart, this.data.eventEnd)
    };
  }

  handleShiftField(event) {
    const field = event.target.dataset.field;
    const value = field === 'needed' ? Number(event.detail.value) : event.detail.value;
    this.shiftForm = { ...this.shiftForm, [field]: value };
  }

  handleShiftCancel() {
    this.shiftForm = undefined;
  }

  async handleShiftSave() {
    const { jobId, startTime, endTime, needed } = this.shiftForm;
    await this.run(async () => {
      await addShift({ eventId: this.recordId, jobId, startTime, endTime, needed });
      this.shiftForm = undefined;
    });
  }

  /** Runs a change, then reloads; a refusal shows in a toast in plain words. */
  async run(change) {
    this.busy = true;
    try {
      await change();
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          message: messageFrom(error, helpText('Events', 'Events_Volunteers_SaveFailed')),
          variant: 'error'
        })
      );
    } finally {
      this.busy = false;
    }
    await this.load();
  }
}
