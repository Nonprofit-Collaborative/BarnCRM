import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import { iconFor } from 'c/barnIcons';
import { tabPageReference } from 'c/barnTabs';
import HEADING from '@salesforce/label/c.Core_HubHome_QuickLinksHeading';
import SETTINGS from '@salesforce/label/c.Core_Settings_Title';
import PEOPLE from '@salesforce/label/c.Core_SettingsGroup_People';
import HOUSEHOLDS from '@salesforce/label/c.Core_SettingsGroup_Households';
import ORGANIZATIONS from '@salesforce/label/c.Core_HubHome_QuickLinkOrganizations';
import FIND from '@salesforce/label/c.Core_Find_Title';
import GIFT_ENTRY from '@salesforce/label/c.Core_HubHome_QuickLinkGiftEntry';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const PEOPLE_LINK = 'People';
const HOUSEHOLDS_TAB = 'Households';
/** The Account list view the Households tab shows (objects/Account/listViews). */
const HOUSEHOLDS_LIST_VIEW = 'Households';
/** Giving's tab, opened by name only: Core has no dependency on Giving (people-giving-7). */
const GIFT_ENTRY_TAB = 'Quick_Gift_Entry';
const SETTINGS_TAB = 'BarnCRM_Settings';

/**
 * The places people go most from the BarnCRM home page, as icon tiles (c-barn-tool-tile),
 * opened by page reference rather than by URL: People, Households, Organizations and Find for
 * everyone; Quick Gift Entry while the Giving module is installed and on (the home model reads
 * the module catalog); BarnCRM Settings only for people with Manage BarnCRM Settings.
 */
export default class HubQuickLinks extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');
  labels = { heading: HEADING };
  model;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  // Cacheable, so every home page tile wiring it shares one server call.
  @wire(getHomeModel)
  wiredModel({ data }) {
    this.model = data;
  }

  get links() {
    const model = this.model || {};
    const links = [
      {
        tab: PEOPLE_LINK,
        label: PEOPLE,
        line: helpText('Core', 'Core_HubHome_QuickLinkPeopleLine'),
        iconName: iconFor('Contact')
      },
      {
        tab: HOUSEHOLDS_TAB,
        label: HOUSEHOLDS,
        line: helpText('Core', 'Core_HubHome_QuickLinkHouseholdsLine'),
        iconName: iconFor(HOUSEHOLDS_TAB)
      },
      {
        tab: 'Organizations',
        label: ORGANIZATIONS,
        line: helpText('Core', 'Core_HubHome_QuickLinkOrganizationsLine'),
        iconName: iconFor('Organizations')
      },
      {
        tab: 'Find',
        label: FIND,
        line: helpText('Core', 'Core_HubHome_QuickLinkFindLine'),
        iconName: iconFor('Find')
      }
    ];
    if (model.giftEntryAvailable) {
      links.push({
        tab: GIFT_ENTRY_TAB,
        label: GIFT_ENTRY,
        line: helpText('Core', 'Core_HubHome_QuickLinkGiftEntryLine'),
        iconName: iconFor(GIFT_ENTRY_TAB)
      });
    }
    if (model.canEdit) {
      links.push({
        tab: SETTINGS_TAB,
        label: SETTINGS,
        line: helpText('Core', 'Core_HubHome_QuickLinkSettingsLine'),
        iconName: iconFor(SETTINGS_TAB)
      });
    }
    return links;
  }

  async handleOpen(event) {
    const name = event.detail.name;
    if (name === PEOPLE_LINK) {
      this[NavigationMixin.Navigate]({
        type: 'standard__objectPage',
        attributes: { objectApiName: 'Contact', actionName: 'list' }
      });
      return;
    }
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
    this[NavigationMixin.Navigate](await tabPageReference(name));
  }
}
