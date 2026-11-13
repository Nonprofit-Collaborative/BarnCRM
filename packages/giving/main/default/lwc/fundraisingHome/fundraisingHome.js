import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHome from '@salesforce/apex/FundraisingHomeController.getHome';
import { iconFor } from 'c/barnIcons';
import { tabPageReference } from 'c/barnTabs';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { pageReferenceFor, toTiles } from 'c/fundraisingHomeModel';
import ENTER_GIFT from '@salesforce/label/c.Giving_FundraisingHome_EnterGift';
import SETUP_GROUP from '@salesforce/label/c.Giving_FundraisingHome_SetupGroup';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

const QUICK_GIFT_ENTRY = 'Quick_Gift_Entry';
/** Core's Import tab, opened by name: the first-run panel's second action. */
const IMPORT_TAB = 'Import';
/** The help key for each More tile's one line. */
const MORE_HELP = {
  Ask__c: 'Giving_FundraisingHome_AsksHelp',
  Installment__c: 'Giving_FundraisingHome_InstallmentsHelp',
  Fund__c: 'Giving_FundraisingHome_FundsHelp',
  Appeal__c: 'Giving_FundraisingHome_AppealsHelp',
  Tribute__c: 'Giving_FundraisingHome_TributesHelp',
  Donor_Segments: 'Giving_FundraisingHome_DonorSegmentsHelp',
  Recurring_Donor_Health: 'Giving_FundraisingHome_RecurringDonorHealthHelp',
  Dashboard: 'Giving_FundraisingHome_DashboardsHelp'
};

/**
 * Fundraising Home (people-giving-22): five "today" figures that open their lists, Enter a Gift,
 * the Fundraising Setup tiles for the setup pages that left the app's menu, and the More tiles
 * for the lists that left it in release 1.24 (D-200 R5). Before the first gift, a first-run
 * panel offers Enter a Gift and Import a File instead of empty figures (D-200 R4). The report
 * charts beside it are standard Report Chart components on the same page (vis-core-18).
 */
export default class FundraisingHome extends NavigationMixin(LightningElement) {
  labels = { enterGift: ENTER_GIFT, loading: LOADING };
  helpReady = isHelpLoaded('Giving');
  loading = true;
  failed = false;
  home;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Giving').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.home = await getHome();
      this.failed = false;
    } catch {
      this.home = undefined;
      this.failed = true;
    } finally {
      this.loading = false;
    }
  }

  get canEnterGift() {
    return Boolean(this.home && this.home.canEnterGift);
  }

  get showError() {
    return this.failed && this.helpReady;
  }

  get errorMessage() {
    return helpText('Giving', 'Giving_FundraisingHome_LoadError');
  }

  get tiles() {
    return toTiles(this.home ? this.home.tiles : [], iconFor);
  }

  get firstRun() {
    return Boolean(this.helpReady && this.home && this.home.firstRun);
  }

  get canImport() {
    return Boolean(this.home && this.home.canImport);
  }

  get firstRunText() {
    return {
      heading: helpText('Giving', 'Giving_FundraisingHome_FirstRunHeading'),
      message: helpText('Giving', 'Giving_FundraisingHome_FirstRunMessage'),
      importFile: helpText('Giving', 'Giving_FundraisingHome_FirstRunImport')
    };
  }

  get hasTiles() {
    return !this.firstRun && this.tiles.length > 0;
  }

  get hasSetup() {
    return this.helpReady && this.setupGroups.length > 0;
  }

  get setupGroups() {
    const home = this.home || {};
    const groups = [];
    const setup = (home.setupTiles || []).map((tile) => ({
      name: tile.name,
      label: tile.label,
      description: this.setupDescription(tile.name),
      iconName: iconFor(tile.name)
    }));
    if (setup.length) {
      groups.push({ name: 'setup', label: SETUP_GROUP, tiles: setup });
    }
    const more = (home.moreTiles || []).map((tile) => ({
      name: tile.name,
      label: tile.label,
      description: MORE_HELP[tile.name] ? helpText('Giving', MORE_HELP[tile.name]) : undefined,
      iconName: iconFor(tile.name, 'standard:dashboard')
    }));
    if (more.length) {
      groups.push({
        name: 'more',
        label: helpText('Giving', 'Giving_FundraisingHome_MoreGroup'),
        tiles: more
      });
    }
    return groups;
  }

  setupDescription(name) {
    switch (name) {
      case 'Donor_Levels':
        return helpText('Giving', 'Giving_FundraisingHome_DonorLevelsHelp');
      case 'Stewardship_Plans':
        return helpText('Giving', 'Giving_FundraisingHome_StewardshipPlansHelp');
      case 'Pledge_Reminders':
        return helpText('Giving', 'Giving_FundraisingHome_PledgeRemindersHelp');
      case 'Receipts':
        return helpText('Giving', 'Giving_FundraisingHome_ReceiptsHelp');
      default:
        return undefined;
    }
  }

  handleTileSelect(event) {
    const name = event.detail && event.detail.name;
    const tile = ((this.home && this.home.tiles) || []).find((each) => each.name === name);
    const reference = pageReferenceFor(tile);
    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }

  async handleSetupSelect(event) {
    const name = event.detail && event.detail.name;
    if (!name) {
      return;
    }
    const more = ((this.home && this.home.moreTiles) || []).find((tile) => tile.name === name);
    if (more && more.objectApiName) {
      // An object's list (for Dashboard, the Dashboards home) opens by object, so it works
      // whether or not the person has the tab in their menu.
      this[NavigationMixin.Navigate]({
        type: 'standard__objectPage',
        attributes: {
          objectApiName: more.objectApiName,
          actionName: more.objectApiName === 'Dashboard' ? 'home' : 'list'
        }
      });
      return;
    }
    this[NavigationMixin.Navigate](await tabPageReference(name));
  }

  async handleImport() {
    this[NavigationMixin.Navigate](await tabPageReference(IMPORT_TAB));
  }

  async handleEnterGift() {
    this[NavigationMixin.Navigate](await tabPageReference(QUICK_GIFT_ENTRY));
  }
}
