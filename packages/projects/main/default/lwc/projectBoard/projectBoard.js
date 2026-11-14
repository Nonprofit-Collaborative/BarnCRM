import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getBoard from '@salesforce/apex/ProjectsController.getBoard';
import setTaskStatus from '@salesforce/apex/ProjectsController.setTaskStatus';
import addTask from '@salesforce/apex/ProjectsController.addTask';
import logTime from '@salesforce/apex/ProjectsController.logTime';
import addExpense from '@salesforce/apex/ProjectTimesheetController.addExpense';
import refreshHealth from '@salesforce/apex/ProjectsController.refreshHealth';
import draftStatusUpdate from '@salesforce/apex/ProjectsController.draftStatusUpdate';
import { localIsoDate, messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { bar, groupTasks, isOpen, percent, timelineSpan, todayMark } from 'c/projectsModel';

const PKG = 'Projects';
const STATUSES = ['Not Started', 'In Progress', 'Blocked', 'Done', 'Cancelled'];
const HEALTH_CLASS = {
  'On Track': 'slds-theme_success',
  'At Risk': 'slds-theme_warning',
  'Off Track': 'slds-theme_error'
};

/**
 * The project board (PM-02 to PM-05): health with its reasons and Refresh Health, progress and,
 * with time tracking on, hours and budget; each phase on the timeline with its tasks, a status
 * menu per task and Add Task; Log Time; and Draft Status Update, which opens the new update.
 */
export default class ProjectBoard extends NavigationMixin(LightningElement) {
  @api recordId;
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Project__c');
  board;
  isWorking = false;
  errorMessage;
  notice;
  addingPhase;
  newTask = {};
  logging = false;
  entry = {};
  spending = false;
  expense = {};

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
      title: helpText('Projects', 'Projects_Board_Title'),
      refresh: helpText('Projects', 'Projects_Board_Refresh'),
      draft: helpText('Projects', 'Projects_Board_Draft'),
      logTime: helpText('Projects', 'Projects_Board_LogTime'),
      noHealth: helpText('Projects', 'Projects_Board_NoHealth'),
      timeline: helpText('Projects', 'Projects_Board_Timeline'),
      noPhase: helpText('Projects', 'Projects_Board_NoPhase'),
      noTasks: helpText('Projects', 'Projects_Board_NoTasks'),
      addTask: helpText('Projects', 'Projects_Board_AddTask'),
      taskName: helpText('Projects', 'Projects_Board_TaskName'),
      dueDate: helpText('Projects', 'Projects_Board_DueDate'),
      milestone: helpText('Projects', 'Projects_Board_Milestone'),
      status: helpText('Projects', 'Projects_Board_Status'),
      date: helpText('Projects', 'Projects_Board_Date'),
      hours: helpText('Projects', 'Projects_Board_Hours'),
      task: helpText('Projects', 'Projects_Board_Task'),
      billable: helpText('Projects', 'Projects_Board_Billable'),
      notes: helpText('Projects', 'Projects_Board_Notes'),
      save: helpText('Projects', 'Projects_Board_Save'),
      cancel: helpText('Projects', 'Projects_Board_Cancel'),
      today: helpText('Projects', 'Projects_Board_Today'),
      addExpense: helpText('Projects', 'Projects_Expense_Add'),
      category: helpText('Projects', 'Projects_Expense_Category'),
      amount: helpText('Projects', 'Projects_Expense_Amount'),
      description: helpText('Projects', 'Projects_Expense_Description')
    };
  }

  // Add Expense and Log Time show only to someone who may create those records.
  get expensesEnabled() {
    return (
      this.timeTracking &&
      this.board?.expensesEnabled === true &&
      this.board?.canCreateExpense === true
    );
  }

  get canLogTime() {
    return this.timeTracking && this.board?.canCreateTime === true;
  }

  get categoryOptions() {
    return ['Travel', 'Lodging', 'Meals', 'Mileage', 'Software', 'Supplies', 'Other'].map(
      (value) => ({ label: value, value })
    );
  }

  get project() {
    return this.board?.project || {};
  }

  get healthClass() {
    return `slds-badge ${HEALTH_CLASS[this.project.health] || ''}`;
  }

  get healthLabel() {
    return this.project.health || this.labels.noHealth;
  }

  get reasons() {
    return (this.project.healthReasons || '').split('\n').filter((line) => line);
  }

  get progressPercent() {
    return percent(this.project.tasksDone, this.project.taskCount);
  }

  get progressText() {
    return helpText(
      'Projects',
      'Projects_Board_Progress',
      this.project.tasksDone || 0,
      this.project.taskCount || 0,
      this.progressPercent
    );
  }

  get timeTracking() {
    return this.board?.timeTracking === true;
  }

  get hoursText() {
    const p = this.project;
    const hasBudget = p.budgetHours !== undefined && p.budgetHours !== null;
    // R-PM20: approved change requests add their hours to the budget.
    const budget = hasBudget ? p.budgetHours + (p.changeHours || 0) : '-';
    return helpText(
      'Projects',
      'Projects_Board_HoursLine',
      p.actualHours || 0,
      p.estimatedHours || 0,
      budget
    );
  }

  get hasBudgetAmount() {
    return this.project.budgetAmount !== undefined && this.project.budgetAmount !== null;
  }

  get span() {
    return timelineSpan(this.project, this.board?.phases);
  }

  get todayStyle() {
    const mark = todayMark(this.span);
    return mark === null ? null : `left: ${mark}%`;
  }

  get groups() {
    const span = this.span;
    return groupTasks(this.board?.phases, this.board?.tasks).map((group) => {
      const place = bar(group, span);
      return {
        ...group,
        key: group.id || 'none',
        name: group.name || this.labels.noPhase,
        barStyle: place ? `left: ${place.left}%; width: ${place.width}%` : null,
        isAdding: this.addingPhase === (group.id || 'none'),
        hasTasks: group.tasks.length > 0,
        tasks: group.tasks.map((task) => ({
          ...task,
          href: `/lightning/r/${task.id}/view`,
          owner: task.assignedToName,
          late: isOpen(task) && task.dueDate && task.dueDate < localIsoDate(),
          options: STATUSES.map((value) => ({ label: value, value }))
        }))
      };
    });
  }

  get taskOptions() {
    return [{ label: '', value: '' }].concat(
      (this.board?.tasks || []).filter(isOpen).map((task) => ({ label: task.name, value: task.id }))
    );
  }

  async load() {
    try {
      this.board = await getBoard({ projectId: this.recordId });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  async run(work, noticeText) {
    this.isWorking = true;
    this.notice = undefined;
    try {
      const result = await work();
      this.errorMessage = undefined;
      this.notice = noticeText;
      await this.load();
      return result;
    } catch (error) {
      this.errorMessage = messageFrom(error);
      return undefined;
    } finally {
      this.isWorking = false;
    }
  }

  handleStatus(event) {
    const taskId = event.target.dataset.task;
    const status = event.detail.value;
    this.run(() => setTaskStatus({ taskId, status }));
  }

  handleRefresh() {
    this.run(
      () => refreshHealth({ projectId: this.recordId }),
      helpText('Projects', 'Projects_Board_Refreshed')
    );
  }

  async handleDraft() {
    const updateId = await this.run(
      () => draftStatusUpdate({ projectId: this.recordId }),
      helpText('Projects', 'Projects_Board_Drafted')
    );
    if (updateId) {
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: { recordId: updateId, actionName: 'view' }
      });
    }
  }

  handleStartAdd(event) {
    this.addingPhase = event.target.dataset.phase;
    this.newTask = { milestone: false };
  }

  handleNewTask(event) {
    const field = event.target.dataset.field;
    this.newTask = {
      ...this.newTask,
      [field]: event.target.type === 'checkbox' ? event.target.checked : event.target.value
    };
  }

  async handleSaveTask() {
    const phaseId = this.addingPhase === 'none' ? null : this.addingPhase;
    const saved = await this.run(() =>
      addTask({
        projectId: this.recordId,
        phaseId,
        name: this.newTask.name,
        dueDate: this.newTask.due || null,
        milestone: this.newTask.milestone === true
      })
    );
    if (saved) {
      this.addingPhase = undefined;
    }
  }

  handleCancel() {
    this.addingPhase = undefined;
    this.logging = false;
    this.spending = false;
  }

  handleStartExpense() {
    this.spending = true;
    this.expense = { date: localIsoDate(), category: 'Travel', billable: false };
  }

  handleExpense(event) {
    const field = event.target.dataset.field;
    const value =
      event.target.type === 'checkbox'
        ? event.target.checked
        : (event.detail?.value ?? event.target.value);
    this.expense = { ...this.expense, [field]: value };
  }

  async handleSaveExpense() {
    const e = this.expense;
    const saved = await this.run(
      () =>
        addExpense({
          projectId: this.recordId,
          workDate: e.date,
          category: e.category,
          amount: e.amount === undefined || e.amount === '' ? null : Number(e.amount),
          billable: e.billable === true,
          description: e.description
        }),
      helpText('Projects', 'Projects_Timesheet_ExpenseAdded')
    );
    if (saved) {
      this.spending = false;
    }
  }

  handleStartLog() {
    this.logging = true;
    this.entry = { date: localIsoDate(), hours: null, taskId: '', billable: false, notes: '' };
  }

  handleEntry(event) {
    const field = event.target.dataset.field;
    const value =
      event.target.type === 'checkbox'
        ? event.target.checked
        : (event.detail?.value ?? event.target.value);
    this.entry = { ...this.entry, [field]: value };
  }

  async handleSaveTime() {
    const e = this.entry;
    const saved = await this.run(
      () =>
        logTime({
          projectId: this.recordId,
          taskId: e.taskId || null,
          workDate: e.date,
          hours: e.hours === null || e.hours === '' ? null : Number(e.hours),
          billable: e.billable === true,
          notes: e.notes
        }),
      // With approvals on a new entry is Open until the week is submitted (R-PM11).
      this.board?.approvalsEnabled
        ? helpText('Projects', 'Projects_Board_TimeLoggedOpen')
        : helpText('Projects', 'Projects_Board_TimeLogged')
    );
    if (saved) {
      this.logging = false;
    }
  }
}
