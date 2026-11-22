import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { updateRecord } from 'lightning/uiRecordApi';
import PROJECT from '@salesforce/schema/Project__c';
import PROJECT_TASK from '@salesforce/schema/Project_Task__c';
import TASK_STATUS_FIELD from '@salesforce/schema/Project_Task__c.Status__c';
import TASK_COMPLETED_DATE_FIELD from '@salesforce/schema/Project_Task__c.Completed_Date__c';
import PROJECT_REQUEST from '@salesforce/schema/Project_Request__c';
import TIME_ENTRY from '@salesforce/schema/Time_Entry__c';
import getHome from '@salesforce/apex/ProjectsController.getHome';
import createFromTemplate from '@salesforce/apex/ProjectsController.createFromTemplate';
import getUtilization from '@salesforce/apex/ProjectsController.getUtilization';
import exportBillable from '@salesforce/apex/ProjectsController.exportBillable';
import applyRates from '@salesforce/apex/ProjectsController.applyRates';
import { fileName, localIsoDate, messageFrom, recordErrorMessage, toCsv } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { BILLABLE_COLUMNS, completedDateFor, utilizationRows } from 'c/projectsModel';

const PKG = 'Projects';

/** Monday of this week, in the person's own day, as YYYY-MM-DD. */
function weekStart(today = new Date()) {
  const day = new Date(today.getFullYear(), today.getMonth(), today.getDate());
  day.setDate(day.getDate() - ((day.getDay() + 6) % 7));
  return localIsoDate(day);
}

/** An object's list, from its schema import so the name carries any namespace. */
function listHref(schema) {
  return `/lightning/o/${schema.objectApiName}/list`;
}

/**
 * Projects Home (PM-02 to PM-05): New Project for whoever may create one, the figures row
 * (active projects, my open tasks, open requests with Requests on, hours this month with time
 * tracking on), the Projects at Risk card, my open tasks with Done, New Project From Template,
 * and, with time tracking on, utilization by person and (Manage Projects) Export Billable Time
 * as a CSV built here with Core's `c/findCsv`.
 */
export default class ProjectsHome extends NavigationMixin(LightningElement) {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Projects_Home');
  canCreate = false;
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
      applyRates: helpText('Projects', 'Projects_Rates_Apply'),
      firstRunHeading: helpText('Projects', 'Projects_Home_FirstRunHeading'),
      firstRunMessage: helpText('Projects', 'Projects_Home_FirstRunMessage'),
      firstRunStart: helpText('Projects', 'Projects_Home_FirstRunStart'),
      newProject: helpText('Projects', 'Projects_Home_NewProject')
    };
  }

  /** New Project shows only to someone who may create projects. */
  @wire(getObjectInfo, { objectApiName: PROJECT })
  receiveProjectInfo({ data }) {
    this.canCreate = Boolean(data && data.createable);
  }

  handleNewProject() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: { objectApiName: PROJECT.objectApiName, actionName: 'new' }
    });
  }

  /** True before the org's first project, for someone who may create one (D-200 R4). */
  get firstRun() {
    return this.home?.firstRun === true;
  }

  get showTiles() {
    return Boolean(this.home) && !this.firstRun;
  }

  /** The figures row (Module Home pattern), each a link to the list behind it. */
  get tiles() {
    const figures = this.home?.figures || {};
    const tiles = [
      {
        key: 'active',
        label: helpText('Projects', 'Projects_Home_FigureActive'),
        value: figures.active,
        href: listHref(PROJECT)
      },
      {
        key: 'tasks',
        label: helpText('Projects', 'Projects_Home_FigureMyTasks'),
        value: this.tasks.length,
        href: listHref(PROJECT_TASK)
      },
      {
        key: 'requests',
        label: helpText('Projects', 'Projects_Home_FigureRequests'),
        value: figures.requests,
        href: listHref(PROJECT_REQUEST)
      },
      {
        key: 'hours',
        label: helpText('Projects', 'Projects_Home_FigureHours'),
        value: figures.hours,
        href: listHref(TIME_ENTRY)
      }
    ];
    // A figure the server left out (a module setting off, or no access) gets no tile.
    return tiles.filter((tile) => typeof tile.value === 'number');
  }

  /** The first-run action: the New Project From Template form is on this page, so go to it. */
  handleStartFirst() {
    const template = this.template.querySelector('[data-id="template"]');
    if (template) {
      template.scrollIntoView?.({ behavior: 'smooth', block: 'center' });
      template.focus();
    }
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
      // Marked Done as the user through Lightning Data Service (ADR-0093 A2; R-PM4).
      await updateRecord({
        fields: {
          Id: event.target.dataset.task,
          [TASK_STATUS_FIELD.fieldApiName]: 'Done',
          [TASK_COMPLETED_DATE_FIELD.fieldApiName]: completedDateFor('Done', localIsoDate())
        }
      });
      this.notice = helpText('Projects', 'Projects_Home_Marked');
      await this.load();
    } catch (error) {
      this.errorMessage = recordErrorMessage(error);
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
