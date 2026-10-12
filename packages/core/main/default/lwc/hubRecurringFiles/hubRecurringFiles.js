import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import HEADING from '@salesforce/label/c.Core_HubHome_RecurringHeading';
import NEVER from '@salesforce/label/c.Core_HubHome_RecurringNever';
import LINK from '@salesforce/label/c.Core_HubHome_RecurringLink';

const IMPORT_TAB = 'Import';

/**
 * The files that arrive regularly and when each was last imported, oldest first (R-IT6).
 * Shows nothing at all until a file is marked as arriving regularly.
 */
export default class HubRecurringFiles extends NavigationMixin(LightningElement) {
  labels = { heading: HEADING, never: NEVER, link: LINK };

  sources = [];

  @wire(getHomeModel)
  wiredModel({ data }) {
    if (data) {
      this.sources = data.recurringSources || [];
    }
  }

  get hasSources() {
    return this.sources.length > 0;
  }

  handleOpenImport() {
    this[NavigationMixin.Navigate]({
      type: 'standard__navItemPage',
      attributes: { apiName: IMPORT_TAB }
    });
  }
}
