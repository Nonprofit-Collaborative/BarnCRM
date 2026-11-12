import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

/**
 * Opens the standard Account list view named by filterName, so a BarnCRM tab (Households,
 * Organizations) gets the full list view page with its view switcher, filters and mass actions
 * instead of a short card. Navigates with replace so the Back button does not return here and
 * loop. Shows one link as a fallback when the page was not left.
 */
export default class AccountListRedirect extends NavigationMixin(LightningElement) {
  /** API name of the Account list view to open (Households, Organizations). */
  @api filterName;
  /** Text of the fallback link. */
  @api linkLabel;

  connectedCallback() {
    this.open(true);
  }

  get reference() {
    return {
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Account', actionName: 'list' },
      state: { filterName: this.filterName }
    };
  }

  open(replace) {
    this[NavigationMixin.Navigate](this.reference, replace);
  }

  handleClick(event) {
    event.preventDefault();
    this.open(false);
  }
}
