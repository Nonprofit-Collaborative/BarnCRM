import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import getBudget from '@salesforce/apex/GrantManagementController.getBudget';
import LINE from '@salesforce/schema/Grant_Budget_Line__c';
import GRANT_FIELD from '@salesforce/schema/Grant_Budget_Line__c.Grant__c';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import { budgetView } from 'c/grantManagementModel';
import { messageFrom } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/**
 * The Budget card on a grant's page (F-12, canonical model R-BL2): each budget line's requested,
 * awarded and spent amounts, what is left, and how the lines add up against the grant.
 */
export default class GrantBudget extends NavigationMixin(LightningElement) {
  @api recordId;

  helpReady = isHelpLoaded('Funders');
  icon = iconFor('Grant__c');
  budget;
  errorMessage;
  isLoading = true;

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
      this.budget = await getBudget({ grantId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.budget = undefined;
      this.errorMessage = messageFrom(error, helpText('Funders', 'Funders_Manage_LoadFailed'));
    } finally {
      this.isLoading = false;
    }
  }

  get t() {
    return this.helpReady
      ? {
          title: helpText('Funders', 'Funders_Budget_Title'),
          empty: helpText('Funders', 'Funders_Budget_Empty'),
          add: helpText('Funders', 'Funders_Budget_New'),
          line: helpText('Funders', 'Funders_Budget_Line'),
          requested: helpText('Funders', 'Funders_Budget_Requested'),
          awarded: helpText('Funders', 'Funders_Budget_Awarded'),
          spent: helpText('Funders', 'Funders_Budget_Spent'),
          remaining: helpText('Funders', 'Funders_Budget_Remaining'),
          total: helpText('Funders', 'Funders_Budget_Total')
        }
      : {};
  }

  get view() {
    return budgetView(this.budget);
  }

  get rows() {
    return this.view.lines.map((line) => ({
      ...line,
      url: `/${line.id}`,
      remainingClass: line.overspent
        ? 'slds-text-align_right slds-text-color_error'
        : 'slds-text-align_right'
    }));
  }

  get hasLines() {
    return this.rows.length > 0;
  }

  get canCreate() {
    return Boolean(this.budget && this.budget.canCreate);
  }

  get notes() {
    if (!this.helpReady) {
      return [];
    }
    const view = this.view;
    const notes = [];
    if (view.requestedGap !== null) {
      notes.push(
        helpText('Funders', 'Funders_Budget_RequestedGap', this.money(view.totals.requested))
      );
    }
    if (view.awardedGap !== null) {
      notes.push(helpText('Funders', 'Funders_Budget_AwardedGap', this.money(view.totals.awarded)));
    }
    if (view.unassigned) {
      notes.push(helpText('Funders', 'Funders_Budget_Unassigned', this.money(view.unassigned)));
    }
    return notes.map((text, index) => ({ key: String(index), text }));
  }

  money(value) {
    return new Intl.NumberFormat(LOCALE, { style: 'currency', currency: CURRENCY }).format(value);
  }

  handleNew() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: LINE.objectApiName, actionName: 'new' },
      state: {
        defaultFieldValues: encodeDefaultFieldValues({ [GRANT_FIELD.fieldApiName]: this.recordId })
      }
    });
  }
}
