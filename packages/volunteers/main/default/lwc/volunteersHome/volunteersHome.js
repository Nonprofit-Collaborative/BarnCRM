import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHome from '@salesforce/apex/VolunteersHomeController.getHome';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { pageReferenceFor, toTiles } from './volunteersHomeModel';
import LOADING from '@salesforce/label/c.Core_AccessExplorer_Loading';

/**
 * Volunteers Home (vis-modules-19): the app's first tab. Three figures that open their lists
 * (approved hours this month, hours to approve, shifts needing people), with the Volunteers
 * report charts beside them on the same page.
 */
export default class VolunteersHome extends NavigationMixin(LightningElement) {
  labels = { loading: LOADING };
  helpReady = isHelpLoaded('Volunteers');
  loading = true;
  failed = false;
  home = [];

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
      this.home = (await getHome()) || [];
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

  get hasTiles() {
    return this.tiles.length > 0;
  }

  handleTileSelect(event) {
    const name = event.detail && event.detail.name;
    const reference = pageReferenceFor(this.home.find((tile) => tile.name === name));
    if (reference) {
      this[NavigationMixin.Navigate](reference);
    }
  }
}
