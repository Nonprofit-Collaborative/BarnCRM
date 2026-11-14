import { LightningElement, api } from 'lwc';
import getFinancials from '@salesforce/apex/ProjectBillingController.getFinancials';
import recognizeRevenue from '@salesforce/apex/ProjectBillingController.recognizeRevenue';
import { messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { financials, lastClosedMonth } from 'c/projectsBillingModel';

const PKG = 'Projects';

/**
 * The Financials card on the project page (PM-11, R-PM21): budget with approved changes,
 * revenue, cost and margin (cost and margin for Projects Admin only), invoiced and unbilled, and
 * recognized revenue month by month with the open month; Recognize Revenue (Manage Projects)
 * redoes a closed month. Shown with Show financials and recognize revenue on.
 */
export default class ProjectsFinancials extends LightningElement {
  @api recordId;
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Project__c');
  card;
  month = lastClosedMonth();
  isWorking = false;
  errorMessage;
  notice;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  get labels() {
    return {
      title: helpText('Projects', 'Projects_Financials_Title'),
      budget: helpText('Projects', 'Projects_Financials_Budget'),
      revenue: helpText('Projects', 'Projects_Financials_Revenue'),
      cost: helpText('Projects', 'Projects_Financials_Cost'),
      margin: helpText('Projects', 'Projects_Financials_Margin'),
      invoiced: helpText('Projects', 'Projects_Financials_Invoiced'),
      unbilled: helpText('Projects', 'Projects_Financials_Unbilled'),
      month: helpText('Projects', 'Projects_Financials_Month'),
      recognized: helpText('Projects', 'Projects_Financials_Recognized'),
      openMonth: helpText('Projects', 'Projects_Financials_OpenMonth'),
      recognize: helpText('Projects', 'Projects_Revenue_Recognize'),
      recognized_done: helpText('Projects', 'Projects_Revenue_Done')
    };
  }

  get isShown() {
    return this.helpReady && this.card?.enabled === true;
  }

  get view() {
    const view = financials(this.card);
    return {
      ...view,
      months: view.months.map((row) => ({
        ...row,
        label: row.open ? `${row.month} (${this.labels.openMonth})` : row.month
      }))
    };
  }

  get withCost() {
    return this.card?.withCost === true;
  }

  get canManage() {
    return this.card?.canManage === true;
  }

  async load() {
    try {
      this.card = await getFinancials({ projectId: this.recordId });
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  handleMonth(event) {
    this.month = event.target.value;
  }

  async handleRecognize() {
    this.isWorking = true;
    try {
      await recognizeRevenue({ projectId: this.recordId, month: this.month });
      this.notice = this.labels.recognized_done;
      this.errorMessage = undefined;
      await this.load();
    } catch (error) {
      this.notice = undefined;
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }
}
