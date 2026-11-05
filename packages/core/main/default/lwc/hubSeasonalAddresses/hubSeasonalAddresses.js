import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import getSettingsLink from '@salesforce/apex/SettingsController.getSettingsLink';
import HEADING from '@salesforce/label/c.Core_SeasonalAddress_HubTitle';
import LINK from '@salesforce/label/c.Core_SeasonalAddress_HubLink';
import NOT_RUN from '@salesforce/label/c.Core_OrgOptimizer_BadgeNotRun';
import OVERDUE from '@salesforce/label/c.Core_HubHome_BadgeOverdue';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

const ADDRESSES_SECTION = 'Addresses';

/**
 * "Seasonal addresses last swapped" on the BarnCRM home page (C-18, R-AD8): a nightly job
 * whose last run nobody can see is a job nobody trusts.
 */
export default class HubSeasonalAddresses extends NavigationMixin(LightningElement) {
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
      return helpText('Core', 'Core_SeasonalAddress_NeverRun');
    },
    get notScheduled() {
      return helpText('Core', 'Core_SeasonalAddress_NotScheduled');
    },
    get stale() {
      return helpText('Core', 'Core_SeasonalAddress_Stale');
    },
    link: LINK,
    notRun: NOT_RUN,
    overdue: OVERDUE
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
      // As on the rollups tile: Overdue only once the swap has run at all.
      this.stale = Boolean(data.seasonalAddressStale && data.seasonalAddressLastRun);
      this.errorMessage = undefined;
    } else if (error) {
      this.errorMessage = helpText('Core', 'Core_HubHome_LoadErrorMessage');
    }
  }

  /**
   * Not scheduled is a choice somebody can make; scheduled and overdue is a fault. Saying both
   * at once would be noise, so the missing schedule is only shown when there is no fault.
   */
  get notScheduled() {
    return this.loaded && !this.scheduled && !this.stale;
  }

  // The tab and the section key are qualified for the org's namespace in Apex.
  async handleOpenAddresses() {
    try {
      const link = await getSettingsLink();
      this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: { apiName: link.tabApiName },
        state: { [link.sectionKey]: ADDRESSES_SECTION }
      });
    } catch {
      this.errorMessage = helpText('Core', 'Core_HubHome_LoadErrorMessage');
    }
  }
}
