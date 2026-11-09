import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSurvey from '@salesforce/apex/EventSurveyController.getSurvey';
import saveForm from '@salesforce/apex/EventSurveyController.saveForm';
import { responseRate, summarize } from 'c/eventSurveyModel';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

import SAVE from '@salesforce/label/c.Core_Kit_Save';

const HELP_PACKAGES = ['Events', 'Core'];

/**
 * The Survey section of the event page's Details tab (EV-18): choose the form attendees are sent
 * after the event, and read a summary of the answers. The forms live in Forms and are reached
 * through Core; with Forms absent the section draws nothing.
 */
export default class EventSurvey extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  /** The form picked in the list and not yet saved; undefined while it matches the saved one. */
  picked;

  labels = { save: SAVE };

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
      this.data = await getSurvey({ eventId: this.recordId });
      this.errorMessage = undefined;
      this.picked = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Survey_LoadFailed'));
      this.data = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  get text() {
    return {
      title: helpText('Events', 'Events_Survey_Title'),
      intro: helpText('Events', 'Events_Survey_Intro'),
      form: helpText('Events', 'Events_Survey_Form'),
      noSurvey: helpText('Events', 'Events_Survey_None'),
      noResponses: helpText('Events', 'Events_Survey_NoResponses'),
      noResponsesHeading: helpText('Events', 'Events_Survey_NoResponsesHeading'),
      results: helpText('Events', 'Events_Survey_Results')
    };
  }

  /** Nothing at all is drawn unless a module keeps forms. */
  get isAvailable() {
    return Boolean(this.data && this.data.available);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get showSection() {
    return this.helpReady && (this.isAvailable || this.hasError);
  }

  get savedKey() {
    return (this.data && this.data.formKey) || '';
  }

  get chosenKey() {
    return this.picked === undefined ? this.savedKey : this.picked;
  }

  get formOptions() {
    const forms = (this.data && this.data.forms) || [];
    const options = forms.map((form) => ({ label: form.label, value: form.key }));
    // A chosen form that is no longer public stays visible, so it can be changed on purpose.
    if (this.savedKey && !forms.some((form) => form.key === this.savedKey)) {
      options.unshift({
        label: helpText('Events', 'Events_Survey_Unavailable'),
        value: this.savedKey
      });
    }
    return [{ label: this.text.noSurvey, value: '' }, ...options];
  }

  get cannotSave() {
    return this.busy || this.chosenKey === this.savedKey;
  }

  get hasSurvey() {
    return Boolean(this.savedKey);
  }

  get responses() {
    return (this.data && this.data.responses) || [];
  }

  get hasResponses() {
    return this.responses.length > 0;
  }

  get showNoResponses() {
    return this.hasSurvey && !this.isLoading && !this.hasResponses;
  }

  get counts() {
    const sent = (this.data && this.data.sent) || 0;
    const attended = (this.data && this.data.attended) || 0;
    const rate = responseRate(this.responses.length, sent, attended);
    return format(
      helpText('Events', 'Events_Survey_Counts'),
      String(this.responses.length),
      String(sent),
      String(attended),
      rate === null ? '-' : `${rate}%`
    );
  }

  /** One card per question, with the figures its kind needs. */
  get summary() {
    return summarize((this.data && this.data.questions) || [], this.responses).map((entry) => ({
      ...entry,
      isNumber: entry.type === 'number',
      isChoice: entry.type === 'choice',
      isText: entry.type === 'text',
      hasMore: Boolean(entry.more),
      moreText: entry.more
        ? format(helpText('Events', 'Events_Survey_More'), String(entry.more))
        : '',
      averageText:
        entry.type === 'number' && entry.average !== null
          ? format(
              helpText('Events', 'Events_Survey_Average'),
              String(entry.average),
              String(entry.lowest),
              String(entry.highest)
            )
          : '',
      answeredText: format(helpText('Events', 'Events_Survey_Answered'), String(entry.answered)),
      options: (entry.options || []).map((option) => ({
        ...option,
        key: option.value,
        text: `${option.value}: ${option.count} (${option.percent}%)`
      })),
      texts: (entry.texts || []).map((one, index) => ({ ...one, key: `${entry.key}-${index}` }))
    }));
  }

  handleForm(event) {
    this.picked = event.detail.value;
  }

  async handleSave() {
    this.busy = true;
    try {
      await saveForm({ eventId: this.recordId, formKey: this.chosenKey });
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          message: messageFrom(error, helpText('Events', 'Events_Survey_SaveFailed')),
          variant: 'error'
        })
      );
    } finally {
      this.busy = false;
    }
    await this.load();
  }
}
