import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getHome from '@salesforce/apex/ProjectsController.getHome';
import setTaskStatus from '@salesforce/apex/ProjectsController.setTaskStatus';
import createFromTemplate from '@salesforce/apex/ProjectsController.createFromTemplate';
import getUtilization from '@salesforce/apex/ProjectsController.getUtilization';
import exportBillable from '@salesforce/apex/ProjectsController.exportBillable';
import applyRates from '@salesforce/apex/ProjectsController.applyRates';
import { fileName, localIsoDate, messageFrom, toCsv } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { BILLABLE_COLUMNS, utilizationRows } from 'c/projectsModel';

const PKG = 'Projects';

/** Monday of this week, in the person's own day, as YYYY-MM-DD. */
function weekStart(today = new Date()) {
  const day = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  day.setDate(day.getDate() - ((day.getDay() + 6) % 7));
  return localIsoDate(day);
}

/**
 * Projects Home (PM-02 to PM-05): the Projects at Risk card, my open tasks with Done, New
 * Project From Template, and, with time tracking on, utilization by person and (Manage
 * Projects) Export Billable Time as a CSV built here with Core's `c/findCsv`.
 */
export default class ProjectsHome extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Projects_Home');
  home;
  isLoading = true;
  isWorking = false;
  errorMessage;
  notice;
  draft = {};
  fromDate;
  toDate;
  utilization;
  includeExported = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp([PKG]).then(() => {
        this.helpReady = true;
      });
    }
    this.fromDate = weekStart();
    this.toDate = localIsoDate();
    this.draft = { startDate: localIsoDate() };
    this.load();
  }

  get labels() {
    return {
      title: helpText('Projects', 'Projects_Home_Title'),
      intro: helpText('Projects', 'Projects_Home_Intro'),
      myTasks: helpText('Projects', 'Projects_Home_MyTasks'),
      noTasks: helpText('Projects', 'Projects_Home_NoTasks'),
      done: helpText('Projects', 'Projects_Home_Done'),
      newTitle: helpText('Projects', 'Projects_Home_NewTitle'),
      template: helpText('Projects', 'Projects_Home_Template'),
      name: helpText('Projects', 'Projects_Home_Name'),
      start: helpText('Projects', 'Projects_Home_Start'),
      client: helpText('Projects', 'Projects_Home_Client'),
      contact: helpText('Projects', 'Projects_Home_Contact'),
      create: helpText('Projects', 'Projects_Home_Create'),
      utilization: helpText('Projects', 'Projects_Home_Utilization'),
      from: helpText('Projects', 'Projects_Home_From'),
      to: helpText('Projects', 'Projects_Home_To'),
      show: helpText('Projects', 'Projects_Home_Show'),
      person: helpText('Projects', 'Projects_Home_Person'),
      logged: helpText('Projects', 'Projects_Home_Logged'),
      billable: helpText('Projects', 'Projects_Home_Billable'),
      planned: helpText('Projects', 'Projects_Home_Planned'),
      capacity: helpText('Projects', 'Projects_Home_Capacity'),
      used: helpText('Projects', 'Projects_Home_Used'),
      noTime: helpText('Projects', 'Projects_Home_NoTime'),
      exportTitle: helpText('Projects', 'Projects_Export_Title'),
      includeExported: helpText('Projects', 'Projects_Export_Include'),
      exportButton: helpText('Projects', 'Projects_Export_Button'),
      applyRates: helpText('Projects', 'Projects_Rates_Apply')
    };
  }

  get ratesEnabled() {
    return this.home?.ratesEnabled === true;
  }

  async handleApplyRates() {
    this.isWorking = true;
    try {
      const count = await applyRates();
      this.notice = helpText('Projects', 'Projects_Rates_Applied', count);
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }

  get canManage() {
    return this.home?.canManage === true;
  }

  get timeTracking() {
    return this.home?.timeTracking === true;
  }

  get templateOptions() {
    return (this.home?.templates || []).map((row) => ({ label: row.name, value: row.key }));
  }

  get tasks() {
    return (this.home?.myTasks || []).map((row) => ({
      ...row,
      href: `/lightning/r/${row.id}/view`,
      projectHref: `/lightning/r/${row.projectId}/view`
    }));
  }

  get hasTasks() {
    return this.tasks.length > 0;
  }

  get people() {
    return utilizationRows(this.utilization);
  }

  get hasPeople() {
    return this.people.length > 0;
  }

  async load() {
    this.isLoading = true;
    try {
      this.home = await getHome();
      this.errorMessage = undefined;
      if (this.timeTracking && this.utilization === undefined) {
        await this.handleShow();
      }
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isLoading = false;
    }
  }

  handleDraft(event) {
    const field = event.target.dataset.field;
    this.draft = {
      ...this.draft,
      [field]: event.detail?.recordId ?? event.detail?.value ?? event.target.value
    };
  }

  async handleCreate() {
    this.isWorking = true;
    try {
      const d = this.draft;
      const projectId = await createFromTemplate({
        templateKey: d.templateKey,
        name: d.name,
        startDate: d.startDate,
        accountId: d.accountId || null,
        contactId: d.contactId || null
      });
      this.errorMessage = undefined;
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: { recordId: projectId, actionName: 'view' }
      });
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }

  async handleDone(event) {
    this.isWorking = true;
    try {
      await setTaskStatus({ taskId: event.target.dataset.task, status: 'Done' });
      this.notice = helpText('Projects', 'Projects_Home_Marked');
      await this.load();
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }

  handleRange(event) {
    this[event.target.dataset.field] =
      event.target.type === 'checkbox' ? event.target.checked : event.target.value;
  }

  async handleShow() {
    try {
      this.utilization = await getUtilization({ fromDate: this.fromDate, toDate: this.toDate });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  async handleExport() {
    this.isWorking = true;
    try {
      const rows = await exportBillable({
        fromDate: this.fromDate,
        toDate: this.toDate,
        includeExported: this.includeExported
      });
      const link = document.createElement('a');
      link.href =
        'data:text/csv;charset=utf-8,' + encodeURIComponent(toCsv(BILLABLE_COLUMNS, rows));
      link.download = fileName('billable_time');
      link.click();
      this.notice = helpText('Projects', 'Projects_Export_Done', rows.length);
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isWorking = false;
    }
  }
}
