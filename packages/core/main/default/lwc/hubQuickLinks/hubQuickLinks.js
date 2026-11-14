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
import IMPORT_FILE from '@salesforce/label/c.Core_HubHome_QuickLinkImport';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const PEOPLE_LINK = 'People';
const HOUSEHOLDS_TAB = 'Households';
/** The Account list view the Households tab shows (objects/Account/listViews). */
const HOUSEHOLDS_LIST_VIEW = 'Households';
const IMPORT_TAB = 'Import';
const SETTINGS_TAB = 'BarnCRM_Settings';
/** A module link that opens an object's new record form is named by this prefix and the object. */
const NEW_RECORD = 'new:';

/**
 * The places people go most from the BarnCRM home page, as icon tiles (c-barn-tool-tile),
 * opened by page reference rather than by URL: People, Households, Organizations and Find for
 * everyone; Import a File for someone who may import; then each installed, turned-on module's
 * own links from the module catalog (Enter a Gift, Log Hours, Enroll; D-200 R7), so Core names
 * no module; BarnCRM Settings only for people with Manage BarnCRM Settings.
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
    if (model.canImport) {
      links.push({
        tab: IMPORT_TAB,
        label: IMPORT_FILE,
        line: helpText('Core', 'Core_HubHome_QuickLinkImportLine'),
        iconName: iconFor(IMPORT_TAB)
      });
    }
    (model.quickLinks || []).forEach((link) => {
      links.push({
        tab: link.objectApiName ? NEW_RECORD + link.objectApiName : link.tab,
        label: link.label,
        line: link.line,
        iconName: iconFor(link.objectApiName || link.tab)
      });
    });
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
    if (name && name.startsWith(NEW_RECORD)) {
      this[NavigationMixin.Navigate]({
        type: 'standard__objectPage',
        attributes: { objectApiName: name.slice(NEW_RECORD.length), actionName: 'new' }
      });
      return;
    }
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
