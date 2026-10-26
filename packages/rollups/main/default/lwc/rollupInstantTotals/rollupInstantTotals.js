import { LightningElement, api } from 'lwc';
import getStates from '@salesforce/apex/RollupInstantTotals.getStates';
import getState from '@salesforce/apex/RollupInstantTotals.getState';
import getCode from '@salesforce/apex/RollupInstantTotals.getCode';
import setTurnedOn from '@salesforce/apex/RollupInstantTotals.setTurnedOn';

import TITLE from '@salesforce/label/c.Core_RollupBuilder_InstantTitle';
import INTRO from '@salesforce/label/c.Core_RollupBuilder_InstantIntro';
import STATUS_BUILT_IN from '@salesforce/label/c.Core_RollupBuilder_InstantStatusBuiltIn';
import STATUS_ON from '@salesforce/label/c.Core_RollupBuilder_InstantStatusOn';
import STATUS_OFF from '@salesforce/label/c.Core_RollupBuilder_InstantStatusOff';
import STATUS_INACTIVE from '@salesforce/label/c.Core_RollupBuilder_InstantStatusInactive';
import STATUS_NOT_SET_UP from '@salesforce/label/c.Core_RollupBuilder_InstantStatusNotSetUp';
import STATUS_NOT_AVAILABLE from '@salesforce/label/c.Core_RollupBuilder_InstantStatusNotAvailable';
import COUNT_MANY from '@salesforce/label/c.Core_RollupBuilder_InstantCount';
import COUNT_ONE from '@salesforce/label/c.Core_RollupBuilder_InstantCountOne';
import COUNT_NONE from '@salesforce/label/c.Core_RollupBuilder_InstantCountNone';
import TURN_ON from '@salesforce/label/c.Core_RollupBuilder_InstantTurnOn';
import TURN_OFF from '@salesforce/label/c.Core_RollupBuilder_InstantTurnOff';
import REMOVE from '@salesforce/label/c.Core_RollupBuilder_InstantRemove';
import CLOSE from '@salesforce/label/c.Core_RollupBuilder_InstantClose';
import COPY from '@salesforce/label/c.Core_RollupBuilder_InstantCopy';
import COPIED from '@salesforce/label/c.Core_RollupBuilder_InstantCopied';
import COPY_FAILED from '@salesforce/label/c.Core_RollupBuilder_InstantCopyFailed';
import DOWNLOAD_DEPLOY from '@salesforce/label/c.Core_RollupBuilder_InstantDownloadDeploy';
import DOWNLOAD_REMOVAL from '@salesforce/label/c.Core_RollupBuilder_InstantDownloadRemoval';
import SETUP_TITLE from '@salesforce/label/c.Core_RollupBuilder_InstantSetupTitle';
import SETUP_STEP_1 from '@salesforce/label/c.Core_RollupBuilder_InstantSetupStep1';
import SETUP_STEP_2 from '@salesforce/label/c.Core_RollupBuilder_InstantSetupStep2';
import SETUP_STEP_3 from '@salesforce/label/c.Core_RollupBuilder_InstantSetupStep3';
import SETUP_STEP_4 from '@salesforce/label/c.Core_RollupBuilder_InstantSetupStep4';
import SETUP_STEP_5 from '@salesforce/label/c.Core_RollupBuilder_InstantSetupStep5';
import SETUP_CLI from '@salesforce/label/c.Core_RollupBuilder_InstantSetupCli';
import REMOVE_TITLE from '@salesforce/label/c.Core_RollupBuilder_InstantRemoveTitle';
import REMOVE_STEP_1 from '@salesforce/label/c.Core_RollupBuilder_InstantRemoveStep1';
import REMOVE_STEP_2 from '@salesforce/label/c.Core_RollupBuilder_InstantRemoveStep2';
import REMOVE_STEP_3 from '@salesforce/label/c.Core_RollupBuilder_InstantRemoveStep3';
import TRIGGER_HEADING from '@salesforce/label/c.Core_RollupBuilder_InstantTriggerHeading';
import TEST_HEADING from '@salesforce/label/c.Core_RollupBuilder_InstantTestHeading';
import TURNED_OFF from '@salesforce/label/c.Core_RollupBuilder_InstantTurnedOff';
import TURNED_ON from '@salesforce/label/c.Core_RollupBuilder_InstantTurnedOn';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Rollups_UnexpectedError';

/** The states `RollupInstantTotals` reports (ADR-0138). */
const STATUS_TEXT = {
  builtIn: STATUS_BUILT_IN,
  on: STATUS_ON,
  off: STATUS_OFF,
  inactive: STATUS_INACTIVE,
  notSetUp: STATUS_NOT_SET_UP,
  notAvailable: STATUS_NOT_AVAILABLE
};

const SETUP = 'setup';
const REMOVAL = 'removal';

function format(label, ...values) {
  return values.reduce((text, value, index) => text.split(`{${index}}`).join(value), label);
}

/**
 * Instant totals on objects BarnCRM ships no trigger for (canonical model R-R12, ADR-0138).
 *
 * On the Rollup Builder page it lists every object an instant rollup counts, and every object
 * that still has a generated trigger, with its state read from the org. In step 5 of the
 * wizard (`object-api-name` set) it shows the one object the rollup counts. "Turn on instant
 * totals" shows the generated trigger and test with the steps to add them (sandbox and change
 * set, or the downloaded package with the Salesforce CLI): BarnCRM deploys nothing itself.
 * "Turn off instant totals" flips the object's switch with no deploy; "Remove the trigger"
 * gives the removal package and steps.
 */
export default class RollupInstantTotals extends LightningElement {
  /** Whether the viewer may switch automation (Manage BarnCRM Settings). */
  @api canManage = false;

  labels = {
    title: TITLE,
    intro: INTRO,
    turnOn: TURN_ON,
    turnOff: TURN_OFF,
    remove: REMOVE,
    close: CLOSE,
    copy: COPY,
    downloadDeploy: DOWNLOAD_DEPLOY,
    downloadRemoval: DOWNLOAD_REMOVAL,
    triggerHeading: TRIGGER_HEADING,
    testHeading: TEST_HEADING,
    setupCli: SETUP_CLI
  };

  states = [];
  error;
  notice;
  busy = false;
  /** The object whose steps are open, which steps, and its generated code. */
  openObject;
  panel;
  code;

  _objectApiName;
  connected = false;

  /** Step 5: the object the rollup counts. Unset on the Builder page, which lists them all. */
  @api
  get objectApiName() {
    return this._objectApiName;
  }

  set objectApiName(value) {
    const changed = value !== this._objectApiName;
    this._objectApiName = value;
    if (this.connected && changed) {
      this.closePanel();
      this.load();
    }
  }

  connectedCallback() {
    this.connected = true;
    this.load();
  }

  /** Reads the state again, for example after a rollup is saved. */
  @api
  load() {
    this.error = undefined;
    if (this.single && !this.objectApiName) {
      this.states = [];
      return Promise.resolve();
    }
    const request = this.objectApiName
      ? getState({ objectApiName: this.objectApiName }).then((state) => [state])
      : getStates();
    return request
      .then((states) => {
        this.states = (states || []).filter((state) => Boolean(state));
      })
      .catch((error) => {
        this.error = this.messageFrom(error);
      });
  }

  get single() {
    return this._objectApiName !== undefined;
  }

  get shown() {
    return this.rows.length > 0 || Boolean(this.error);
  }

  get showIntro() {
    return !this.single;
  }

  get rows() {
    return this.states
      .filter((state) => !(this.single && state.status === 'builtIn'))
      .map((state) => {
        const open = state.objectApiName === this.openObject;
        return {
          key: state.objectApiName,
          objectApiName: state.objectApiName,
          label: state.objectLabel,
          statusText: format(STATUS_TEXT[state.status] || '', state.triggerName),
          countText: this.single ? undefined : this.countText(state.instantRollups),
          showTurnOn: state.status === 'notSetUp' || (state.status === 'off' && this.canManage),
          showTurnOff: state.status === 'on' && this.canManage,
          showRemove: ['on', 'off', 'inactive'].includes(state.status),
          status: state.status,
          showSetup: open && this.panel === SETUP && Boolean(this.code),
          showRemoval: open && this.panel === REMOVAL && Boolean(this.code)
        };
      });
  }

  countText(count) {
    if (!count) {
      return COUNT_NONE;
    }
    return count === 1 ? COUNT_ONE : format(COUNT_MANY, count);
  }

  // --------------------------------------------------------------------------------- actions

  handleTurnOn(event) {
    const objectApiName = event.target.dataset.object;
    const state = this.states.find((entry) => entry.objectApiName === objectApiName);
    if (state && state.status === 'off') {
      this.switchTo(objectApiName, true);
      return;
    }
    this.openPanel(objectApiName, SETUP);
  }

  handleTurnOff(event) {
    this.switchTo(event.target.dataset.object, false);
  }

  handleRemove(event) {
    this.openPanel(event.target.dataset.object, REMOVAL);
  }

  handleClose() {
    this.closePanel();
  }

  openPanel(objectApiName, panel) {
    this.error = undefined;
    this.notice = undefined;
    this.busy = true;
    return getCode({ objectApiName })
      .then((code) => {
        this.code = code;
        this.openObject = objectApiName;
        this.panel = panel;
      })
      .catch((error) => {
        this.error = this.messageFrom(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  closePanel() {
    this.openObject = undefined;
    this.panel = undefined;
    this.code = undefined;
  }

  switchTo(objectApiName, turnedOn) {
    this.error = undefined;
    this.notice = undefined;
    this.busy = true;
    return setTurnedOn({ objectApiName, turnedOn })
      .then((state) => {
        this.states = this.states.map((entry) => {
          return entry.objectApiName === state.objectApiName ? state : entry;
        });
        this.notice = format(turnedOn ? TURNED_ON : TURNED_OFF, state.objectLabel);
      })
      .catch((error) => {
        this.error = this.messageFrom(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  handleCopy(event) {
    const text =
      event.target.dataset.part === 'test' ? this.code.testSource : this.code.triggerSource;
    this.notice = undefined;
    const clipboard = typeof navigator !== 'undefined' ? navigator.clipboard : undefined;
    if (!clipboard || !clipboard.writeText) {
      this.notice = COPY_FAILED;
      return Promise.resolve();
    }
    return clipboard
      .writeText(text)
      .then(() => {
        this.notice = COPIED;
      })
      .catch(() => {
        this.notice = COPY_FAILED;
      });
  }

  // ----------------------------------------------------------------------- the open panel

  get openLabel() {
    const state = this.states.find((entry) => entry.objectApiName === this.openObject);
    return state ? state.objectLabel : this.openObject;
  }

  get setupTitle() {
    return format(SETUP_TITLE, this.openLabel);
  }

  get removeTitle() {
    return format(REMOVE_TITLE, this.openLabel);
  }

  get setupSteps() {
    const code = this.code;
    return [
      format(SETUP_STEP_1, code.triggerName, this.openObject),
      format(SETUP_STEP_2, code.testClassName),
      format(SETUP_STEP_3, code.triggerName, code.testClassName),
      format(SETUP_STEP_4, code.testClassName),
      SETUP_STEP_5
    ].map((text, index) => ({ key: `setup-${index}`, text }));
  }

  get removeSteps() {
    const code = this.code;
    return [
      REMOVE_STEP_1,
      format(REMOVE_STEP_2, code.triggerName, code.testClassName),
      REMOVE_STEP_3
    ].map((text, index) => ({ key: `remove-${index}`, text }));
  }

  get deployFileName() {
    return `${this.code.triggerName}.zip`;
  }

  get removalFileName() {
    return `${this.code.triggerName}_Removal.zip`;
  }

  get deployHref() {
    return `data:application/zip;base64,${this.code.deployPackage}`;
  }

  get removalHref() {
    return `data:application/zip;base64,${this.code.removalPackage}`;
  }

  /** The Salesforce CLI command that deploys the downloaded package, running only its test. */
  get deployCommand() {
    return (
      `sf project deploy start --metadata-dir ${this.deployFileName} --single-package ` +
      `--test-level RunSpecifiedTests --tests ${this.code.testClassName} --target-org your-org`
    );
  }

  /** Production runs its local tests for any Apex change, a delete included. */
  get removalCommand() {
    return (
      `sf project deploy start --metadata-dir ${this.removalFileName} --single-package ` +
      '--test-level RunLocalTests --target-org your-org'
    );
  }

  messageFrom(error) {
    return error && error.body && error.body.message ? error.body.message : UNEXPECTED_ERROR;
  }
}
