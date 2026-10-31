import { LightningElement } from 'lwc';
import getSettings from '@salesforce/apex/ProgramsSettingsController.getSettings';
import savePrivacy from '@salesforce/apex/ProgramsSettingsController.savePrivacy';

import TITLE from '@salesforce/label/c.Programs_Settings_Title';
import INTRO from '@salesforce/label/c.Programs_Settings_Intro';
import PICKLISTS_TITLE from '@salesforce/label/c.Programs_Settings_PicklistsTitle';
import PICKLISTS_INTRO from '@salesforce/label/c.Programs_Settings_PicklistsIntro';
import DEFAULT_VALUE from '@salesforce/label/c.Programs_Settings_Default';
import CHANGE_IN_SETUP from '@salesforce/label/c.Programs_Settings_ChangeInSetup';
import CHANGE_FOR from '@salesforce/label/c.Programs_Settings_ChangeFor';
import NO_ACCESS from '@salesforce/label/c.Programs_Settings_NoAccess';
import LOAD_FAILED from '@salesforce/label/c.Programs_Settings_LoadFailed';
import PRIVACY_TITLE from '@salesforce/label/c.Programs_Settings_PrivacyTitle';
import PRIVACY_INTRO from '@salesforce/label/c.Programs_Settings_PrivacyIntro';
import PRIVACY_LEGEND from '@salesforce/label/c.Programs_Settings_PrivacyLegend';
import PRIVACY_SHARED from '@salesforce/label/c.Programs_Settings_PrivacyShared';
import PRIVACY_PRIVATE from '@salesforce/label/c.Programs_Settings_PrivacyPrivate';
import PRIVACY_DEFAULT from '@salesforce/label/c.Programs_Settings_PrivacyDefault';
import SAVE from '@salesforce/label/c.Programs_Settings_Save';
import SAVED from '@salesforce/label/c.Programs_Settings_Saved';
import SAVE_FAILED from '@salesforce/label/c.Programs_Settings_SaveFailed';
import LOADING from '@salesforce/label/c.Programs_Loading';

import { PRIVATE, picklistRows, privacyOptions, storedPrivacy } from './settingsRows';

/**
 * The Programs module's settings page, reached from the Programs section of BarnCRM Settings:
 * the intake and eligibility picklists (P-07) with a link to change their choices in Setup, and
 * the Participant Privacy preset (P-08).
 */
export default class ProgramsSettings extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    picklistsTitle: PICKLISTS_TITLE,
    picklistsIntro: PICKLISTS_INTRO,
    changeInSetup: CHANGE_IN_SETUP,
    noAccess: NO_ACCESS,
    loading: LOADING,
    privacyTitle: PRIVACY_TITLE,
    privacyIntro: PRIVACY_INTRO,
    privacyLegend: PRIVACY_LEGEND,
    privacyDefault: PRIVACY_DEFAULT,
    save: SAVE
  };

  privacyOptions = privacyOptions({ shared: PRIVACY_SHARED, private: PRIVACY_PRIVATE });

  settings;
  chosenPrivacy;
  loading = true;
  saving = false;
  errorMessage;
  savedMessage;

  connectedCallback() {
    this.load();
  }

  load() {
    this.loading = true;
    return getSettings()
      .then((settings) => {
        this.show(settings);
      })
      .catch((error) => {
        this.errorMessage = messageOf(error, LOAD_FAILED);
      })
      .finally(() => {
        this.loading = false;
      });
  }

  show(settings) {
    this.settings = settings;
    this.chosenPrivacy = storedPrivacy(settings);
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

  get saveDisabled() {
    return this.saving || this.chosenPrivacy === storedPrivacy(this.settings);
  }

  handlePrivacyChange(event) {
    this.chosenPrivacy = event.detail.value;
    this.savedMessage = undefined;
  }

  handleSavePrivacy() {
    this.saving = true;
    this.errorMessage = undefined;
    this.savedMessage = undefined;
    return savePrivacy({ privateParticipants: this.chosenPrivacy === PRIVATE })
      .then((settings) => {
        this.show(settings);
        this.savedMessage = SAVED;
      })
      .catch((error) => {
        this.errorMessage = messageOf(error, SAVE_FAILED);
      })
      .finally(() => {
        this.saving = false;
      });
  }
}

function messageOf(error, fallback) {
  return error && error.body && error.body.message ? error.body.message : fallback;
}
