import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { iconFor } from 'c/barnIcons';
import HEADING from '@salesforce/label/c.Core_HubHome_QuickLinksHeading';
import SETTINGS from '@salesforce/label/c.Core_Settings_Title';
import HOUSEHOLDS from '@salesforce/label/c.Core_SettingsGroup_Households';
import ORGANIZATIONS from '@salesforce/label/c.Core_HubHome_QuickLinkOrganizations';
import HOUSEHOLDS_LINE from '@salesforce/label/c.Core_HubHome_QuickLinkHouseholdsLine';
import ORGANIZATIONS_LINE from '@salesforce/label/c.Core_HubHome_QuickLinkOrganizationsLine';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const HOUSEHOLDS_TAB = 'Households';
/** The Account list view the Households tab shows (objects/Account/listViews). */
const HOUSEHOLDS_LIST_VIEW = 'Households';

/**
 * The places people go most from the BarnCRM home page, as icon tiles (c-barn-tool-tile),
 * opened by page reference rather than by URL.
 */
export default class HubQuickLinks extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  labels = { heading: HEADING };

  links = [
    {
      tab: HOUSEHOLDS_TAB,
      label: HOUSEHOLDS,
      line: HOUSEHOLDS_LINE,
      iconName: iconFor(HOUSEHOLDS_TAB)
    },
    {
      tab: 'Organizations',
      label: ORGANIZATIONS,
      line: ORGANIZATIONS_LINE,
      iconName: iconFor('Organizations')
    },
    {
      tab: 'BarnCRM_Settings',
      label: SETTINGS,
      get line() {
        return helpText('Core', 'Core_HubHome_QuickLinkSettingsLine');
      },
      iconName: iconFor('BarnCRM_Settings')
    }
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
