import { LightningElement } from 'lwc';
import getSettings from '@salesforce/apex/ProgramsSettingsController.getSettings';
import savePrivacy from '@salesforce/apex/ProgramsSettingsController.savePrivacy';

import TITLE from '@salesforce/label/c.Programs_Settings_Title';
import PICKLISTS_TITLE from '@salesforce/label/c.Programs_Settings_PicklistsTitle';
import DEFAULT_VALUE from '@salesforce/label/c.Programs_Settings_Default';
import CHANGE_IN_SETUP from '@salesforce/label/c.Programs_Settings_ChangeInSetup';
import CHANGE_FOR from '@salesforce/label/c.Programs_Settings_ChangeFor';
import PRIVACY_TITLE from '@salesforce/label/c.Programs_Settings_PrivacyTitle';
import PRIVACY_LEGEND from '@salesforce/label/c.Programs_Settings_PrivacyLegend';
import PRIVACY_SHARED from '@salesforce/label/c.Programs_Settings_PrivacyShared';
import PRIVACY_PRIVATE from '@salesforce/label/c.Programs_Settings_PrivacyPrivate';
import PRIVACY_DEFAULT from '@salesforce/label/c.Programs_Settings_PrivacyDefault';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

import { PRIVATE, picklistRows, privacyOptions, storedPrivacy } from './settingsRows';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';
import { bodyMessage as messageOf } from 'c/findCsv';

/**
 * The Programs module's settings page, reached from the Programs section of BarnCRM Settings:
 * the intake and eligibility picklists (P-07) with a link to change their choices in Setup, and
 * the Participant Privacy preset (P-08).
 */
export default class ProgramsSettings extends LightningElement {
  helpReady = isHelpLoaded('Programs');

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Programs', 'Programs_Settings_Intro');
    },
    picklistsTitle: PICKLISTS_TITLE,
    get picklistsIntro() {
      return helpText('Programs', 'Programs_Settings_PicklistsIntro');
    },
    changeInSetup: CHANGE_IN_SETUP,
    get noAccess() {
      return helpText('Programs', 'Programs_Settings_NoAccess');
    },
    loading: LOADING,
    privacyTitle: PRIVACY_TITLE,
    get privacyIntro() {
      return helpText('Programs', 'Programs_Settings_PrivacyIntro');
    },
    privacyLegend: PRIVACY_LEGEND,
    privacyDefault: PRIVACY_DEFAULT
  };

  icons = { settings: iconFor('Programs_Settings') };

  privacyOptions = privacyOptions({ shared: PRIVACY_SHARED, private: PRIVACY_PRIVATE });

  settings;
  chosenPrivacy;
  loading = true;
  saving = false;
  errorMessage;
  savedMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Programs').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  load() {
    this.loading = true;
    return getSettings()
      .then((settings) => {
        this.show(settings);
      })
      .catch((error) => {
        this.errorMessage = messageOf(error, helpText('Programs', 'Programs_Fail_SettingsLoad'));
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

  /** One unsaved change while the chosen preset differs from the stored one; the save bar shows. */
  get dirtyCount() {
    return this.settings && this.chosenPrivacy !== storedPrivacy(this.settings) ? 1 : 0;
  }

  handlePrivacyChange(event) {
    this.chosenPrivacy = event.detail.value;
    this.savedMessage = undefined;
  }

  handleDiscard() {
    this.chosenPrivacy = storedPrivacy(this.settings);
    this.errorMessage = undefined;
  }

  handleSavePrivacy() {
    this.saving = true;
    this.errorMessage = undefined;
    this.savedMessage = undefined;
    return savePrivacy({ privateParticipants: this.chosenPrivacy === PRIVATE })
      .then((settings) => {
        this.show(settings);
        this.savedMessage = helpText('Programs', 'Programs_Settings_Saved');
      })
      .catch((error) => {
        this.errorMessage = messageOf(error, helpText('Programs', 'Programs_Fail_SettingsSave'));
      })
      .finally(() => {
        this.saving = false;
      });
  }
}
