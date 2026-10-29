import { LightningElement, api } from 'lwc';
import HEADING from '@salesforce/label/c.Core_OrganizationAddress_Heading';
import HINT from '@salesforce/label/c.Core_OrganizationAddress_Hint';
import STREET from '@salesforce/label/c.Core_OrganizationAddress_Street';
import STREET_2 from '@salesforce/label/c.Core_OrganizationAddress_Street2';
import CITY from '@salesforce/label/c.Core_OrganizationAddress_City';
import STATE from '@salesforce/label/c.Core_OrganizationAddress_State';
import POSTAL_CODE from '@salesforce/label/c.Core_OrganizationAddress_PostalCode';
import COUNTRY from '@salesforce/label/c.Core_OrganizationAddress_Country';

/** The settings field each part is saved to, which is also the key of `values`. */
const PART_KEYS = [
  'Organization_Street__c',
  'Organization_Street_2__c',
  'Organization_City__c',
  'Organization_State__c',
  'Organization_Postal_Code__c',
  'Organization_Country__c'
];

/**
 * The organization's mailing address as one grouped block laid out like a Salesforce address:
 * Street, Street 2, then City, State and Zip Code on one row, then Country.
 *
 * The whole address may be blank. Once any part is filled, Street, City, State and Zip Code are
 * marked required, so the person sees what is still missing (canonical model R-OA1). The block
 * holds no state: the parent passes `values` (keyed by settings field name) and keeps what
 * `partchange` reports, and the server enforces the same rule on every save.
 */
export default class OrganizationAddress extends LightningElement {
  /** Show the group heading and the line saying what may be left blank. */
  @api titled = false;
  @api disabled = false;
  @api values = {};
  /** Shown in each empty box, saying what a blank part means (for example "Not set"). */
  @api placeholder;

  labels = {
    heading: HEADING,
    hint: HINT,
    street: STREET,
    street2: STREET_2,
    city: CITY,
    state: STATE,
    postalCode: POSTAL_CODE,
    country: COUNTRY
  };

  get street() {
    return this.part('Organization_Street__c');
  }

  get street2() {
    return this.part('Organization_Street_2__c');
  }

  get city() {
    return this.part('Organization_City__c');
  }

  get state() {
    return this.part('Organization_State__c');
  }

  get postalCode() {
    return this.part('Organization_Postal_Code__c');
  }

  get country() {
    return this.part('Organization_Country__c');
  }

  /** Street, City, State and Zip Code are required as soon as any part has a value. */
  get partsRequired() {
    return PART_KEYS.some((key) => this.part(key).trim() !== '');
  }

  /** Marks every box that is still required and empty. True when the address may be saved. */
  @api
  reportValidity() {
    const inputs = Array.from(this.template.querySelectorAll('lightning-input'));
    return inputs.map((input) => input.reportValidity()).every((valid) => valid !== false);
  }

  part(key) {
    const value = this.values ? this.values[key] : undefined;
    return typeof value === 'string' ? value : '';
  }

  handleChange(event) {
    this.dispatchEvent(
      new CustomEvent('partchange', {
        detail: { key: event.target.dataset.key, value: event.target.value }
      })
    );
  }
}
