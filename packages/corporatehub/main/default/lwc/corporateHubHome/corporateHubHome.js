import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getHome from '@salesforce/apex/CorporateHubController.getHome';
import acknowledge from '@salesforce/apex/CorporateHubController.acknowledge';
import addMissingTemplates from '@salesforce/apex/CorporateHubController.addMissingTemplates';
import { messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { DUE_NONE, DUE_OVERDUE, DUE_TODAY, dueState, todayIso } from 'c/corporateHubModel';

const HELP_PACKAGES = ['CorporateHub'];

/** A record's page in Lightning. */
const recordHref = (recordId) => `/lightning/r/${recordId}/view`;

/** When a line is due, in words. */
function dueText(dateIso, today) {
  const due = dueState(dateIso, today);
  if (due.state === DUE_NONE) {
    return helpText('CorporateHub', 'CorporateHub_Due_None');
  }
  if (due.state === DUE_OVERDUE) {
    return helpText('CorporateHub', 'CorporateHub_Due_Overdue', due.count);
  }
  if (due.state === DUE_TODAY) {
    return helpText('CorporateHub', 'CorporateHub_Due_Today');
  }
  return helpText('CorporateHub', 'CorporateHub_Due_InDays', due.count);
}

/**
 * The Corporate Hub page (CH-01 to CH-03, CH-08): the policies the person is asked to read, with
 * I Have Read This; the compliance obligations due in the next 60 days; the agreements whose
 * notice or end date is in the next 90; and, for a holder of Manage Corporate Hub, Add Missing
 * Templates. The lists come from `CorporateHubController.getHome`.
 */
export default class CorporateHubHome extends LightningElement {
  helpReady = isHelpLoaded(HELP_PACKAGES);
  icon = iconFor('Corporate_Hub');
  home;
  isLoading = true;
  isWorking = false;
  errorMessage;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(HELP_PACKAGES).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  get labels() {
    return {
      title: helpText('CorporateHub', 'CorporateHub_Home_Title'),
      intro: helpText('CorporateHub', 'CorporateHub_Home_Intro'),
      requests: helpText('CorporateHub', 'CorporateHub_Home_Requests'),
      noRequests: helpText('CorporateHub', 'CorporateHub_Home_NoRequests'),
      obligations: helpText('CorporateHub', 'CorporateHub_Home_Obligations'),
      noObligations: helpText('CorporateHub', 'CorporateHub_Home_NoObligations'),
      agreements: helpText('CorporateHub', 'CorporateHub_Home_Agreements'),
      noAgreements: helpText('CorporateHub', 'CorporateHub_Home_NoAgreements'),
      haveRead: helpText('CorporateHub', 'CorporateHub_Home_HaveRead'),
      addTemplates: helpText('CorporateHub', 'CorporateHub_Home_AddTemplates')
    };
  }

  async load() {
    this.isLoading = true;
    try {
      this.home = await getHome();
      this.errorMessage = undefined;
    } catch (error) {
      this.home = undefined;
      this.errorMessage = messageFrom(
        error,
        helpText('CorporateHub', 'CorporateHub_Error_Generic')
      );
    } finally {
      this.isLoading = false;
    }
  }

  decorate(rows) {
    const today = todayIso();
    return (rows || []).map((row) => ({
      ...row,
      href: recordHref(row.recordId || row.id),
      dueText: dueText(row.due, today),
      dueClass: dueState(row.due, today).state === DUE_OVERDUE ? 'slds-text-color_error' : ''
    }));
  }

  get requests() {
    return this.decorate(this.home && this.home.requests);
  }

  get obligations() {
    return this.decorate(this.home && this.home.obligations);
  }

  get agreements() {
    return this.decorate(this.home && this.home.agreements);
  }

  get hasRequests() {
    return this.requests.length > 0;
  }

  get hasObligations() {
    return this.obligations.length > 0;
  }

  get hasAgreements() {
    return this.agreements.length > 0;
  }

  get canManage() {
    return Boolean(this.home && this.home.canManage);
  }

  async handleHaveRead(event) {
    await this.run(
      () => acknowledge({ acknowledgmentId: event.currentTarget.dataset.rowId }),
      () => helpText('CorporateHub', 'CorporateHub_Home_Acknowledged')
    );
  }

  async handleAddTemplates() {
    await this.run(
      () => addMissingTemplates(),
      (added) => helpText('CorporateHub', 'CorporateHub_Home_TemplatesAdded', added || 0)
    );
  }

  /** One server call, then a toast and a fresh page, or the error where the person sees it. */
  async run(call, success) {
    this.isWorking = true;
    try {
      const result = await call();
      this.dispatchEvent(new ShowToastEvent({ message: success(result), variant: 'success' }));
      await this.load();
    } catch (error) {
      this.errorMessage = messageFrom(
        error,
        helpText('CorporateHub', 'CorporateHub_Error_Generic')
      );
    } finally {
      this.isWorking = false;
    }
  }
}
