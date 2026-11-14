import { createElement } from 'lwc';
import ProjectsHome from 'c/projectsHome';
import getHome from '@salesforce/apex/ProjectsController.getHome';
import setTaskStatus from '@salesforce/apex/ProjectsController.setTaskStatus';
import createFromTemplate from '@salesforce/apex/ProjectsController.createFromTemplate';
import getUtilization from '@salesforce/apex/ProjectsController.getUtilization';
import exportBillable from '@salesforce/apex/ProjectsController.exportBillable';
import applyRates from '@salesforce/apex/ProjectsController.applyRates';

jest.mock('@salesforce/apex/ProjectsController.applyRates', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/ProjectsController.getHome', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectsController.setTaskStatus', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ProjectsController.createFromTemplate',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/ProjectsController.getUtilization', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectsController.exportBillable', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ProjectsController.getAtRisk',
  () => ({ default: jest.fn().mockResolvedValue([]) }),
  { virtual: true }
);

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

const HOME = {
  canManage: true,
  timeTracking: true,
  templates: [
    { key: 'salesforce_implementation', name: 'Salesforce Implementation', shipped: true }
  ],
  myTasks: [
    {
      id: 'a03000000000001AAA',
      name: 'Interviews',
      projectId: 'a01000000000001AAA',
      projectName: 'Rollout'
    }
  ]
};

function mount() {
  const element = createElement('c-projects-home', { is: ProjectsHome });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-projects-home', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers to start the first project, and goes to the template form', async () => {
    getHome.mockResolvedValue({ ...HOME, timeTracking: false, myTasks: [], firstRun: true });
    const element = mount();
    await flush();

    const panel = find(element, 'first-run');
    expect(panel).not.toBeNull();
    expect(panel.heading).toBe('c.Projects_Home_FirstRunHeading');
    const template = find(element, 'template');
    template.focus = jest.fn();
    find(element, 'first-run-start').click();
    expect(template.focus).toHaveBeenCalled();
  });

  it('leaves the first-run panel out once a project exists', async () => {
    getHome.mockResolvedValue({ ...HOME, timeTracking: false });
    const element = mount();
    await flush();
    expect(find(element, 'first-run')).toBeNull();
  });

  it('lists my tasks and utilization, marks a task done and creates from a template', async () => {
    getHome.mockResolvedValue(HOME);
    getUtilization.mockResolvedValue([
      {
        userId: '005000000000001AAA',
        name: 'Ann',
        logged: 20,
        billable: 10,
        planned: 16,
        capacity: 40
      }
    ]);
    setTaskStatus.mockResolvedValue();
    createFromTemplate.mockResolvedValue('a01000000000002AAA');
    const element = mount();
    await flush();
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="task"]')).toHaveLength(1);
    expect(find(element, 'person').textContent).toContain('50%');
    find(element, 'done').click();
    await flush();
    expect(setTaskStatus).toHaveBeenCalledWith({ taskId: 'a03000000000001AAA', status: 'Done' });
    find(element, 'template').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'salesforce_implementation' } })
    );
    find(element, 'create').click();
    await flush();
    expect(createFromTemplate).toHaveBeenCalledWith(
      expect.objectContaining({ templateKey: 'salesforce_implementation', accountId: null })
    );
  });

  it('exports billable time for a manager', async () => {
    getHome.mockResolvedValue(HOME);
    getUtilization.mockResolvedValue([]);
    exportBillable.mockResolvedValue([{ entry: 'TE-1', hours: 4, amount: 400 }]);
    const element = mount();
    await flush();
    await flush();
    find(element, 'export-button').click();
    await flush();
    expect(exportBillable).toHaveBeenCalledWith(
      expect.objectContaining({ includeExported: false })
    );
    expect(find(element, 'notice')).not.toBeNull();
  });

  it('shows Apply Rates to a manager only with rate cards on, and applies them', async () => {
    getHome.mockResolvedValue(HOME);
    getUtilization.mockResolvedValue([]);
    let element = mount();
    await flush();
    await flush();
    expect(find(element, 'apply-rates')).toBeNull();
    document.body.removeChild(element);

    getHome.mockResolvedValue({ ...HOME, ratesEnabled: true });
    applyRates.mockResolvedValue(12);
    element = mount();
    await flush();
    await flush();
    find(element, 'apply-rates').click();
    await flush();
    expect(applyRates).toHaveBeenCalledTimes(1);
    expect(find(element, 'notice')).not.toBeNull();
  });

  it('hides utilization and the export when time tracking is off', async () => {
    getHome.mockResolvedValue({ ...HOME, timeTracking: false, canManage: false });
    const element = mount();
    await flush();
    expect(find(element, 'utilization')).toBeNull();
    expect(getUtilization).not.toHaveBeenCalled();
  });
});
