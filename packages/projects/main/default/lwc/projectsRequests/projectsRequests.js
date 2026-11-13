import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRequests from '@salesforce/apex/ProjectRequestsController.getRequests';
import { messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { VIEWS, decorate, viewOrDefault } from 'c/projectsRequestsModel';

const PKG = 'Projects';

/**
 * The Requests tab (D-201): requests by view (mine, open, unassigned, overdue, recently closed);
 * choosing one opens the request panel beside the list. New Request opens the standard new
 * record page. Off unless Track requests and issues is on.
 */
export default class ProjectsRequests extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Projects_Requests');
  view = VIEWS[0];
  page;
  selectedId;
  isLoading = true;
  errorMessage;

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
      title: helpText('Projects', 'Projects_Requests_Title'),
      intro: helpText('Projects', 'Projects_Requests_Intro'),
      off: helpText('Projects', 'Projects_Requests_Off'),
      empty: helpText('Projects', 'Projects_Requests_Empty'),
      newRequest: helpText('Projects', 'Projects_Requests_New'),
      number: helpText('Projects', 'Projects_Requests_Number'),
      subject: helpText('Projects', 'Projects_Requests_Subject'),
      status: helpText('Projects', 'Projects_Requests_Status'),
      priority: helpText('Projects', 'Projects_Requests_Priority'),
      owner: helpText('Projects', 'Projects_Requests_Owner'),
      due: helpText('Projects', 'Projects_Requests_DueDate'),
      overdue: helpText('Projects', 'Projects_Requests_Overdue')
    };
  }

  get enabled() {
    return this.page?.enabled === true;
  }

  get views() {
    const names = {
      mine: helpText('Projects', 'Projects_Requests_View_Mine'),
      open: helpText('Projects', 'Projects_Requests_View_Open'),
      unassigned: helpText('Projects', 'Projects_Requests_View_Unassigned'),
      overdue: helpText('Projects', 'Projects_Requests_View_Overdue'),
      closed: helpText('Projects', 'Projects_Requests_View_Closed')
    };
    return VIEWS.map((key) => ({
      key,
      label: names[key],
      variant: key === this.view ? 'brand' : 'neutral'
    }));
  }

  get rows() {
    return decorate(this.page?.rows).map((row) => ({
      ...row,
      selected: row.id === this.selectedId
    }));
  }

  get hasRows() {
    return this.rows.length > 0;
  }

  async load() {
    this.isLoading = true;
    try {
      this.page = await getRequests({ view: this.view });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleView(event) {
    this.view = viewOrDefault(event.target.dataset.view);
    this.selectedId = undefined;
    return this.load();
  }

  handleSelect(event) {
    this.selectedId = event.target.dataset.request;
  }

  handleChanged() {
    return this.load();
  }

  handleNew() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Project_Request__c', actionName: 'new' }
    });
  }
}
