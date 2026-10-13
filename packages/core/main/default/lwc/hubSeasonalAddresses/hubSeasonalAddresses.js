import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import HEADING from '@salesforce/label/c.Core_SeasonalAddress_HubTitle';
import NEVER from '@salesforce/label/c.Core_SeasonalAddress_NeverRun';
import NOT_SCHEDULED from '@salesforce/label/c.Core_SeasonalAddress_NotScheduled';
import STALE from '@salesforce/label/c.Core_SeasonalAddress_Stale';
import LINK from '@salesforce/label/c.Core_SeasonalAddress_HubLink';
import LOAD_ERROR from '@salesforce/label/c.Core_HubHome_LoadErrorMessage';
import WARNING from '@salesforce/label/c.Core_HubHome_WarningAltText';

const SETTINGS_TAB = 'BarnCRM_Settings';
const ADDRESSES_SECTION = 'Addresses';

/**
 * "Seasonal addresses last swapped" on the BarnCRM home page (C-18, R-AD8): a nightly job
 * whose last run nobody can see is a job nobody trusts.
 */
export default class HubSeasonalAddresses extends NavigationMixin(LightningElement) {
  labels = {
    heading: HEADING,
    never: NEVER,
    notScheduled: NOT_SCHEDULED,
    stale: STALE,
    link: LINK,
    warning: WARNING
  };

  lastRun;
  lastRunSummary;
  scheduled = false;
  stale = false;
  loaded = false;
  errorMessage;

  @wire(getHomeModel)
  wiredModel({ data, error }) {
    if (data) {
      this.loaded = true;
      this.lastRun = data.seasonalAddressLastRun;
      this.lastRunSummary = data.seasonalAddressLastRunSummary;
      this.scheduled = Boolean(data.seasonalAddressScheduled);
      this.stale = Boolean(data.seasonalAddressStale);
      this.errorMessage = undefined;
    } else if (error) {
      this.errorMessage = LOAD_ERROR;
    }
  }

  /**
   * Not scheduled is a choice somebody can make; scheduled and overdue is a fault. Saying both
   * at once would be noise, so the missing schedule is only shown when there is no fault.
   */
  get notScheduled() {
    return this.loaded && !this.scheduled && !this.stale;
  }

  handleOpenAddresses() {
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: SETTINGS_TAB },
      state: { c__section: ADDRESSES_SECTION }
    });
  }
}
