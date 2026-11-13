import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHome from '@salesforce/apex/VolunteersHomeController.getHome';
import getFirstRun from '@salesforce/apex/VolunteersHomeController.getFirstRun';
import { iconFor } from 'c/barnIcons';
import { tabPageReference } from 'c/barnTabs';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { pageReferenceFor, toTiles } from './volunteersHomeModel';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

/** Core's Import tab, opened by name: the first-run panel's second action. */
const IMPORT_TAB = 'Import';

/**
 * Volunteers Home (vis-modules-19): the app's first tab. Three figures that open their lists
 * (approved hours this month, hours to approve, shifts needing people), with the Volunteers
 * report charts beside them on the same page. Before the first volunteer job, a first-run
 * panel offers New Volunteer Job and Import a File instead of empty figures (D-200 R4).
 */
export default class VolunteersHome extends NavigationMixin(LightningElement) {
  labels = { loading: LOADING };
  helpReady = isHelpLoaded('Volunteers');
  loading = true;
  failed = false;
  home = [];
  firstRunState;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Volunteers').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      const [home, firstRun] = await Promise.all([
        getHome(),
        // The first-run panel is a nicety: if it cannot be read, the figures still show.
        getFirstRun().catch(() => undefined)
      ]);
      this.home = home || [];
      this.firstRunState = firstRun;
      this.failed = false;
    } catch {
      this.home = [];
      this.failed = true;
    } finally {
      this.loading = false;
    }
  }

  get showError() {
    return this.failed && this.helpReady;
  }

  get errorMessage() {
    return helpText('Volunteers', 'Volunteers_Home_LoadError');
  }

  get tiles() {
    return toTiles(this.home, iconFor);
  }

  get firstRun() {
    return Boolean(this.helpReady && this.firstRunState && this.firstRunState.show);
  }

  get canImport() {
    return Boolean(this.firstRunState && this.firstRunState.canImport);
  }

  get firstRunText() {
    return {
      heading: helpText('Volunteers', 'Volunteers_Home_FirstRunHeading'),
      message: helpText('Volunteers', 'Volunteers_Home_FirstRunMessage'),
      newJob: helpText('Volunteers', 'Volunteers_Home_FirstRunNewJob'),
      importFile: helpText('Volunteers', 'Volunteers_Home_FirstRunImport')
    };
  }

  get hasTiles() {
    return !this.firstRun && this.tiles.length > 0;
  }

  handleNewJob() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Volunteer_Job__c', actionName: 'new' }
    });
  }

  async handleImport() {
    this[NavigationMixin.Navigate](await tabPageReference(IMPORT_TAB));
  }

  handleTileSelect(event) {
    const name = event.detail && event.detail.name;
    const reference = pageReferenceFor(this.home.find((tile) => tile.name === name));
    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }
}
