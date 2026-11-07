import { LightningElement, api } from 'lwc';
import listRadiusFields from '@salesforce/apex/FindController.listRadiusFields';
import resolveRadiusCenter from '@salesforce/apex/FindController.resolveRadiusCenter';
import { format, messageFrom } from 'c/findCsv';

import RADIUS from '@salesforce/label/c.Core_Find_Radius';
import ADDRESS from '@salesforce/label/c.Core_Find_RadiusAddress';
import MILES from '@salesforce/label/c.Core_Find_RadiusMilesLabel';
import PLACE from '@salesforce/label/c.Core_Find_RadiusPlace';
import USE from '@salesforce/label/c.Core_Find_RadiusUse';
import REMOVE from '@salesforce/label/c.Core_Find_Remove';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const DEFAULT_MILES = 25;

/**
 * Distance from a place in Find (C-69, canonical model R-SQ13): "within N miles of a postal
 * code or of the address on a record". The place is looked up on the server (a shipped table of
 * US postal codes, or the geocode already stored on a record), so the document only ever holds
 * numbers: it reports `{ field, miles, latitude, longitude }` as the document's `radius` key in
 * a `change` event, and the server checks it. Nothing is geocoded outside Salesforce.
 */
export default class FindRadiusPanel extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  labels = {
    radius: RADIUS,
    address: ADDRESS,
    miles: MILES,
    place: PLACE,
    use: USE,
    remove: REMOVE,
    get help() {
      return helpText('Core', 'Core_Find_RadiusHelp');
    },
    get noFields() {
      return helpText('Core', 'Core_Find_RadiusNoFields');
    },
    get needsPlace() {
      return helpText('Core', 'Core_Find_RadiusNeedsPlace');
    }
  };

  options = [];
  active = false;
  field = '';
  miles = DEFAULT_MILES;
  placeText = '';
  center;
  errorMessage;
  loadedFor;
  lastRadius = '';
  _objectApiName;

  @api
  get objectApiName() {
    return this._objectApiName;
  }
  set objectApiName(value) {
    this._objectApiName = value;
    this.loadFields();
  }

  /** The document's `radius`, when a query is opened. */
  @api
  get radius() {
    return this.entry();
  }
  set radius(value) {
    // Find hands back what this panel just reported; keep what is being edited.
    if (JSON.stringify(value || null) === this.lastRadius) {
      return;
    }
    if (!value) {
      this.active = false;
      this.center = undefined;
      return;
    }
    this.active = true;
    this.field = value.field;
    this.miles = value.miles;
    this.placeText = '';
    this.center = { latitude: value.latitude, longitude: value.longitude };
  }

  async loadFields() {
    if (!this._objectApiName || this.loadedFor === this._objectApiName) {
      return;
    }
    this.loadedFor = this._objectApiName;
    try {
      this.options = ((await listRadiusFields({ objectApiName: this._objectApiName })) || []).map(
        (option) => ({ label: option.label, value: option.value })
      );
      if (!this.field || !this.options.some((option) => option.value === this.field)) {
        this.field = this.options.length > 0 ? this.options[0].value : '';
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  get helpVisible() {
    return this.helpReady;
  }

  get hasOptions() {
    return this.options.length > 0;
  }

  get noOptions() {
    return !this.hasOptions;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  get showNeedsPlace() {
    return this.active && !this.center;
  }

  get centerText() {
    if (!this.center) {
      return '';
    }
    const label =
      this.center.label ||
      `${this.center.latitude.toFixed(4)}, ${this.center.longitude.toFixed(4)}`;
    return format(helpText('Core', 'Core_Find_RadiusCenterSet'), label);
  }

  get centerNote() {
    return (this.center && this.center.note) || '';
  }

  entry() {
    if (!this.active || !this.center || !this.field) {
      return undefined;
    }
    return {
      field: this.field,
      miles: Number(this.miles),
      latitude: this.center.latitude,
      longitude: this.center.longitude
    };
  }

  announce() {
    const radius = this.entry();
    this.lastRadius = JSON.stringify(radius || null);
    this.dispatchEvent(
      new CustomEvent('change', { detail: { radius, valid: !this.active || !!radius } })
    );
  }

  handleAdd() {
    this.active = true;
    this.announce();
  }

  handleRemove() {
    this.active = false;
    this.center = undefined;
    this.placeText = '';
    this.errorMessage = undefined;
    this.announce();
  }

  handleFieldChange(event) {
    this.field = event.detail.value;
    this.announce();
  }

  handleMilesChange(event) {
    this.miles = event.detail.value;
    this.announce();
  }

  handlePlaceChange(event) {
    this.placeText = event.detail.value;
    // A new place must be looked up again before the distance can use it.
    this.center = undefined;
    this.errorMessage = undefined;
    this.announce();
  }

  async handleUse() {
    this.errorMessage = undefined;
    try {
      this.center = await resolveRadiusCenter({ text: this.placeText });
    } catch (error) {
      this.center = undefined;
      this.errorMessage = messageFrom(error);
    }
    this.announce();
  }
}
