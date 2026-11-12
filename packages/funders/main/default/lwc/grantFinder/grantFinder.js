import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStatus from '@salesforce/apex/GrantFinderController.getStatus';
import search from '@salesforce/apex/GrantFinderController.search';
import save from '@salesforce/apex/GrantFinderController.save';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/**
 * The Grant Finder tab (F-09, canonical model R-GN11): searches open federal funding listings on
 * Grants.gov and saves one to the pipeline as a Prospect grant. Off when the Grant Finder setting
 * is off; a person who cannot create grants sees no Save to Pipeline.
 */
export default class GrantFinder extends LightningElement {
  helpReady = isHelpLoaded('Funders');
  icon = iconFor('Grant_Finder');
  status;
  keyword = '';
  statuses = ['posted'];
  listings;
  errorMessage;
  isLoading = true;
  savingId;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Funders').then(() => {
        this.helpReady = true;
      });
    }
    this.loadStatus();
  }

  async loadStatus() {
    try {
      this.status = await getStatus();
    } catch (error) {
      this.errorMessage = messageFrom(error, helpText('Funders', 'Funders_Manage_LoadFailed'));
    } finally {
      this.isLoading = false;
    }
  }

  get t() {
    return this.helpReady
      ? {
          title: helpText('Funders', 'Funders_Finder_Title'),
          intro: helpText('Funders', 'Funders_Finder_Intro'),
          off: helpText('Funders', 'Funders_Finder_Off'),
          search: helpText('Funders', 'Funders_Finder_Search'),
          show: helpText('Funders', 'Funders_Finder_Show'),
          empty: helpText('Funders', 'Funders_Finder_Empty'),
          agency: helpText('Funders', 'Funders_Finder_Agency'),
          number: helpText('Funders', 'Funders_Finder_Number'),
          opens: helpText('Funders', 'Funders_Finder_Opens'),
          closes: helpText('Funders', 'Funders_Finder_Closes'),
          listing: helpText('Funders', 'Funders_Finder_Listing'),
          saved: helpText('Funders', 'Funders_Finder_Saved')
        }
      : {};
  }

  get statusOptions() {
    return [
      {
        label: this.helpReady ? helpText('Funders', 'Funders_Finder_Posted') : '',
        value: 'posted'
      },
      {
        label: this.helpReady ? helpText('Funders', 'Funders_Finder_Forecasted') : '',
        value: 'forecasted'
      }
    ];
  }

  get isOff() {
    return Boolean(this.status) && !this.status.enabled;
  }

  get isOn() {
    return Boolean(this.status) && this.status.enabled;
  }

  get searchDisabled() {
    return this.isLoading || !this.keyword.trim();
  }

  get rows() {
    const canSave = Boolean(this.status && this.status.canSave);
    return (this.listings || []).map((listing) => ({
      ...listing,
      key: listing.id || listing.title,
      grantUrl: listing.grantId ? `/${listing.grantId}` : null,
      canSave: canSave && !listing.grantId,
      saving: this.savingId === listing.id,
      saveLabel: this.helpReady ? helpText('Funders', 'Funders_Finder_Save') : ''
    }));
  }

  get noResults() {
    return Array.isArray(this.listings) && this.listings.length === 0;
  }

  handleKeyword(event) {
    this.keyword = event.target.value || '';
  }

  handleStatuses(event) {
    this.statuses = event.detail.value;
  }

  handleKeyUp(event) {
    if (event.key === 'Enter' && !this.searchDisabled) {
      this.handleSearch();
    }
  }

  async handleSearch() {
    this.isLoading = true;
    try {
      this.listings = await search({ keyword: this.keyword.trim(), statuses: this.statuses });
      this.errorMessage = undefined;
    } catch (error) {
      this.listings = undefined;
      this.errorMessage = messageFrom(error, helpText('Funders', 'Funders_Finder_SearchFailed'));
    } finally {
      this.isLoading = false;
    }
  }

  async handleSave(event) {
    const id = event.currentTarget.dataset.id;
    const listing = (this.listings || []).find((row) => row.id === id);
    if (!listing) {
      return;
    }
    this.savingId = id;
    try {
      const grantId = await save({ listing: JSON.stringify(listing) });
      this.listings = this.listings.map((row) => (row.id === id ? { ...row, grantId } : row));
      this.dispatchEvent(
        new ShowToastEvent({
          message: helpText('Funders', 'Funders_Finder_SavedToast'),
          variant: 'success'
        })
      );
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          message: messageFrom(error, helpText('Funders', 'Funders_Shared_NotSaved')),
          variant: 'error'
        })
      );
    } finally {
      this.savingId = undefined;
    }
  }
}
