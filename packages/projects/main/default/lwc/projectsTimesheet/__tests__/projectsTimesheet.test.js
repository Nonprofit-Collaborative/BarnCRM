import { createElement } from 'lwc';
import ProjectsTimesheet from 'c/projectsTimesheet';
import getWeek from '@salesforce/apex/ProjectTimesheetController.getWeek';
import getTasks from '@salesforce/apex/ProjectTimesheetController.getTasks';
import saveWeek from '@salesforce/apex/ProjectTimesheetController.saveWeek';
import submitWeek from '@salesforce/apex/ProjectTimesheetController.submitWeek';
import recallWeek from '@salesforce/apex/ProjectTimesheetController.recallWeek';
import addExpense from '@salesforce/apex/ProjectTimesheetController.addExpense';

jest.mock('@salesforce/apex/ProjectTimesheetController.getWeek', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectTimesheetController.getTasks', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectTimesheetController.saveWeek', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ProjectTimesheetController.submitWeek',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ProjectTimesheetController.recallWeek',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ProjectTimesheetController.addExpense',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

const entry = (id, date, hours, status) => ({
  Id: id,
  Project__c: 'a01000000000001AAA',
  Project__r: { Name: 'Rollout' },
  Task__c: 'a03000000000001AAA',
  Task__r: { Name: 'Build' },
  Billable__c: true,
  Date__c: date,
  Hours__c: hours,
  Status__c: status
});

const WEEK = (status = 'Open') => ({
  enabled: true,
  expensesEnabled: true,
  entries: [entry('e1', '2026-11-09', 4, status), entry('e2', '2026-11-10', 3, status)],
  expenses: [],
  projects: [{ Id: 'a01000000000001AAA', Name: 'Rollout' }]
});

function mount() {
  const element = createElement('c-projects-timesheet', { is: ProjectsTimesheet });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const all = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('c-projects-timesheet', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says the page is off when approvals are off and draws no grid', async () => {
    getWeek.mockResolvedValue({ enabled: false, entries: [], expenses: [], projects: [] });
    const element = mount();
    await flush();
    expect(find(element, 'off')).not.toBeNull();
    expect(find(element, 'grid')).toBeNull();
  });

  it('draws the week with totals, saves an edited cell and submits', async () => {
    getWeek.mockResolvedValue(WEEK());
    saveWeek.mockResolvedValue(1);
    submitWeek.mockResolvedValue(2);
    const element = mount();
    await flush();
    expect(all(element, 'row')).toHaveLength(1);
    expect(find(element, 'week-total').textContent).toBe('7');
    expect(find(element, 'save').disabled).toBe(true);
    expect(find(element, 'submit').disabled).toBe(false);

    const cell = all(element, 'cell')[0];
    cell.value = '5';
    cell.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(find(element, 'save').disabled).toBe(false);
    expect(find(element, 'submit').disabled).toBe(true);
    find(element, 'save').click();
    await flush();
    expect(saveWeek).toHaveBeenCalledWith({
      cells: [expect.objectContaining({ id: 'e1', hours: 5, workDate: '2026-11-09' })]
    });
    find(element, 'submit').click();
    await flush();
    expect(submitWeek).toHaveBeenCalledWith({
      weekStart: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/)
    });
  });

  it('locks submitted cells, recalls, and refuses to empty a cell', async () => {
    getWeek.mockResolvedValue(WEEK('Submitted'));
    recallWeek.mockResolvedValue(2);
    const element = mount();
    await flush();
    expect(all(element, 'cell')[0].disabled).toBe(true);
    expect(find(element, 'recall').disabled).toBe(false);
    find(element, 'recall').click();
    await flush();
    expect(recallWeek).toHaveBeenCalled();

    getWeek.mockResolvedValue(WEEK());
    find(element, 'this-week').click();
    await flush();
    const cell = all(element, 'cell')[0];
    cell.value = '';
    cell.dispatchEvent(new CustomEvent('change'));
    await flush();
    find(element, 'save').click();
    await flush();
    expect(saveWeek).not.toHaveBeenCalled();
    expect(find(element, 'error-message').message).toBe('c.Projects_Timesheet_Cleared');
  });

  it('adds a row for a project and task and adds an expense', async () => {
    getWeek.mockResolvedValue({ ...WEEK(), entries: [] });
    getTasks.mockResolvedValue([{ Id: 'a03000000000001AAA', Name: 'Build' }]);
    addExpense.mockResolvedValue('a09000000000001AAA');
    const element = mount();
    await flush();
    find(element, 'row-project').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'a01000000000001AAA' } })
    );
    await flush();
    expect(getTasks).toHaveBeenCalledWith({ projectId: 'a01000000000001AAA' });
    find(element, 'add-row-button').click();
    await flush();
    expect(all(element, 'row')).toHaveLength(1);

    const form = find(element, 'expense-form');
    const set = (field, value) => {
      const input = form.querySelector(`[data-field="${field}"]`);
      input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
    };
    set('projectId', 'a01000000000001AAA');
    set('amount', '12.5');
    find(element, 'add-expense').click();
    await flush();
    expect(addExpense).toHaveBeenCalledWith(
      expect.objectContaining({
        projectId: 'a01000000000001AAA',
        amount: 12.5,
        category: 'Travel',
        billable: false
      })
    );
    expect(find(element, 'receipt')).not.toBeNull();
  });
});
