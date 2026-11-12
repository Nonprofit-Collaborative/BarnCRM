import { LightningElement } from 'lwc';
import getWeek from '@salesforce/apex/ProjectTimesheetController.getWeek';
import getTasks from '@salesforce/apex/ProjectTimesheetController.getTasks';
import saveWeek from '@salesforce/apex/ProjectTimesheetController.saveWeek';
import submitWeek from '@salesforce/apex/ProjectTimesheetController.submitWeek';
import recallWeek from '@salesforce/apex/ProjectTimesheetController.recallWeek';
import addExpense from '@salesforce/apex/ProjectTimesheetController.addExpense';
import { localIsoDate, messageFrom } from 'c/findCsv';
import { iconFor } from 'c/barnIcons';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import {
  addDays,
  buildGrid,
  cellChanges,
  mondayOf,
  newRow,
  weekDays,
  weekStatus,
  withTotals
} from 'c/projectsTimesheetModel';

const PKG = 'Projects';
const CATEGORIES = ['Travel', 'Lodging', 'Meals', 'Mileage', 'Software', 'Supplies', 'Other'];

/**
 * Timesheet (PM-07, PM-08): a person's week, Monday to Sunday, as a grid of hours for each
 * project and task, with the week's expenses; Save, Submit Week and Recall. The week math and
 * the grid are `c/projectsTimesheetModel`; locks are the entry's own validation rules.
 */
export default class ProjectsTimesheet extends LightningElement {
  helpReady = isHelpLoaded([PKG]);
  icon = iconFor('Projects_Timesheet');
  monday = mondayOf(localIsoDate());
  week;
  extraRows = [];
  edits = {};
  isLoading = true;
  isWorking = false;
  errorMessage;
  notice;
  rowDraft = { billable: true };
  taskOptions = [];
  expense = { billable: false, category: 'Travel' };
  receiptFor;

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
      title: helpText('Projects', 'Projects_Timesheet_Title'),
      intro: helpText('Projects', 'Projects_Timesheet_Intro'),
      off: helpText('Projects', 'Projects_Approvals_Off'),
      previous: helpText('Projects', 'Projects_Timesheet_Previous'),
      thisWeek: helpText('Projects', 'Projects_Timesheet_ThisWeek'),
      next: helpText('Projects', 'Projects_Timesheet_Next'),
      weekOf: helpText('Projects', 'Projects_Timesheet_WeekOf', this.monday),
      project: helpText('Projects', 'Projects_Timesheet_Project'),
      task: helpText('Projects', 'Projects_Timesheet_Task'),
      billable: helpText('Projects', 'Projects_Timesheet_Billable'),
      total: helpText('Projects', 'Projects_Timesheet_Total'),
      addRow: helpText('Projects', 'Projects_Timesheet_AddRow'),
      save: helpText('Projects', 'Projects_Timesheet_Save'),
      submit: helpText('Projects', 'Projects_Timesheet_Submit'),
      recall: helpText('Projects', 'Projects_Timesheet_Recall'),
      noRows: helpText('Projects', 'Projects_Timesheet_NoRows'),
      expensesTitle: helpText('Projects', 'Projects_Timesheet_ExpensesTitle'),
      noExpenses: helpText('Projects', 'Projects_Timesheet_NoExpenses'),
      date: helpText('Projects', 'Projects_Timesheet_Date'),
      category: helpText('Projects', 'Projects_Timesheet_Category'),
      amount: helpText('Projects', 'Projects_Timesheet_Amount'),
      description: helpText('Projects', 'Projects_Timesheet_Description'),
      addExpense: helpText('Projects', 'Projects_Timesheet_AddExpense'),
      receipt: helpText('Projects', 'Projects_Timesheet_Receipt')
    };
  }

  get enabled() {
    return this.week?.enabled === true;
  }

  get expensesEnabled() {
    return this.week?.expensesEnabled === true;
  }

  get days() {
    return weekDays(this.monday);
  }

  /** The saved rows, then the rows added this visit that hold no entry yet. */
  get grid() {
    const saved = buildGrid(this.week?.entries, this.days);
    const known = new Set(saved.rows.map((row) => row.key));
    const added = this.extraRows.filter((row) => !known.has(row.key));
    const grid = withTotals([...saved.rows, ...added], this.days);
    grid.rows = grid.rows.map((row) => ({
      ...row,
      label: row.taskName ? `${row.projectName}: ${row.taskName}` : row.projectName,
      cells: row.cells.map((cell) => ({
        ...cell,
        id: `${row.key}|${cell.iso}`,
        shown: this.edits[`${row.key}|${cell.iso}`] ?? cell.value,
        locked: !cell.editable,
        title: cell.reason || cell.status || '',
        rejected: cell.status === 'Rejected'
      }))
    }));
    grid.dayTotals = grid.dayTotals.map((hours, index) => ({ iso: this.days[index].iso, hours }));
    return grid;
  }

  get hasRows() {
    return this.grid.rows.length > 0;
  }

  get status() {
    return weekStatus(this.week?.entries, this.week?.expenses);
  }

  get cannotSubmit() {
    return this.isWorking || !this.status.canSubmit || this.hasEdits;
  }

  get cannotRecall() {
    return this.isWorking || !this.status.canRecall;
  }

  get hasEdits() {
    return Object.keys(this.edits).length > 0;
  }

  get cannotSave() {
    return this.isWorking || !this.hasEdits;
  }

  get statusLine() {
    const s = this.status;
    return helpText(
      'Projects',
      'Projects_Timesheet_StatusLine',
      s.Open,
      s.Submitted,
      s.Rejected,
      s.Approved
    );
  }

  get projectOptions() {
    return (this.week?.projects || []).map((row) => ({ label: row.Name, value: row.Id }));
  }

  get categoryOptions() {
    return CATEGORIES.map((value) => ({ label: value, value }));
  }

  get expenses() {
    return (this.week?.expenses || []).map((row) => ({
      ...row,
      projectName: row.Project__r?.Name,
      href: `/lightning/r/${row.Id}/view`
    }));
  }

  get hasExpenses() {
    return this.expenses.length > 0;
  }

  async load() {
    this.isLoading = true;
    try {
      this.week = await getWeek({ weekStart: this.monday });
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = messageFrom(error);
    } finally {
      this.isLoading = false;
    }
  }

  async move(monday) {
    this.monday = monday;
    this.edits = {};
    this.extraRows = [];
    this.notice = undefined;
    await this.load();
  }

  handlePrevious() {
    return this.move(addDays(this.monday, -7));
  }

  handleNext() {
    return this.move(addDays(this.monday, 7));
  }

  handleThisWeek() {
    return this.move(mondayOf(localIsoDate()));
  }

  handleCell(event) {
    this.edits = { ...this.edits, [event.target.dataset.cell]: event.target.value };
  }

  handleRowDraft(event) {
    const field = event.target.dataset.field;
    this.rowDraft = {
      ...this.rowDraft,
      [field]: event.target.type === 'checkbox' ? event.target.checked : event.detail.value
    };
  }

  async handleProject(event) {
    this.rowDraft = { ...this.rowDraft, projectId: event.detail.value, taskId: undefined };
    try {
      const tasks = await getTasks({ projectId: event.detail.value });
      this.taskOptions = tasks.map((task) => ({ label: task.Name, value: task.Id }));
    } catch (error) {
      this.errorMessage = messageFrom(error);
    }
  }

  handleAddRow() {
    const d = this.rowDraft;
    const project = (this.week?.projects || []).find((row) => row.Id === d.projectId);
    if (!project) {
      return;
    }
    const task = this.taskOptions.find((option) => option.value === d.taskId);
    this.extraRows = [
      ...this.extraRows,
      newRow(project, task ? { Id: task.value, Name: task.label } : null, d.billable, this.days)
    ];
  }

  /** Runs one action, shows its message or error, then reloads the week. */
  async run(action, message) {
    this.isWorking = true;
    try {
      const result = await action();
      this.notice = message;
      this.errorMessage = undefined;
      await this.load();
      return result;
    } catch (error) {
      this.errorMessage = messageFrom(error);
      return undefined;
    } finally {
      this.isWorking = false;
    }
  }

  async handleSave() {
    const { cells, cleared, invalid } = cellChanges(this.grid.rows, this.edits);
    if (cleared.length || invalid.length) {
      this.errorMessage = cleared.length
        ? helpText('Projects', 'Projects_Timesheet_Cleared')
        : helpText('Projects', 'Projects_Timesheet_Invalid');
      return;
    }
    if (cells.length === 0) {
      this.edits = {};
      return;
    }
    const saved = await this.run(
      () => saveWeek({ cells }),
      helpText('Projects', 'Projects_Timesheet_Saved')
    );
    if (saved !== undefined) {
      this.edits = {};
      this.extraRows = [];
    }
  }

  handleSubmit() {
    return this.run(
      () => submitWeek({ weekStart: this.monday }),
      helpText('Projects', 'Projects_Timesheet_Submitted')
    );
  }

  handleRecall() {
    return this.run(
      () => recallWeek({ weekStart: this.monday }),
      helpText('Projects', 'Projects_Timesheet_Recalled')
    );
  }

  handleExpense(event) {
    const field = event.target.dataset.field;
    this.expense = {
      ...this.expense,
      [field]: event.target.type === 'checkbox' ? event.target.checked : event.detail.value
    };
  }

  async handleAddExpense() {
    const e = this.expense;
    const id = await this.run(
      () =>
        addExpense({
          projectId: e.projectId,
          workDate: e.date || localIsoDate(),
          category: e.category,
          amount: e.amount === undefined || e.amount === '' ? null : Number(e.amount),
          billable: e.billable === true,
          description: e.description
        }),
      helpText('Projects', 'Projects_Timesheet_ExpenseAdded')
    );
    if (id) {
      this.receiptFor = id;
      this.expense = { billable: false, category: 'Travel' };
    }
  }

  handleReceipt() {
    this.receiptFor = undefined;
    this.notice = helpText('Projects', 'Projects_Timesheet_ReceiptSaved');
  }
}
