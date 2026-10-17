import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import getSettingsLink from '@salesforce/apex/SettingsController.getSettingsLink';
import HEADING from '@salesforce/label/c.Core_Rollups_FreshnessTitle';
import NEVER from '@salesforce/label/c.Core_Rollups_FreshnessNever';
import STALE from '@salesforce/label/c.Core_Rollups_FreshnessStale';
import LINK from '@salesforce/label/c.Core_Rollups_FreshnessLink';
import LOAD_ERROR from '@salesforce/label/c.Core_HubHome_LoadErrorMessage';
import WARNING from '@salesforce/label/c.Core_HubHome_WarningAltText';

const ROLLUPS_SECTION = 'Rollups';

/**
 * "Rollups last completed" on the BarnCRM home page, and a warning once the nightly run is overdue.
 * Shown only when the Rollup Builder module is installed (ADR-0125): an org that keeps its totals
 * with another tool sees no tile.
 */
export default class HubRollups extends NavigationMixin(LightningElement) {
  labels = { heading: HEADING, never: NEVER, stale: STALE, link: LINK, warning: WARNING };

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
      this.stale = Boolean(data.rollupsStale);
      this.errorMessage = undefined;
      this.loaded = true;
    } else if (error) {
      this.errorMessage = LOAD_ERROR;
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
      this.errorMessage = LOAD_ERROR;
    }
  }
}
