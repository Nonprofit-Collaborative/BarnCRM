import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
// Bare, and correctly so: a custom permission defined in the same package resolves without a
// namespace prefix, so this is not the B5 problem that TriggerHandler.getName had.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import getPage from '@salesforce/apex/AutomationControlController.getPage';
import pauseAll from '@salesforce/apex/AutomationControlController.pauseAll';
import resumeAll from '@salesforce/apex/AutomationControlController.resumeAll';
import setEnabled from '@salesforce/apex/AutomationControlController.setEnabled';
import saveControl from '@salesforce/apex/AutomationControlController.saveControl';
import addControl from '@salesforce/apex/AutomationControlController.addControl';
import removeControl from '@salesforce/apex/AutomationControlController.removeControl';
import addFlow from '@salesforce/apex/AutomationControlController.addFlow';
import removeFlow from '@salesforce/apex/AutomationControlController.removeFlow';
import catchUpNow from '@salesforce/apex/AutomationControlController.catchUpNow';

import TITLE from '@salesforce/label/c.Core_AutomationControl_Title';
import PAUSE_BUTTON from '@salesforce/label/c.Core_AutomationControl_PauseButton';
import RESUME_BUTTON from '@salesforce/label/c.Core_AutomationControl_ResumeButton';
import PAUSE_LENGTH from '@salesforce/label/c.Core_AutomationControl_PauseLength';
import PAUSED_BANNER from '@salesforce/label/c.Core_AutomationControl_PausedBanner';
import READ_ONLY from '@salesforce/label/c.Core_AutomationControl_ReadOnly';
import RUNS_ON from '@salesforce/label/c.Core_AutomationControl_RunsOn';
import ONE_HOUR from '@salesforce/label/c.Core_AutomationControl_OneHour';
import TWO_HOURS from '@salesforce/label/c.Core_AutomationControl_TwoHours';
import FOUR_HOURS from '@salesforce/label/c.Core_AutomationControl_FourHours';
import EIGHT_HOURS from '@salesforce/label/c.Core_AutomationControl_EightHours';
import TWENTY_FOUR_HOURS from '@salesforce/label/c.Core_AutomationControl_TwentyFourHours';
import ERROR_PREFIX from '@salesforce/label/c.Core_AutomationControl_ErrorPrefix';
import PAUSED_PREFIX from '@salesforce/label/c.Core_AutomationControl_PausedPrefix';
import PAUSED_BY from '@salesforce/label/c.Core_AutomationControl_PausedBy';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Automation_UnexpectedError';
import ALWAYS_RUNS from '@salesforce/label/c.Core_Automation_AlwaysRuns';
import PEOPLE_TITLE from '@salesforce/label/c.Core_AutomationControl_PeopleTitle';
import FLOWS_TITLE from '@salesforce/label/c.Core_AutomationControl_FlowsTitle';
import CATCH_UP_BUTTON from '@salesforce/label/c.Core_AutomationControl_CatchUpButton';
import WHOLE_ORGANIZATION from '@salesforce/label/c.Core_AutomationControl_WholeOrganization';
import KIND_USER from '@salesforce/label/c.Core_AutomationControl_KindUser';
import ADD_FOR from '@salesforce/label/c.Core_AutomationControl_AddFor';
import KIND_PROFILE from '@salesforce/label/c.Core_AccessExplorer_KindProfile';
import KIND_ORGANIZATION from '@salesforce/label/c.Core_Settings_NavGroup_Organization';
import ADD from '@salesforce/label/c.Core_CmdtManager_AddButton';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import NAME from '@salesforce/label/c.Core_CmdtManager_NameField';
import TYPE from '@salesforce/label/c.Core_DataDictionary_ColType';
import FLOW from '@salesforce/label/c.Core_DataDictionary_TypeFlow';
import TURN_OFF from '@salesforce/label/c.Core_ModuleManager_TurnOffButton';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const HOUR_OPTIONS = [
  { label: ONE_HOUR, value: '1' },
  { label: TWO_HOURS, value: '2' },
  { label: FOUR_HOURS, value: '4' },
  { label: EIGHT_HOURS, value: '8' },
  { label: TWENTY_FOUR_HOURS, value: '24' }
];

const LEVEL_ORGANIZATION = 'Organization';
const LEVEL_PROFILE = 'Profile';
const LEVEL_USER = 'User';
const LEVEL_LABELS = {
  [LEVEL_ORGANIZATION]: KIND_ORGANIZATION,
  [LEVEL_PROFILE]: KIND_PROFILE,
  [LEVEL_USER]: KIND_USER
};

const DEFAULT_HOURS = '2';
/** How long the "is off" line stays beside a switch just turned off (admin-12). */
const STATUS_LINE_MS = 6000;

export default class AutomationControl extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Core', 'Core_AutomationControl_Intro');
    },
    pauseButton: PAUSE_BUTTON,
    resumeButton: RESUME_BUTTON,
    pauseLength: PAUSE_LENGTH,
    pausedBanner: PAUSED_BANNER,
    readOnly: READ_ONLY,
    get empty() {
      return helpText('Core', 'Core_AutomationControl_Empty');
    },
    runsOn: RUNS_ON,
    errorPrefix: ERROR_PREFIX,
    pausedPrefix: PAUSED_PREFIX,
    get resumesItself() {
      return helpText('Core', 'Core_AutomationControl_ResumesItself');
    },
    alwaysRuns: ALWAYS_RUNS,
    peopleTitle: PEOPLE_TITLE,
    flowsTitle: FLOWS_TITLE,
    catchUpButton: CATCH_UP_BUTTON,
    addFor: ADD_FOR,
    profile: KIND_PROFILE,
    user: KIND_USER,
    add: ADD,
    remove: REMOVE,
    name: NAME,
    type: TYPE,
    flow: FLOW,
    get peopleHelp() {
      return helpText('Core', 'Core_AutomationControl_PeopleHelp');
    },
    get flowsHelp() {
      return helpText('Core', 'Core_AutomationControl_FlowsHelp');
    },
    get catchUpHelp() {
      return helpText('Core', 'Core_AutomationControl_CatchUpHelp');
    },
    get noFlowsToAdd() {
      return helpText('Core', 'Core_AutomationControl_NoFlowsToAdd');
    },
    get pausedForEveryone() {
      return helpText('Core', 'Core_AutomationControl_PausedForEveryone');
    }
  };

  /** Profile or User: which picker adds the next row. */
  addKind = LEVEL_USER;
  addOwnerId;
  flowToAdd;
  /** Shown after Catch Up Now starts. */
  catchUpMessage;

  page;
  errorMessage;
  selectedHours = DEFAULT_HOURS;
  busy = false;
  wiredPageResult;
  /** The automation just switched off, whose row says so for a few seconds. */
  switchedOff;
  statusTimer;

  disconnectedCallback() {
    clearTimeout(this.statusTimer);
  }

  @wire(getPage)
  wiredPage(result) {
    // The whole result is kept so that an action can refresh the cached wire rather than leaving
    // the page showing what the server said before the action.
    this.wiredPageResult = result;
    if (result.data) {
      this.page = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = bodyMessage(result.error, UNEXPECTED_ERROR);
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
        toggleDisabled: this.controlsDisabled || automation.alwaysRuns === true,
        removable: automation.removable === true,
        removeTitle: `${REMOVE}: ${automation.label}`,
        statusLine:
          this.switchedOff === automation.automationName
            ? helpText('Core', 'Core_AutomationControl_SwitchedOff', automation.label)
            : ''
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

  // ---------------------------------------------- BarnCRM Automation Control rows (R-A8)

  get pauseAllLabel() {
    return this.page ? this.page.pauseAllLabel : undefined;
  }

  get bypassLabel() {
    return this.page ? this.page.bypassLabel : undefined;
  }

  /** The org default first (named Whole Organization), then profiles and users. */
  get controlRows() {
    const rows = (this.page && this.page.controlRows) || [];
    return rows.map((row) => {
      const name = row.level === LEVEL_ORGANIZATION ? WHOLE_ORGANIZATION : row.ownerName;
      return {
        ...row,
        name,
        typeLabel: LEVEL_LABELS[row.level] || row.level,
        removable: row.level !== LEVEL_ORGANIZATION,
        pauseAllTitle: `${this.pauseAllLabel}: ${name}`,
        bypassTitle: `${this.bypassLabel}: ${name}`,
        removeTitle: `${REMOVE}: ${name}`
      };
    });
  }

  get pausedForEveryone() {
    return !!(this.page && this.page.pausedForEveryone);
  }

  /** Turn Off in the Pause All bar, offered only to someone who can use it. */
  get turnOffLabel() {
    return this.isReadOnly ? undefined : TURN_OFF;
  }

  get kindOptions() {
    return [
      { label: KIND_PROFILE, value: LEVEL_PROFILE },
      { label: KIND_USER, value: LEVEL_USER }
    ];
  }

  get addingProfile() {
    return this.addKind === LEVEL_PROFILE;
  }

  get profileOptions() {
    return (this.page && this.page.profileOptions) || [];
  }

  get addControlDisabled() {
    return this.controlsDisabled || !this.addOwnerId;
  }

  get flowOptions() {
    return (this.page && this.page.flowOptions) || [];
  }

  get hasFlowOptions() {
    return this.flowOptions.length > 0;
  }

  get addFlowDisabled() {
    return this.controlsDisabled || !this.flowToAdd;
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
    this.showSwitchStatus(undefined);
    this.runAction(
      setEnabled({ automationName, enabled }),
      () => {
        this.setEnabledOn(automationName, before);
        // The row is the truth the next render works from; the switch itself is put back here
        // so that it is right whichever order the render and the rejection happen in.
        input.checked = before;
      },
      () => {
        if (!enabled) {
          this.showSwitchStatus(automationName);
        }
      }
    );
  }

  /** One box of an Automation Control row saves at once; a refused save puts the box back. */
  handleControlChange(event) {
    const input = event.target;
    const ownerId = input.dataset.owner;
    const row = this.controlRows.find((candidate) => candidate.ownerId === ownerId);
    if (!row) {
      return;
    }
    const pause = input.dataset.field === 'pauseAll' ? input.checked : row.pauseAll;
    const bypass = input.dataset.field === 'bypass' ? input.checked : row.bypass;
    const before = !input.checked;
    this.runAction(saveControl({ ownerId, pauseAll: pause, bypass }), () => {
      input.checked = before;
    });
  }

  /** Turn Off in the Pause All bar: the Whole Organization row loses Pause All. */
  handleTurnOffPauseAll() {
    const org = this.controlRows.find((row) => row.level === LEVEL_ORGANIZATION);
    if (!org) {
      return;
    }
    this.runAction(saveControl({ ownerId: org.ownerId, pauseAll: false, bypass: org.bypass }));
  }

  handleRemoveControl(event) {
    this.runAction(removeControl({ ownerId: event.target.dataset.owner }));
  }

  handleAddKind(event) {
    this.addKind = event.detail.value;
    this.addOwnerId = undefined;
  }

  handleAddOwner(event) {
    this.addOwnerId = event.detail.value;
  }

  handleUserPicked(event) {
    this.addOwnerId = event.detail ? event.detail.recordId : undefined;
  }

  handleAddControl() {
    const ownerId = this.addOwnerId;
    this.runAction(addControl({ ownerId }), undefined, () => {
      this.addOwnerId = undefined;
      const picker = this.template.querySelector('[data-id="add-user"]');
      if (picker && typeof picker.clearSelection === 'function') {
        picker.clearSelection();
      }
    });
  }

  handleFlowChoice(event) {
    this.flowToAdd = event.detail.value;
  }

  handleAddFlow() {
    const apiName = this.flowToAdd;
    this.runAction(addFlow({ apiName }), undefined, () => {
      this.flowToAdd = undefined;
    });
  }

  handleRemoveFlow(event) {
    this.runAction(removeFlow({ automationName: event.target.dataset.automation }));
  }

  handleCatchUp() {
    this.catchUpMessage = undefined;
    this.runAction(catchUpNow(), undefined, () => {
      this.catchUpMessage = helpText('Core', 'Core_AutomationControl_CatchUpStarted');
    });
  }

  /**
   * Shows "X is off. Turn it back on here." beside the switch just turned off, announced by its
   * live region, and clears it after a few seconds (admin-12).
   */
  showSwitchStatus(automationName) {
    clearTimeout(this.statusTimer);
    this.switchedOff = automationName;
    if (automationName) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.statusTimer = setTimeout(() => {
        this.switchedOff = undefined;
      }, STATUS_LINE_MS);
    }
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

  runAction(promise, revert, onSuccess) {
    this.busy = true;
    this.errorMessage = undefined;
    return promise
      .then((page) => {
        this.page = page;
        if (onSuccess) {
          onSuccess();
        }
      })
      .catch((error) => {
        this.errorMessage = bodyMessage(error, UNEXPECTED_ERROR);
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
}
