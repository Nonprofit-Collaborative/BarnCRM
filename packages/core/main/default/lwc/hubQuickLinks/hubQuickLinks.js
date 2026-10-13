import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import HEADING from '@salesforce/label/c.Core_HubHome_QuickLinksHeading';
import SETTINGS from '@salesforce/label/c.Core_HubHome_QuickLinkSettings';
import HOUSEHOLDS from '@salesforce/label/c.Core_HubHome_QuickLinkHouseholds';
import ORGANIZATIONS from '@salesforce/label/c.Core_HubHome_QuickLinkOrganizations';

/** The places people go most from the BarnCRM home page, opened by tab rather than by URL. */
export default class HubQuickLinks extends NavigationMixin(LightningElement) {
  labels = { heading: HEADING };

  links = [
    { tab: 'Households', label: HOUSEHOLDS },
    { tab: 'Organizations', label: ORGANIZATIONS },
    { tab: 'BarnCRM_Settings', label: SETTINGS }
  ];

  handleOpen(event) {
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: event.target.dataset.tab }
    });
  }
}
