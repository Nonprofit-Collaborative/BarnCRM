import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * Opens the standard Account list view named by filterName, so a BarnCRM tab (Households,
 * Organizations) gets the full list view page with its view switcher, filters and mass actions
 * instead of a short card. Navigates with replace so the Back button does not return here and
 * loop. Shows one link as a fallback when the page was not left; its text is the help catalog's
 * Core_AccountListRedirect_OpenHouseholds or _OpenOrganizations, unless a page sets linkLabel.
 */
export default class AccountListRedirect extends NavigationMixin(LightningElement) {
  /** API name of the Account list view to open (Households, Organizations). */
  @api filterName;
  /** Text of the fallback link; blank takes the help catalog's. */
  @api linkLabel;

  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
    this.open(true);
  }

  get linkText() {
    if (this.linkLabel) {
      return this.linkLabel;
    }
    return this.filterName === 'Organizations'
      ? helpText('Core', 'Core_AccountListRedirect_OpenOrganizations')
      : helpText('Core', 'Core_AccountListRedirect_OpenHouseholds');
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
