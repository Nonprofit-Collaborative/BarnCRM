import LightningModal from 'lightning/modal';
import { api } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import { MAX_OCCURRENCES, seriesStarts, whenText } from 'c/eventsModel';
import { helpText } from 'c/barnHelpText';

import REPEATS from '@salesforce/label/c.Events_Repeat_Repeats';
import EVERY_WEEK from '@salesforce/label/c.Events_Repeat_EveryWeek';
import EVERY_TWO_WEEKS from '@salesforce/label/c.Events_Repeat_EveryTwoWeeks';
import EVERY_MONTH from '@salesforce/label/c.Events_Repeat_EveryMonth';
import HOW_MANY from '@salesforce/label/c.Events_Repeat_HowMany';
import REPEAT_EVENT from '@salesforce/label/c.Events_Home_RepeatEvent';
import PREVIEW from '@salesforce/label/c.Core_BulkUpdate_Preview';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';

const DEFAULT_COUNT = 4;

/**
 * Repeat Event (R-EV4): a platform modal that asks how the event repeats (every week, every two
 * weeks or every month) and how many occurrences to add, and lists the new dates before anything
 * is saved. The dates are worked out by the framework-free `eventsModel`. It resolves
 * `{ starts }` (ISO date-times) when confirmed, and undefined when closed.
 *
 * Open it with EventRepeatModal.open({ label, size: 'small', eventName, startsAt }).
 */
export default class EventRepeatModal extends LightningModal {
  /** The event's name, for the explanation. */
  @api eventName;
  /** When the event starts, as an ISO date-time. */
  @api startsAt;

  labels = {
    repeats: REPEATS,
    howMany: HOW_MANY,
    confirm: REPEAT_EVENT,
    preview: PREVIEW,
    cancel: CANCEL
  };

  frequencyOptions = [
    { label: EVERY_WEEK, value: 'weekly' },
    { label: EVERY_TWO_WEEKS, value: 'biweekly' },
    { label: EVERY_MONTH, value: 'monthly' }
  ];

  frequency = 'weekly';
  count = DEFAULT_COUNT;
  maxCount = MAX_OCCURRENCES;

  get intro() {
    return helpText('Events', 'Events_Repeat_Intro', this.eventName || '');
  }

  get starts() {
    return seriesStarts(this.startsAt, this.frequency, this.count);
  }

  get previewRows() {
    return this.starts.map((start, index) => ({
      key: String(index),
      text: whenText(start, null, { locale: LOCALE, timeZone: TIME_ZONE })
    }));
  }

  get countValid() {
    const count = Number(this.count);
    return Number.isInteger(count) && count >= 1 && count <= MAX_OCCURRENCES;
  }

  get cannotConfirm() {
    return !this.countValid || this.starts.length === 0;
  }

  handleFrequency(event) {
    this.frequency = event.detail.value;
  }

  handleCount(event) {
    this.count = event.detail.value;
  }

  handleCancel() {
    this.close();
  }

  handleConfirm() {
    if (this.cannotConfirm) {
      return;
    }
    this.close({ starts: this.starts.map((start) => start.toISOString()) });
  }
}
