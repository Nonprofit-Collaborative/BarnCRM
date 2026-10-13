import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import HEADING from '@salesforce/label/c.Core_Rollups_FreshnessTitle';
import NEVER from '@salesforce/label/c.Core_Rollups_FreshnessNever';
import STALE from '@salesforce/label/c.Core_Rollups_FreshnessStale';
import LINK from '@salesforce/label/c.Core_Rollups_FreshnessLink';
import LOAD_ERROR from '@salesforce/label/c.Core_HubHome_LoadErrorMessage';
import WARNING from '@salesforce/label/c.Core_HubHome_WarningAltText';

const SETTINGS_TAB = 'BarnCRM_Settings';
const ROLLUPS_SECTION = 'Rollups';

/** "Rollups last completed" on the BarnCRM home page, and a warning once the nightly run is overdue. */
export default class HubRollups extends NavigationMixin(LightningElement) {
  labels = { heading: HEADING, never: NEVER, stale: STALE, link: LINK, warning: WARNING };

  lastCalculated;
  stale = false;
  errorMessage;
  // "Never calculated" shows once the model has arrived, not while it is still loading.
  loaded = false;

  @wire(getHomeModel)
  wiredModel({ data, error }) {
    if (data) {
      this.lastCalculated = data.rollupsLastCalculated;
      this.stale = Boolean(data.rollupsStale);
      this.errorMessage = undefined;
      this.loaded = true;
    } else if (error) {
      this.errorMessage = LOAD_ERROR;
    }
  }

  handleOpenRollups() {
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: SETTINGS_TAB },
      state: { c__section: ROLLUPS_SECTION }
    });
  }
}
