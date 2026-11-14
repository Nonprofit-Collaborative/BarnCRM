import { LightningElement, api } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import getFeatures from '@salesforce/apex/FeatureController.getFeatures';
import turnOn from '@salesforce/apex/FeatureController.turnOn';
import { messageFrom as messageOf } from 'c/findCsv';
import TURN_ON from '@salesforce/label/c.Core_Feature_TurnOn';
import ON from '@salesforce/label/c.Core_Feature_On';
import OFF from '@salesforce/label/c.Core_Feature_Off';
import CONFIRM_TITLE from '@salesforce/label/c.Core_Feature_ConfirmTitle';
import CANCEL from '@salesforce/label/c.Core_CmdtManager_CancelButton';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * BarnCRM Settings, General, Features (ADR-0124): each Core feature with its description and
 * state. A feature that is off has a Turn on button behind a confirmation; turning on is
 * one-way, which the warning above the list says, so a feature that is on has no control.
 */
export default class FeatureSettings extends LightningElement {
  helpReady = isHelpLoaded('Core');

  labels = {
    get warning() {
      return helpText('Core', 'Core_Feature_OneWayWarning');
    },
    turnOn: TURN_ON
  };

  features = [];
  canEdit = false;
  loaded = false;
  busyKey;
  errorMessage;
  savedMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  /** The console calls this after first-run setup finishes, because this row stays mounted. */
  @api
  refresh() {
    this.errorMessage = undefined;
    return this.load();
  }

  async load() {
    try {
      this.apply(await getFeatures());
    } catch (error) {
      this.errorMessage = messageOf(error);
    }
  }

  apply(model) {
    this.canEdit = Boolean(model && model.canEdit);
    this.features = ((model && model.features) || []).map((feature) => ({
      ...feature,
      stateLabel: feature.isOn ? ON : OFF,
      stateStatus: feature.isOn ? 'on' : 'off',
      showTurnOn: this.canEdit && !feature.isOn,
      buttonLabel: `${TURN_ON}: ${feature.name}`
    }));
    this.loaded = true;
  }

  get isBusy() {
    return Boolean(this.busyKey);
  }

  /** The rows as shown: Turn On is disabled while saving, or while the row says why it waits. */
  get rows() {
    return this.features.map((feature) => ({
      ...feature,
      turnOnDisabled: this.isBusy || Boolean(feature.blockedReason)
    }));
  }

  async handleTurnOn(event) {
    const key = event.target.dataset.key;
    const feature = this.features.find((row) => row.key === key);
    if (!feature) {
      return;
    }
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: format(CONFIRM_TITLE, feature.name),
      message: [
        format(helpText('Core', 'Core_Feature_ConfirmMessage'), feature.name),
        feature.confirmNote
      ]
        .filter(Boolean)
        .join(' '),
      confirmLabel: TURN_ON,
      cancelLabel: CANCEL
    });
    if (!confirmed) {
      return;
    }
    this.busyKey = key;
    this.errorMessage = undefined;
    this.savedMessage = undefined;
    try {
      this.apply(await turnOn({ key }));
      this.savedMessage = format(helpText('Core', 'Core_Feature_TurnedOn'), feature.name);
      // The settings rows the feature brings are shown by the console around this panel.
      this.dispatchEvent(new CustomEvent('featureturnedon', { detail: { key } }));
    } catch (error) {
      this.errorMessage = messageOf(error);
    } finally {
      this.busyKey = undefined;
    }
  }
}

function format(template, value) {
  return (template || '').replace('{0}', value);
}
