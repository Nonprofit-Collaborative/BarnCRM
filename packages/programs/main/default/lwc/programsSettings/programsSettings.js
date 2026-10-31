import { LightningElement } from 'lwc';
import getSettings from '@salesforce/apex/ProgramsSettingsController.getSettings';

import TITLE from '@salesforce/label/c.Programs_Settings_Title';
import INTRO from '@salesforce/label/c.Programs_Settings_Intro';
import PICKLISTS_TITLE from '@salesforce/label/c.Programs_Settings_PicklistsTitle';
import PICKLISTS_INTRO from '@salesforce/label/c.Programs_Settings_PicklistsIntro';
import DEFAULT_VALUE from '@salesforce/label/c.Programs_Settings_Default';
import CHANGE_IN_SETUP from '@salesforce/label/c.Programs_Settings_ChangeInSetup';
import CHANGE_FOR from '@salesforce/label/c.Programs_Settings_ChangeFor';
import NO_ACCESS from '@salesforce/label/c.Programs_Settings_NoAccess';
import LOAD_FAILED from '@salesforce/label/c.Programs_Settings_LoadFailed';
import LOADING from '@salesforce/label/c.Programs_Loading';

import { picklistRows } from './settingsRows';

/**
 * The Programs module's settings page, reached from the Programs section of BarnCRM Settings:
 * the intake and eligibility picklists (P-07) with a link to change their choices in Setup.
 */
export default class ProgramsSettings extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    picklistsTitle: PICKLISTS_TITLE,
    picklistsIntro: PICKLISTS_INTRO,
    changeInSetup: CHANGE_IN_SETUP,
    noAccess: NO_ACCESS,
    loading: LOADING
  };

  settings;
  loading = true;
  errorMessage;

  connectedCallback() {
    this.load();
  }

  load() {
    this.loading = true;
    return getSettings()
      .then((settings) => {
        this.settings = settings;
      })
      .catch((error) => {
        this.errorMessage =
          error && error.body && error.body.message ? error.body.message : LOAD_FAILED;
      })
      .finally(() => {
        this.loading = false;
      });
  }

  get canManage() {
    return !!(this.settings && this.settings.canManage);
  }

  get noAccess() {
    return !!this.settings && !this.settings.canManage;
  }

  get picklists() {
    return picklistRows(this.settings, { defaultValue: DEFAULT_VALUE, changeFor: CHANGE_FOR });
  }
}
