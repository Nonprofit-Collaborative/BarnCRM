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

/**
 * Fundraising Home (people-giving-22): five "today" figures that open their lists, Enter a Gift,
 * and the Fundraising Setup tiles for the setup pages that left the app's menu. The report
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

  get hasTiles() {
    return this.tiles.length > 0;
  }

  get hasSetup() {
    return Boolean(
      this.helpReady && this.home && this.home.setupTiles && this.home.setupTiles.length
    );
  }

  get setupGroups() {
    const tiles = (this.home ? this.home.setupTiles : []).map((tile) => ({
      name: tile.name,
      label: tile.label,
      description: this.setupDescription(tile.name),
      iconName: iconFor(tile.name)
    }));
    return [{ name: 'setup', label: SETUP_GROUP, tiles }];
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
    if (name) {
      this[NavigationMixin.Navigate](await tabPageReference(name));
    }
  }

  async handleEnterGift() {
    this[NavigationMixin.Navigate](await tabPageReference(QUICK_GIFT_ENTRY));
  }
}
