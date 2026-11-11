import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRenewals from '@salesforce/apex/GrantManagementController.getRenewals';
import startRenewal from '@salesforce/apex/GrantManagementController.startRenewal';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/**
 * The Renewals card on a grant's page (F-13, canonical model R-GN12): the grant's history across
 * years, oldest first, and Start Renewal on an awarded grant not yet renewed.
 */
export default class GrantRenewals extends NavigationMixin(LightningElement) {
  @api recordId;

  helpReady = isHelpLoaded('Funders');
  icon = iconFor('Grant__c');
  card;
  errorMessage;
  isLoading = true;
  starting = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Funders').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.isLoading = true;
    try {
      this.card = await getRenewals({ grantId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.card = undefined;
      this.errorMessage = messageFrom(error, helpText('Funders', 'Funders_Manage_LoadFailed'));
    } finally {
      this.isLoading = false;
    }
  }

  get t() {
    return this.helpReady
      ? {
          title: helpText('Funders', 'Funders_Renewals_Title'),
          empty: helpText('Funders', 'Funders_Renewals_Empty'),
          start: helpText('Funders', 'Funders_Renewals_Start'),
          thisGrant: helpText('Funders', 'Funders_Renewals_ThisGrant'),
          to: helpText('Funders', 'Funders_Renewals_To')
        }
      : {};
  }

  get chain() {
    return ((this.card && this.card.chain) || []).map((grant) => ({
      ...grant,
      url: `/${grant.id}`
    }));
  }

  get hasHistory() {
    return this.chain.length > 1;
  }

  get canStart() {
    return Boolean(this.card && this.card.canStart);
  }

  async handleStart() {
    this.starting = true;
    try {
      const grantId = await startRenewal({ grantId: this.recordId });
      this.dispatchEvent(
        new ShowToastEvent({
          message: helpText('Funders', 'Funders_Renewals_Started'),
          variant: 'success'
        })
      );
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: { recordId: grantId, actionName: 'view' }
      });
    } catch (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          message: messageFrom(error, helpText('Funders', 'Funders_Shared_NotSaved')),
          variant: 'error'
        })
      );
    } finally {
      this.starting = false;
    }
  }
}
