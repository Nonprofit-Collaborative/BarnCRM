import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import HEADING from '@salesforce/label/c.Core_HubHome_QuickLinksHeading';
import SETTINGS from '@salesforce/label/c.Core_HubHome_QuickLinkSettings';
import HOUSEHOLDS from '@salesforce/label/c.Core_HubHome_QuickLinkHouseholds';
import ORGANIZATIONS from '@salesforce/label/c.Core_HubHome_QuickLinkOrganizations';
import SETTINGS_LINE from '@salesforce/label/c.Core_HubHome_QuickLinkSettingsLine';
import HOUSEHOLDS_LINE from '@salesforce/label/c.Core_HubHome_QuickLinkHouseholdsLine';
import ORGANIZATIONS_LINE from '@salesforce/label/c.Core_HubHome_QuickLinkOrganizationsLine';

const HOUSEHOLDS_TAB = 'Households';
/** The Account list view the Households tab shows (objects/Account/listViews). */
const HOUSEHOLDS_LIST_VIEW = 'Households';

/**
 * The places people go most from the BarnCRM home page, as icon tiles (c-barn-tool-tile),
 * opened by page reference rather than by URL.
 */
export default class HubQuickLinks extends NavigationMixin(LightningElement) {
  labels = { heading: HEADING };

  links = [
    {
      tab: HOUSEHOLDS_TAB,
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
    const name = event.detail.name;
    if (name === HOUSEHOLDS_TAB) {
      // The Households tab is the Households list view in a page, and a person may not have
      // the tab yet: it arrives with the BarnCRM Households permission set, which the nightly
      // Tab Access Check assigns. The list view itself needs only read access to accounts, so
      // the link opens it directly and works for everyone from the first day.
      this[NavigationMixin.Navigate]({
        type: 'standard__objectPage',
        attributes: { objectApiName: 'Account', actionName: 'list' },
        state: { filterName: HOUSEHOLDS_LIST_VIEW }
      });
      return;
    }
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: name }
    });
  }
}
