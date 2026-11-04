import { LightningElement, api } from 'lwc';
import getSetupChecks from '@salesforce/apex/SettingsController.getSetupChecks';
import { setupPath } from 'c/setupLinks';
import HEADING from '@salesforce/label/c.Core_SetupNote_Heading';
import OPEN_IN_SETUP from '@salesforce/label/c.Core_SetupNote_OpenInSetup';
import NEW_TAB from '@salesforce/label/c.Core_Kit_NewTab';
import CHECK_AGAIN from '@salesforce/label/c.Core_SuiteChoice_CheckAgain';
import SHOW_STEPS from '@salesforce/label/c.Core_SetupNote_ShowSteps';
import NOT_DONE from '@salesforce/label/c.Core_SetupNote_NotDone';
import METADATA_UNCONFIRMED from '@salesforce/label/c.Core_SetupNote_Metadata_Unconfirmed';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * What each Core section needs from Setup, by the section name the console shows. `link` names
 * a c/setupLinks key, the Setup page Open in Setup opens. `check` names a key of
 * SettingsController.getSetupChecks when BarnCRM can read the answer. Core sections only: a
 * module's notes go on the module's own settings page (ADR-0020).
 */
const NOTES = {
  general: [
    {
      key: 'metadata',
      get what() {
        return helpText('Core', 'Core_SetupNote_Metadata_What');
      },
      get why() {
        return helpText('Core', 'Core_SetupNote_Metadata_Why');
      },
      get steps() {
        return helpText('Core', 'Core_SetupNote_Metadata_Steps');
      },
      link: 'apexSettings',
      check: 'metadata',
      unconfirmed: METADATA_UNCONFIRMED
    }
  ],
  'duplicate matching': [
    {
      key: 'duplicates',
      get what() {
        return helpText('Core', 'Core_SetupNote_Duplicates_What');
      },
      get why() {
        return helpText('Core', 'Core_SetupNote_Duplicates_Why');
      },
      get steps() {
        return helpText('Core', 'Core_SetupNote_Duplicates_Steps');
      },
      link: 'duplicateRules'
    }
  ],
  rollups: [
    {
      key: 'rollupField',
      get what() {
        return helpText('Core', 'Core_SetupNote_RollupField_What');
      },
      get why() {
        return helpText('Core', 'Core_SetupNote_RollupField_Why');
      },
      get steps() {
        return helpText('Core', 'Core_SetupNote_RollupField_Steps');
      },
      link: 'objectManager'
    }
  ],
  'error log': [
    {
      key: 'emailDeliverability',
      get what() {
        return helpText('Core', 'Core_SetupNote_Email_What');
      },
      get why() {
        return helpText('Core', 'Core_SetupNote_Email_Why');
      },
      get steps() {
        return helpText('Core', 'Core_SetupNote_Email_Steps');
      },
      link: 'deliverability',
      check: 'emailDeliverability'
    }
  ],
  access: [
    {
      key: 'users',
      get what() {
        return helpText('Core', 'Core_SetupNote_Users_What');
      },
      get why() {
        return helpText('Core', 'Core_SetupNote_Users_Why');
      },
      get steps() {
        return helpText('Core', 'Core_SetupNote_Users_Steps');
      },
      link: 'permissionSets'
    }
  ]
};

/** A steps label holds the clicks separated by `|`; each becomes one numbered step. */
function splitSteps(steps) {
  return String(steps || '')
    .split('|')
    .map((step) => step.trim())
    .filter((step) => step);
}

/**
 * Two ways in. The console passes `section`, and the notes come from the Core list above. A
 * module's own settings page passes `notes` instead: a list of { key, what, why, steps, link,
 * met }, each text from the module's own labels, `steps` the clicks separated by `|`, `link` a
 * c/setupLinks key, and `met` true or false when the page can tell, or `check` naming a
 * SettingsController.getSetupChecks key (left out, the note is the instruction alone). `notes`,
 * when set, wins over `section`.
 *
 * A note whose prerequisite is met is not shown: the box says something needs a change in
 * Setup, and nothing does (owner QA, 2026-10-31). Not done shows a warning; unknown shows the
 * instruction, plus the note's `unconfirmed` text when it has one.
 */
export default class SettingsSetupNotes extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  labels = {
    heading: HEADING,
    openInSetup: OPEN_IN_SETUP,
    newTab: NEW_TAB,
    checkAgain: CHECK_AGAIN,
    showSteps: SHOW_STEPS
  };

  _notes;
  _section;
  checks = {};
  checksRequested = false;
  checking = false;

  @api
  get notes() {
    return this._notes;
  }

  set notes(value) {
    this._notes = value;
    this.loadChecksIfNeeded();
  }

  @api
  get section() {
    return this._section;
  }

  set section(value) {
    this._section = value;
    this.loadChecksIfNeeded();
  }

  get entries() {
    if (Array.isArray(this._notes)) {
      return this._notes;
    }
    return NOTES[String(this._section || '').toLowerCase()] || [];
  }

  get shownNotes() {
    return this.entries
      .map((entry) => ({ entry, met: entry.check ? this.checks[entry.check] : entry.met }))
      .filter(({ met }) => met !== true)
      .map(({ entry, met }) => {
        const notDone = met === false;
        const stepList = splitSteps(entry.steps);
        return {
          ...entry,
          stepList,
          hasSteps: stepList.length > 0,
          url: setupPath(entry.link),
          canCheckAgain: Boolean(entry.check),
          hasStatus: notDone,
          statusText: notDone ? NOT_DONE : HEADING,
          showUnconfirmed: !notDone && Boolean(entry.unconfirmed),
          iconName: notDone ? 'utility:warning' : 'utility:info',
          iconVariant: notDone ? 'warning' : undefined
        };
      });
  }

  loadChecksIfNeeded() {
    if (this.entries.some((entry) => entry.check)) {
      this.loadChecks();
    }
  }

  /** Asked once per page; Check Again asks again after the admin changes Setup. */
  async loadChecks() {
    if (this.checksRequested) {
      return;
    }
    this.checksRequested = true;
    await this.readChecks();
  }

  async readChecks() {
    this.checking = true;
    try {
      this.checks = (await getSetupChecks()) || {};
    } catch {
      // No answer is not a failure: each note still shows its instruction.
      this.checks = {};
    } finally {
      this.checking = false;
    }
  }

  handleCheckAgain() {
    return this.readChecks();
  }
}
