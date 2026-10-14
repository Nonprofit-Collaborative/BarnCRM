import { LightningElement } from 'lwc';
import BarnConfirmModal from 'c/barnConfirmModal';
import getFeatures from '@salesforce/apex/FeatureController.getFeatures';
import turnOn from '@salesforce/apex/FeatureController.turnOn';
import WARNING from '@salesforce/label/c.Core_Feature_OneWayWarning';
import TURN_ON from '@salesforce/label/c.Core_Feature_TurnOn';
import ON from '@salesforce/label/c.Core_Feature_On';
import OFF from '@salesforce/label/c.Core_Feature_Off';
import CONFIRM_TITLE from '@salesforce/label/c.Core_Feature_ConfirmTitle';
import CONFIRM_MESSAGE from '@salesforce/label/c.Core_Feature_ConfirmMessage';
import CANCEL from '@salesforce/label/c.Core_Feature_Cancel';
import TURNED_ON from '@salesforce/label/c.Core_Feature_TurnedOn';

/**
 * BarnCRM Settings, General, Features (ADR-NEXT): each Core feature with its description and
 * state. A feature that is off has a Turn on button behind a confirmation; turning on is
 * one-way, which the warning above the list says, so a feature that is on has no control.
 */
export default class FeatureSettings extends LightningElement {
  labels = { warning: WARNING, turnOn: TURN_ON };

  features = [];
  canEdit = false;
  loaded = false;
  busyKey;
  errorMessage;
  savedMessage;

  connectedCallback() {
    this.load();
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
      stateClass: feature.isOn ? 'slds-badge slds-theme_success' : 'slds-badge',
      showTurnOn: this.canEdit && !feature.isOn,
      buttonLabel: `${TURN_ON}: ${feature.name}`
    }));
    this.loaded = true;
  }

  get isBusy() {
    return Boolean(this.busyKey);
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
      message: format(CONFIRM_MESSAGE, feature.name),
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
      this.savedMessage = format(TURNED_ON, feature.name);
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

function messageOf(error) {
  return (error && error.body && error.body.message) || (error && error.message) || '';
}
