import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import INVOICE from '@salesforce/schema/Project_Invoice__c';
import getProjectBilling from '@salesforce/apex/ProjectBillingController.getProjectBilling';
import buildInvoice from '@salesforce/apex/ProjectBillingController.buildInvoice';
import { messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { defaultPeriod } from 'c/projectsBillingModel';

const PKG = 'Projects';

/**
 * New Invoice on the project page (PM-10, R-PM16): a period, then a Draft built from the
 * project's unbilled work, opened when made. Shown only with Create invoices on, to Manage
 * Projects holders, on a project that is billed.
 */
export default class ProjectsInvoiceBuilder extends NavigationMixin(LightningElement) {
  @api recordId;
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Project_Invoice__c');
  billing;
  period = defaultPeriod();
  isWorking = false;
  errorMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
    getProjectBilling({ projectId: this.recordId })
      .then((billing) => {
        this.billing = billing;
      })
      .catch((error) => {
        this.errorMessage = messageFrom(error);
      });
  }

  get labels() {
    return {
      title: helpText('Projects', 'Projects_Invoice_NewTitle'),
      intro: helpText('Projects', 'Projects_Invoice_NewIntro'),
      start: helpText('Projects', 'Projects_Invoice_PeriodStart'),
      end: helpText('Projects', 'Projects_Invoice_PeriodEnd'),
      build: helpText('Projects', 'Projects_Invoice_Build')
    };
  }

  get isShown() {
    return (
      this.helpReady &&
      this.billing?.enabled === true &&
      this.billing?.canManage === true &&
      this.billing?.billingType !== 'Not Billed'
    );
  }

  handlePeriod(event) {
    this.period = { ...this.period, [event.target.dataset.field]: event.target.value };
  }

  async handleBuild() {
    this.isWorking = true;
    try {
      const invoiceId = await buildInvoice({
        projectId: this.recordId,
        periodStart: this.period.start,
        periodEnd: this.period.end
      });
      this.errorMessage = undefined;
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: {
          recordId: invoiceId,
          objectApiName: INVOICE.objectApiName,
          actionName: 'view'
        }
      });
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }
}
