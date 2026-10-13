import { LightningElement, api } from 'lwc';
import getSetupChecks from '@salesforce/apex/SettingsController.getSetupChecks';
import HEADING from '@salesforce/label/c.Core_SetupNote_Heading';
import WHERE from '@salesforce/label/c.Core_SetupNote_Where';
import DONE from '@salesforce/label/c.Core_SetupNote_Done';
import NOT_DONE from '@salesforce/label/c.Core_SetupNote_NotDone';
import FISCAL_WHAT from '@salesforce/label/c.Core_SetupNote_FiscalYear_What';
import FISCAL_WHY from '@salesforce/label/c.Core_SetupNote_FiscalYear_Why';
import FISCAL_WHERE from '@salesforce/label/c.Core_SetupNote_FiscalYear_Where';
import METADATA_WHAT from '@salesforce/label/c.Core_SetupNote_Metadata_What';
import METADATA_WHY from '@salesforce/label/c.Core_SetupNote_Metadata_Why';
import METADATA_WHERE from '@salesforce/label/c.Core_SetupNote_Metadata_Where';
import DUPLICATES_WHAT from '@salesforce/label/c.Core_SetupNote_Duplicates_What';
import DUPLICATES_WHY from '@salesforce/label/c.Core_SetupNote_Duplicates_Why';
import DUPLICATES_WHERE from '@salesforce/label/c.Core_SetupNote_Duplicates_Where';
import ROLLUP_WHAT from '@salesforce/label/c.Core_SetupNote_RollupField_What';
import ROLLUP_WHY from '@salesforce/label/c.Core_SetupNote_RollupField_Why';
import ROLLUP_WHERE from '@salesforce/label/c.Core_SetupNote_RollupField_Where';
import EMAIL_WHAT from '@salesforce/label/c.Core_SetupNote_Email_What';
import EMAIL_WHY from '@salesforce/label/c.Core_SetupNote_Email_Why';
import EMAIL_WHERE from '@salesforce/label/c.Core_SetupNote_Email_Where';
import USERS_WHAT from '@salesforce/label/c.Core_SetupNote_Users_What';
import USERS_WHY from '@salesforce/label/c.Core_SetupNote_Users_Why';
import USERS_WHERE from '@salesforce/label/c.Core_SetupNote_Users_Where';
import BULK_WHAT from '@salesforce/label/c.Core_SetupNote_Bulk_What';
import BULK_WHY from '@salesforce/label/c.Core_SetupNote_Bulk_Why';
import BULK_WHERE from '@salesforce/label/c.Core_SetupNote_Bulk_Where';

/**
 * What each Core section needs from Setup, by the section name the console shows. `check`
 * names a key of SettingsController.getSetupChecks when BarnCRM can read the answer. Core
 * sections only: a module's notes go on the module's own settings page (ADR-0020).
 */
const NOTES = {
  general: [
    {
      key: 'fiscalYear',
      what: FISCAL_WHAT,
      why: FISCAL_WHY,
      where: FISCAL_WHERE,
      check: 'fiscalYear'
    },
    { key: 'metadata', what: METADATA_WHAT, why: METADATA_WHY, where: METADATA_WHERE }
  ],
  households: [
    { key: 'duplicates', what: DUPLICATES_WHAT, why: DUPLICATES_WHY, where: DUPLICATES_WHERE }
  ],
  rollups: [{ key: 'rollupField', what: ROLLUP_WHAT, why: ROLLUP_WHY, where: ROLLUP_WHERE }],
  'error log': [
    {
      key: 'emailDeliverability',
      what: EMAIL_WHAT,
      why: EMAIL_WHY,
      where: EMAIL_WHERE,
      check: 'emailDeliverability'
    }
  ],
  access: [{ key: 'users', what: USERS_WHAT, why: USERS_WHY, where: USERS_WHERE }],
  import: [{ key: 'bulk', what: BULK_WHAT, why: BULK_WHY, where: BULK_WHERE }]
};

export default class SettingsSetupNotes extends LightningElement {
  labels = { heading: HEADING, where: WHERE };

  _section;
  checks = {};
  checksRequested = false;

  @api
  get section() {
    return this._section;
  }

  set section(value) {
    this._section = value;
    if (this.entries.some((entry) => entry.check)) {
      this.loadChecks();
    }
  }

  get entries() {
    return NOTES[String(this._section || '').toLowerCase()] || [];
  }

  get notes() {
    return this.entries.map((entry) => {
      const met = entry.check ? this.checks[entry.check] : undefined;
      const hasStatus = met === true || met === false;
      let iconName = 'utility:info';
      let iconVariant;
      if (hasStatus) {
        iconName = met ? 'utility:success' : 'utility:warning';
        iconVariant = met ? 'success' : 'warning';
      }
      return {
        ...entry,
        hasStatus,
        statusText: hasStatus ? (met ? DONE : NOT_DONE) : HEADING,
        iconName,
        iconVariant
      };
    });
  }

  /** Asked once per page: the answers change only when someone changes Setup and reloads. */
  async loadChecks() {
    if (this.checksRequested) {
      return;
    }
    this.checksRequested = true;
    try {
      this.checks = (await getSetupChecks()) || {};
    } catch {
      // No answer is not a failure: each note still shows its instruction.
      this.checks = {};
    }
  }
}
