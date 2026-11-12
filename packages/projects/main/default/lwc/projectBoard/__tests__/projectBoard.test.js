import { createElement } from 'lwc';
import ProjectBoard from 'c/projectBoard';
import getBoard from '@salesforce/apex/ProjectsController.getBoard';
import setTaskStatus from '@salesforce/apex/ProjectsController.setTaskStatus';
import addTask from '@salesforce/apex/ProjectsController.addTask';
import logTime from '@salesforce/apex/ProjectsController.logTime';
import refreshHealth from '@salesforce/apex/ProjectsController.refreshHealth';
import addExpense from '@salesforce/apex/ProjectTimesheetController.addExpense';
import { setHelpTextForTest } from 'c/barnHelpText';

jest.mock(
  '@salesforce/apex/ProjectTimesheetController.addExpense',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock('@salesforce/apex/ProjectsController.getBoard', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectsController.setTaskStatus', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectsController.addTask', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectsController.logTime', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectsController.refreshHealth', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectsController.draftStatusUpdate', () => ({ default: jest.fn() }), {
  virtual: true
});

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

const BOARD = {
  timeTracking: true,
  canCreateTime: true,
  canCreateExpense: true,
  project: {
    Id: 'a01000000000001AAA',
    Health__c: 'At Risk',
    Health_Reasons__c: 'Data mapping was due 1/1/2027.',
    Start_Date__c: '2027-01-01',
    Target_Date__c: '2027-01-10',
    Tasks__c: 2,
    Tasks_Done__c: 1,
    Actual_Hours__c: 4,
    Estimated_Hours__c: 20,
    Budget_Hours__c: 30
  },
  phases: [
    {
      Id: 'a02000000000001AAA',
      Name: 'Build',
      Start_Date__c: '2027-01-01',
      End_Date__c: '2027-01-05'
    }
  ],
  tasks: [
    {
      Id: 'a03000000000001AAA',
      Name: 'Configure',
      Phase__c: 'a02000000000001AAA',
      Status__c: 'Done'
    },
    {
      Id: 'a03000000000002AAA',
      Name: 'Go-Live',
      Phase__c: 'a02000000000001AAA',
      Status__c: 'Not Started',
      Milestone__c: true
    }
  ]
};

function mount() {
  const element = createElement('c-project-board', { is: ProjectBoard });
  element.recordId = 'a01000000000001AAA';
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-project-board', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws health, progress, the phase and its tasks, and changes a status', async () => {
    getBoard.mockResolvedValue(BOARD);
    setTaskStatus.mockResolvedValue();
    const element = mount();
    await flush();
    expect(find(element, 'health').textContent).toContain('At Risk');
    expect(find(element, 'health').textContent).toContain('Data mapping');
    expect(element.shadowRoot.querySelectorAll('[data-id="phase"]')).toHaveLength(1);
    expect(element.shadowRoot.querySelectorAll('[data-id="task"]')).toHaveLength(2);
    expect(element.shadowRoot.querySelector('.bar').getAttribute('style')).toContain('width: 50%');
    const status = element.shadowRoot.querySelector(
      'lightning-combobox[data-task="a03000000000002AAA"]'
    );
    status.dispatchEvent(new CustomEvent('change', { detail: { value: 'Done' } }));
    await flush();
    expect(setTaskStatus).toHaveBeenCalledWith({ taskId: 'a03000000000002AAA', status: 'Done' });
    find(element, 'refresh').click();
    await flush();
    expect(refreshHealth).toHaveBeenCalledWith({ projectId: 'a01000000000001AAA' });
  });

  it('adds a task and logs time, and shows a refusal', async () => {
    getBoard.mockResolvedValue(BOARD);
    addTask.mockResolvedValue('a03000000000003AAA');
    logTime.mockRejectedValue({ body: { message: 'Enter more than 0 and at most 24 hours.' } });
    const element = mount();
    await flush();
    find(element, 'add-task').click();
    await flush();
    const name = element.shadowRoot.querySelector(
      '[data-id="task-form"] lightning-input[data-field="name"]'
    );
    name.value = 'Reports';
    name.dispatchEvent(new CustomEvent('change'));
    find(element, 'save-task').click();
    await flush();
    expect(addTask).toHaveBeenCalledWith(
      expect.objectContaining({ phaseId: 'a02000000000001AAA', name: 'Reports' })
    );
    find(element, 'log-time').click();
    await flush();
    find(element, 'save-time').click();
    await flush();
    await flush();
    expect(logTime).toHaveBeenCalledWith(
      expect.objectContaining({ projectId: 'a01000000000001AAA', billable: false })
    );
    expect(find(element, 'error-message').message).toBe('Enter more than 0 and at most 24 hours.');
  });

  it('shows Add Expense only when expenses are on and adds one', async () => {
    getBoard.mockResolvedValue(BOARD);
    let element = mount();
    await flush();
    expect(find(element, 'add-expense')).toBeNull();
    document.body.removeChild(element);

    getBoard.mockResolvedValue({ ...BOARD, expensesEnabled: true });
    addExpense.mockResolvedValue('a09000000000001AAA');
    element = mount();
    await flush();
    find(element, 'add-expense').click();
    await flush();
    const amount = element.shadowRoot.querySelector(
      '[data-id="expense-form"] lightning-input[data-field="amount"]'
    );
    amount.value = '42.5';
    amount.dispatchEvent(new CustomEvent('change'));
    find(element, 'save-expense').click();
    await flush();
    expect(addExpense).toHaveBeenCalledWith(
      expect.objectContaining({
        projectId: 'a01000000000001AAA',
        amount: 42.5,
        category: 'Travel',
        billable: false
      })
    );
    expect(find(element, 'expense-form')).toBeNull();
  });

  it('hides Log Time and the hours when time tracking is off', async () => {
    getBoard.mockResolvedValue({ ...BOARD, timeTracking: false });
    const element = mount();
    await flush();
    expect(find(element, 'log-time')).toBeNull();
    expect(find(element, 'hours')).toBeNull();
  });

  it('hides Log Time and Add Expense from someone who cannot create them', async () => {
    getBoard.mockResolvedValue({
      ...BOARD,
      expensesEnabled: true,
      canCreateTime: false,
      canCreateExpense: false
    });
    const element = mount();
    await flush();
    expect(find(element, 'log-time')).toBeNull();
    expect(find(element, 'add-expense')).toBeNull();
    expect(find(element, 'hours')).not.toBeNull();
  });

  it('adds approved change hours to the budget (R-PM20)', async () => {
    setHelpTextForTest({ Projects_Board_HoursLine: 'Budget: {2} hours' });
    getBoard.mockResolvedValue({ ...BOARD, project: { ...BOARD.project, Change_Hours__c: 10 } });
    const element = mount();
    await flush();
    expect(find(element, 'hours').textContent).toContain('Budget: 40 hours');
  });
});
