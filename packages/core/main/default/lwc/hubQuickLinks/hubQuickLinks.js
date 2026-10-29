import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import HEADING from '@salesforce/label/c.Core_HubHome_QuickLinksHeading';
import SETTINGS from '@salesforce/label/c.Core_HubHome_QuickLinkSettings';
import HOUSEHOLDS from '@salesforce/label/c.Core_HubHome_QuickLinkHouseholds';
import ORGANIZATIONS from '@salesforce/label/c.Core_HubHome_QuickLinkOrganizations';
import SETTINGS_LINE from '@salesforce/label/c.Core_HubHome_QuickLinkSettingsLine';
import HOUSEHOLDS_LINE from '@salesforce/label/c.Core_HubHome_QuickLinkHouseholdsLine';
import ORGANIZATIONS_LINE from '@salesforce/label/c.Core_HubHome_QuickLinkOrganizationsLine';

/**
 * The places people go most from the BarnCRM home page, as icon tiles (c-barn-tool-tile),
 * opened by tab rather than by URL.
 */
export default class HubQuickLinks extends NavigationMixin(LightningElement) {
  labels = { heading: HEADING };

  links = [
    {
      tab: 'Households',
      label: HOUSEHOLDS,
      line: HOUSEHOLDS_LINE,
      iconName: 'standard:household'
    },
    {
      tab: 'Organizations',
      label: ORGANIZATIONS,
      line: ORGANIZATIONS_LINE,
      iconName: 'standard:account'
    },
    { tab: 'BarnCRM_Settings', label: SETTINGS, line: SETTINGS_LINE, iconName: 'standard:settings' }
  ];

  handleOpen(event) {
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: event.detail.name }
    });
  }
}
