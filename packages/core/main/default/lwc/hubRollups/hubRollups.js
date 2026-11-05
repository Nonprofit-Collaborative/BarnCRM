import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import getSettingsLink from '@salesforce/apex/SettingsController.getSettingsLink';
import HEADING from '@salesforce/label/c.Core_Rollups_FreshnessTitle';
import STALE from '@salesforce/label/c.Core_Rollups_FreshnessStale';
import LINK from '@salesforce/label/c.Core_Rollups_FreshnessLink';
import NOT_RUN from '@salesforce/label/c.Core_OrgOptimizer_BadgeNotRun';
import OVERDUE from '@salesforce/label/c.Core_HubHome_BadgeOverdue';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const ROLLUPS_SECTION = 'Rollups';

/**
 * "Rollups last completed" on the BarnCRM home page, and a warning once the nightly run is overdue.
 * Shown only when the Rollup Builder module is installed (ADR-0125): an org that keeps its totals
 * with another tool sees no tile.
 */
export default class HubRollups extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  labels = {
    heading: HEADING,
    get never() {
      return helpText('Core', 'Core_Rollups_FreshnessNever');
    },
    stale: STALE,
    link: LINK,
    notRun: NOT_RUN,
    overdue: OVERDUE
  };

  lastCalculated;
  stale = false;
  errorMessage;
  installed = false;
  // "Never calculated" shows once the model has arrived, not while it is still loading.
  loaded = false;

  get shown() {
    return this.installed || Boolean(this.errorMessage);
  }

  @wire(getHomeModel)
  wiredModel({ data, error }) {
    if (data) {
      this.installed = Boolean(data.rollupsInstalled);
      this.lastCalculated = data.rollupsLastCalculated;
      // Late only once rollups have run at all: before the first run the tile says Not Run Yet,
      // not that a run is overdue (screenshot review 2026-10-28).
      this.stale = Boolean(data.rollupsStale && data.rollupsLastCalculated);
      this.errorMessage = undefined;
      this.loaded = true;
    } else if (error) {
      this.errorMessage = helpText('Core', 'Core_HubHome_LoadErrorMessage');
    }
  }

  // The tab and the section key are qualified for the org's namespace in Apex.
  async handleOpenRollups() {
    try {
      const link = await getSettingsLink();
      this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: { apiName: link.tabApiName },
        state: { [link.sectionKey]: ROLLUPS_SECTION }
      });
    } catch {
      this.errorMessage = helpText('Core', 'Core_HubHome_LoadErrorMessage');
    }
  }
}
