import { LightningElement, api } from 'lwc';

// Stands in for c/filterBuilder in the Territory Management page tests, which drive its change
// event themselves.
export default class FilterBuilder extends LightningElement {
  @api objectApiName;
  @api value;
}
