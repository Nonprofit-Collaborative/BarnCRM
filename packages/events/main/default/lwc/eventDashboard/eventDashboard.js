import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getDashboard from '@salesforce/apex/EventDashboardController.getDashboard';
import applyPlan from '@salesforce/apex/EventDashboardController.applyPlan';
import { format, messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import {
  canTakeTemplate,
  daysToGo,
  parseTemplates,
  planFromTemplate,
  setupSteps,
  timelineFor
} from 'c/eventDashboardModel';

const HELP_PACKAGES = ['Events', 'Core'];
const TIMELINE_STATUS = { past: 'closed', soon: 'pending', later: 'neutral' };

/**
 * The top of the event page's Details tab (EV-11): days to go, what the event has so far, the
 * setup steps still to do, and the opt-in templates. A template is only previewed until Apply
 * Template is pressed, and only an event with no tickets, tracks or sessions takes one.
 */
export default class EventDashboard extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(HELP_PACKAGES);
  data;
  isLoading = true;
  errorMessage;
  busy = false;
  templateKey = '';

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
      this.data = await getDashboard({ eventId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Events', 'Events_Dashboard_LoadFailed'));
      this.data = undefined;
    } finally {
      this.isLoading = false;
    }
  }

  get text() {
    return {
      title: helpText('Events', 'Events_Dashboard_Title'),
      intro: helpText('Events', 'Events_Dashboard_Intro'),
      setup: helpText('Events', 'Events_Dashboard_SetupTitle'),
      template: helpText('Events', 'Events_Dashboard_TemplateTitle'),
      templateIntro: helpText('Events', 'Events_Dashboard_TemplateIntro'),
      choose: helpText('Events', 'Events_Dashboard_TemplateChoose'),
      apply: helpText('Events', 'Events_Dashboard_Apply'),
      timeline: helpText('Events', 'Events_Dashboard_TimelineTitle'),
      done: helpText('Events', 'Events_Dashboard_StepDone'),
      todo: helpText('Events', 'Events_Dashboard_StepTodo')
    };
  }

  get hasData() {
    return Boolean(this.data);
  }

  get hasError() {
    return Boolean(this.errorMessage);
  }

  get counts() {
    return this.data || {};
  }

  get days() {
    return daysToGo(this.counts.startsAt);
  }

  get daysText() {
    const days = this.days;
    if (days === null) {
      return '';
    }
    if (days === 0) {
      return helpText('Events', 'Events_Dashboard_Today');
    }
    return days > 0
      ? format(helpText('Events', 'Events_Dashboard_DaysToGo'), String(days))
      : format(helpText('Events', 'Events_Dashboard_DaysAgo'), String(-days));
  }

  get tiles() {
    const c = this.counts;
    return [
      {
        key: 'tickets',
        label: helpText('Events', 'Events_Dashboard_TicketTypes'),
        value: c.ticketTypes
      },
      { key: 'tracks', label: helpText('Events', 'Events_Dashboard_Tracks'), value: c.tracks },
      {
        key: 'sessions',
        label: helpText('Events', 'Events_Dashboard_Sessions'),
        value: c.sessions
      },
      {
        key: 'speakers',
        label: helpText('Events', 'Events_Dashboard_Speakers'),
        value: c.speakers
      }
    ];
  }

  get speakersNote() {
    const c = this.counts;
    return c.speakers
      ? format(
          helpText('Events', 'Events_Dashboard_SpeakersConfirmed'),
          String(c.confirmedSpeakers),
          String(c.speakers)
        )
      : '';
  }

  get steps() {
    const words = {
      tickets: helpText('Events', 'Events_Dashboard_Step_Tickets'),
      agenda: helpText('Events', 'Events_Dashboard_Step_Agenda'),
      speakers: helpText('Events', 'Events_Dashboard_Step_Speakers')
    };
    return setupSteps(this.counts).map((step) => ({
      ...step,
      label: words[step.key],
      status: step.done ? 'active' : 'pending',
      badge: step.done ? this.text.done : this.text.todo
    }));
  }

  get templates() {
    return parseTemplates(this.counts.templatesJson);
  }

  get templateOptions() {
    return this.templates.map((t) => ({ label: t.name, value: t.key }));
  }

  /** Templates are offered only to an empty event, by someone who may add its records. */
  get showTemplates() {
    return (
      this.hasData &&
      this.counts.canApplyTemplate &&
      this.templates.length > 0 &&
      canTakeTemplate(this.counts)
    );
  }

  get chosen() {
    return this.templates.find((t) => t.key === this.templateKey);
  }

  get hasChosen() {
    return Boolean(this.chosen);
  }

  get chosenDescription() {
    return this.chosen ? this.chosen.description : '';
  }

  get plan() {
    return planFromTemplate(this.chosen, this.counts.startsAt, this.counts.endsAt);
  }

  get planSummary() {
    const plan = this.plan;
    const text = format(
      helpText('Events', 'Events_Dashboard_TemplateSummary'),
      String(plan.tracks.length),
      String(plan.ticketTypes.length),
      String(plan.sessions.length)
    );
    return plan.skipped
      ? `${text} ${format(helpText('Events', 'Events_Dashboard_TemplateSkipped'), String(plan.skipped))}`
      : text;
  }

  get timelineSteps() {
    const dateFormat = new Intl.DateTimeFormat(LOCALE, {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      timeZone: TIME_ZONE
    });
    return timelineFor(this.chosen, this.counts.startsAt).map((step) => ({
      ...step,
      key: `${step.title}-${step.due}`,
      dueText: dateFormat.format(new Date(step.due)),
      status: TIMELINE_STATUS[step.state]
    }));
  }

  get applyDisabled() {
    return this.busy || !this.hasChosen;
  }

  handleTemplate(event) {
    this.templateKey = event.detail.value;
  }

  async handleApply() {
    this.busy = true;
    try {
      const added = await applyPlan({
        eventId: this.recordId,
        planJson: JSON.stringify(this.plan)
      });
      this.dispatchEvent(
        new ShowToastEvent({
          message: format(helpText('Events', 'Events_Dashboard_Applied'), String(added)),
          variant: 'success'
        })
      );
      this.templateKey = '';
      await this.load();
      this.dispatchEvent(new CustomEvent('templateapplied'));
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          message: messageFrom(error, helpText('Events', 'Events_Dashboard_ApplyFailed')),
          variant: 'error'
        })
      );
    } finally {
      this.busy = false;
    }
  }
}
