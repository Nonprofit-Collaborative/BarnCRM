import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
// Bare, and correctly so: a custom permission defined in the same package resolves without a
// namespace prefix, so this is not the B5 problem that TriggerHandler.getName had.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import getPage from '@salesforce/apex/AutomationControlController.getPage';
import pauseAll from '@salesforce/apex/AutomationControlController.pauseAll';
import resumeAll from '@salesforce/apex/AutomationControlController.resumeAll';
import setEnabled from '@salesforce/apex/AutomationControlController.setEnabled';

import TITLE from '@salesforce/label/c.Core_AutomationControl_Title';
import INTRO from '@salesforce/label/c.Core_AutomationControl_Intro';
import PAUSE_BUTTON from '@salesforce/label/c.Core_AutomationControl_PauseButton';
import RESUME_BUTTON from '@salesforce/label/c.Core_AutomationControl_ResumeButton';
import PAUSE_LENGTH from '@salesforce/label/c.Core_AutomationControl_PauseLength';
import PAUSED_BANNER from '@salesforce/label/c.Core_AutomationControl_PausedBanner';
import READ_ONLY from '@salesforce/label/c.Core_AutomationControl_ReadOnly';
import EMPTY from '@salesforce/label/c.Core_AutomationControl_Empty';
import RUNS_ON from '@salesforce/label/c.Core_AutomationControl_RunsOn';
import ONE_HOUR from '@salesforce/label/c.Core_AutomationControl_OneHour';
import TWO_HOURS from '@salesforce/label/c.Core_AutomationControl_TwoHours';
import FOUR_HOURS from '@salesforce/label/c.Core_AutomationControl_FourHours';
import EIGHT_HOURS from '@salesforce/label/c.Core_AutomationControl_EightHours';
import TWENTY_FOUR_HOURS from '@salesforce/label/c.Core_AutomationControl_TwentyFourHours';
import ERROR_PREFIX from '@salesforce/label/c.Core_AutomationControl_ErrorPrefix';
import PAUSED_PREFIX from '@salesforce/label/c.Core_AutomationControl_PausedPrefix';
import PAUSED_BY from '@salesforce/label/c.Core_AutomationControl_PausedBy';
import RESUMES_ITSELF from '@salesforce/label/c.Core_AutomationControl_ResumesItself';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Automation_UnexpectedError';
import ALWAYS_RUNS from '@salesforce/label/c.Core_Automation_AlwaysRuns';

const HOUR_OPTIONS = [
  { label: ONE_HOUR, value: '1' },
  { label: TWO_HOURS, value: '2' },
  { label: FOUR_HOURS, value: '4' },
  { label: EIGHT_HOURS, value: '8' },
  { label: TWENTY_FOUR_HOURS, value: '24' }
];

const DEFAULT_HOURS = '2';

export default class AutomationControl extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    pauseButton: PAUSE_BUTTON,
    resumeButton: RESUME_BUTTON,
    pauseLength: PAUSE_LENGTH,
    pausedBanner: PAUSED_BANNER,
    readOnly: READ_ONLY,
    empty: EMPTY,
    runsOn: RUNS_ON,
    errorPrefix: ERROR_PREFIX,
    pausedPrefix: PAUSED_PREFIX,
    resumesItself: RESUMES_ITSELF,
    alwaysRuns: ALWAYS_RUNS
  };

  page;
  errorMessage;
  selectedHours = DEFAULT_HOURS;
  busy = false;
  wiredPageResult;

  @wire(getPage)
  wiredPage(result) {
    // The whole result is kept so that an action can refresh the cached wire rather than leaving
    // the page showing what the server said before the action.
    this.wiredPageResult = result;
    if (result.data) {
      this.page = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = this.messageFrom(result.error);
    }
  }

  get hourOptions() {
    return HOUR_OPTIONS;
  }

  get canManage() {
    return canManageSettings === true;
  }

  get isReadOnly() {
    return !this.canManage;
  }

  get isPaused() {
    return !!(this.page && this.page.paused);
  }

  get pausedUntil() {
    return this.page ? this.page.pausedUntil : undefined;
  }

  /** "Paused by Maria Lopez.", or nothing when the pause was not set from this page. */
  get pausedByText() {
    const name = this.page ? this.page.pausedBy : undefined;
    return name ? PAUSED_BY.replace('{0}', name) : undefined;
  }

  /**
   * The rows the list renders. Each carries its own disabled state, because an automation that
   * enforces a rule is never switchable, whoever is looking and whatever else is going on
   * (ADR-0024), and a template cannot work that out per row.
   */
  get automations() {
    const rows = this.page && this.page.automations ? this.page.automations : [];
    return rows.map((automation) => {
      return {
        ...automation,
        alwaysRuns: automation.alwaysRuns === true,
        toggleDisabled: this.controlsDisabled || automation.alwaysRuns === true
      };
    });
  }

  get hasAutomations() {
    return this.automations.length > 0;
  }

  get isEmpty() {
    return !!this.page && !this.hasAutomations;
  }

  get controlsDisabled() {
    return this.isReadOnly || this.busy;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  handleHoursChange(event) {
    this.selectedHours = event.detail.value;
  }

  handlePause() {
    this.runAction(pauseAll({ hours: parseInt(this.selectedHours, 10) }));
  }

  handleResume() {
    this.runAction(resumeAll());
  }

  handleToggle(event) {
    const automationName = event.target.dataset.automation;
    const row = this.automations.find((automation) => automation.automationName === automationName);
    if (row && row.alwaysRuns) {
      // The switch is disabled, so this is unreachable from a click; it is here so that a
      // change arriving any other way cannot send the server a request it is going to refuse.
      event.target.checked = false;
      return;
    }
    const enabled = event.target.checked;
    // The switch has already moved in the browser, so the row moves with it before the call. The
    // two have to agree first: LWC pushes a property to a child only when the value it rendered
    // last time has changed, so a revert from a row that never moved would change nothing and the
    // switch would sit in a position the server refused.
    const before = this.enabledFor(automationName);
    const input = event.target;
    this.setEnabledOn(automationName, enabled);
    this.runAction(setEnabled({ automationName, enabled }), () => {
      this.setEnabledOn(automationName, before);
      // The row is the truth the next render works from; the switch itself is put back here so
      // that it is right whichever order the render and the rejection happen in.
      input.checked = before;
    });
  }

  enabledFor(automationName) {
    const row = this.automations.find((automation) => automation.automationName === automationName);
    return row ? row.enabled : undefined;
  }

  /**
   * Replaces the one row that changed with a new object, so that the toggle is re-rendered.
   * Copying the page alone would keep the same row objects and the same values, and nothing
   * would be pushed to the switch.
   */
  setEnabledOn(automationName, enabled) {
    if (!this.page || !this.page.automations) {
      return;
    }
    this.page = {
      ...this.page,
      automations: this.page.automations.map((automation) => {
        return automation.automationName === automationName
          ? { ...automation, enabled }
          : automation;
      })
    };
  }

  runAction(promise, revert) {
    this.busy = true;
    this.errorMessage = undefined;
    return promise
      .then((page) => {
        this.page = page;
      })
      .catch((error) => {
        this.errorMessage = this.messageFrom(error);
        // A refused switch must not leave a toggle showing a change the server did not make.
        if (revert) {
          revert();
        }
      })
      .finally(() => {
        this.busy = false;
        this.refreshPage();
      });
  }

  refreshPage() {
    if (this.wiredPageResult) {
      return refreshApex(this.wiredPageResult);
    }
    return Promise.resolve();
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return UNEXPECTED_ERROR;
  }
}
