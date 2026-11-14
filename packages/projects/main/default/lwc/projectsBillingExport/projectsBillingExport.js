import { LightningElement } from 'lwc';
import getProjectBilling from '@salesforce/apex/ProjectBillingController.getProjectBilling';
import exportInvoices from '@salesforce/apex/ProjectBillingController.exportInvoices';
import { downloadCsv, messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { defaultPeriod, INVOICE_COLUMNS, invoiceRows } from 'c/projectsBillingModel';

const PKG = 'Projects';

/**
 * Export Invoices on Projects Home (PM-10, R-PM17): Sent and Paid invoices dated in a range, one
 * CSV row per line, built here with Core's `c/findCsv`; each exported invoice is stamped. Shown
 * with Create invoices on, to Manage Projects holders.
 */
export default class ProjectsBillingExport extends LightningElement {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Project_Invoice__c');
  billing;
  period = defaultPeriod();
  includeExported = false;
  isWorking = false;
  errorMessage;
  notice;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
    getProjectBilling({ projectId: null })
      .then((billing) => {
        this.billing = billing;
      })
      .catch((error) => {
        this.errorMessage = messageFrom(error);
      });
  }

  get labels() {
    return {
      title: helpText('Projects', 'Projects_Billing_ExportTitle'),
      from: helpText('Projects', 'Projects_Home_From'),
      to: helpText('Projects', 'Projects_Home_To'),
      include: helpText('Projects', 'Projects_Billing_ExportInclude'),
      button: helpText('Projects', 'Projects_Billing_ExportButton')
    };
  }

  get isShown() {
    return this.helpReady && this.billing?.enabled === true && this.billing?.canManage === true;
  }

  handleField(event) {
    const field = event.target.dataset.field;
    if (field === 'includeExported') {
      this.includeExported = event.target.checked;
    } else {
      this.period = { ...this.period, [field]: event.target.value };
    }
  }

  async handleExport() {
    this.isWorking = true;
    try {
      const invoices = await exportInvoices({
        fromDate: this.period.start,
        toDate: this.period.end,
        includeExported: this.includeExported
      });
      downloadCsv('project_invoices', INVOICE_COLUMNS, invoiceRows(invoices));
      this.notice = helpText('Projects', 'Projects_Billing_ExportDone', invoices.length);
      this.errorMessage = undefined;
    } catch (error) {
      this.notice = undefined;
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }
}
