import { createElement } from 'lwc';
import GrantChecklist from 'c/grantChecklist';
import getChecklist from '@salesforce/apex/GrantManagementController.getChecklist';
import addChecklistTasks from '@salesforce/apex/GrantManagementController.addChecklistTasks';
import setTaskDone from '@salesforce/apex/GrantManagementController.setTaskDone';
import { setHelpTextForTest, clearHelpTextForTest } from 'c/barnHelpText';

import { refreshApex } from '@salesforce/apex';

jest.mock(
  '@salesforce/apex/GrantManagementController.getChecklist',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/GrantManagementController.addChecklistTasks',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/GrantManagementController.setTaskDone',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const TASKS = [
  { id: 'r1', name: 'Draft the narrative', done: true, dueDate: '2027-01-01', assignedTo: 'Ana' },
  { id: 'r2', name: 'Gather the budget', done: false, dueDate: null, assignedTo: null }
];

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(card) {
  const element = createElement('c-grant-checklist', { is: GrantChecklist });
  element.recordId = 'a01000000000001';
  document.body.appendChild(element);
  getChecklist.emit(card);
  await flush();
  return element;
}

describe('c-grant-checklist', () => {
  beforeEach(() => {
    setHelpTextForTest({ Funders_Checklist_Progress: '{0} of {1} done' });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    clearHelpTextForTest();
    jest.clearAllMocks();
  });

  it('shows the tasks with progress and ticks one done', async () => {
    setTaskDone.mockResolvedValue();
    const element = await render({ tasks: TASKS, canEdit: true, canAdd: true });
    expect(element.shadowRoot.querySelector('[data-id="progress"]').textContent).toBe(
      '1 of 2 done'
    );
    const box = element.shadowRoot.querySelector('[data-id="r2"]');
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(setTaskDone).toHaveBeenCalledWith({ requirementId: 'r2', done: true });
    expect(refreshApex).toHaveBeenCalledTimes(1);
  });

  it('shows the load error', async () => {
    const element = createElement('c-grant-checklist', { is: GrantChecklist });
    element.recordId = 'a01000000000001';
    document.body.appendChild(element);
    getChecklist.error({ message: 'No access' });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).toBeNull();
    expect(getChecklist.getLastConfig()).toEqual({ grantId: 'a01000000000001' });
  });

  it('adds the checklist tasks of the grant stage', async () => {
    addChecklistTasks.mockResolvedValue(3);
    const element = await render({ tasks: [], canEdit: true, canAdd: true });
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
    const toasts = jest.fn();
    element.addEventListener('lightning__showtoast', toasts);
    element.shadowRoot.querySelector('[data-id="add"]').click();
    await flush();
    expect(addChecklistTasks).toHaveBeenCalledWith({ grantId: 'a01000000000001' });
    expect(toasts.mock.calls[0][0].detail.message).toBe('c.Funders_Checklist_Added');
  });

  it('locks the boxes and hides Add for a reader', async () => {
    const element = await render({ tasks: TASKS, canEdit: false, canAdd: false });
    expect(element.shadowRoot.querySelector('[data-id="r1"]').disabled).toBe(true);
    expect(element.shadowRoot.querySelector('[data-id="add"]')).toBeNull();
  });
});
