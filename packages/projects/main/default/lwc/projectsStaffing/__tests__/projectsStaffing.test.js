import { createElement } from 'lwc';
import ProjectsStaffing from 'c/projectsStaffing';
import getStaffing from '@salesforce/apex/ProjectStaffingController.getStaffing';
import getAllocation from '@salesforce/apex/ProjectStaffingController.getAllocation';
import fill from '@salesforce/apex/ProjectStaffingController.fill';
import saveResource from '@salesforce/apex/ProjectStaffingController.saveResource';

jest.mock(
  '@salesforce/apex/ProjectStaffingController.getStaffing',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/ProjectStaffingController.getAllocation',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/ProjectStaffingController.fill', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ProjectStaffingController.saveResource',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

const person = (id, name, skills) => ({
  Id: `r${id}`,
  User__c: `u${id}`,
  User__r: { Name: name },
  Skills__c: skills,
  Active__c: true
});

const STAFFING = {
  enabled: true,
  defaultCapacity: 40,
  skills: ['Apex', 'Data Migration'],
  resources: [person(1, 'Ann', 'Apex'), person(2, 'Bo', 'Apex;Data Migration')],
  requests: [
    {
      Id: 'q1',
      Project__c: 'p1',
      Project__r: { Name: 'Rollout' },
      Role__c: 'Data Migration',
      Skills__c: 'Apex;Data Migration',
      Hours__c: 20,
      Start_Date__c: '2026-11-09',
      End_Date__c: '2026-11-13'
    }
  ]
};

function mount() {
  const element = createElement('c-projects-staffing', { is: ProjectsStaffing });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const findAll = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('c-projects-staffing', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows only the off message while Manage resources is off', async () => {
    getStaffing.mockResolvedValue({ enabled: false, defaultCapacity: 40 });
    const element = mount();
    await flush();
    expect(find(element, 'off')).not.toBeNull();
    expect(find(element, 'requests')).toBeNull();
    expect(find(element, 'resources')).toBeNull();
  });

  it('ranks people for a request, then assigns the one chosen', async () => {
    getStaffing.mockResolvedValue(STAFFING);
    getAllocation.mockResolvedValue({
      defaultCapacity: 40,
      resources: STAFFING.resources,
      assignments: [],
      requests: [],
      logged: []
    });
    fill.mockResolvedValue('a02000000000001AAA');
    const element = mount();
    await flush();
    expect(findAll(element, 'request')).toHaveLength(1);

    element.shadowRoot.querySelector('.fill').click();
    await flush();
    expect(getAllocation).toHaveBeenCalledWith({
      fromDate: '2026-11-09',
      toDate: '2026-11-13'
    });
    const rows = findAll(element, 'candidate');
    expect(rows).toHaveLength(2);
    expect(rows[0].textContent).toContain('Bo');
    expect(rows[0].textContent).toContain('c.Projects_Staffing_Match');

    rows[0].querySelector('.assign').click();
    await flush();
    expect(fill).toHaveBeenCalledWith({ requestId: 'q1', userId: 'u2' });
    expect(find(element, 'notice')).not.toBeNull();
    expect(getStaffing).toHaveBeenCalledTimes(2);
  });

  it('saves a person with their skills and capacity', async () => {
    getStaffing.mockResolvedValue(STAFFING);
    saveResource.mockResolvedValue('a03000000000001AAA');
    const element = mount();
    await flush();
    element.shadowRoot.querySelector('.edit').click();
    await flush();
    find(element, 'save').click();
    await flush();
    expect(saveResource).toHaveBeenCalledWith({
      userId: 'u1',
      skills: 'Apex',
      weeklyCapacity: null,
      defaultRole: '',
      active: true
    });
  });

  it('shows a refusal in words', async () => {
    getStaffing.mockResolvedValue(STAFFING);
    getAllocation.mockRejectedValue({ body: { message: 'Not allowed.' } });
    const element = mount();
    await flush();
    element.shadowRoot.querySelector('.fill').click();
    await flush();
    expect(find(element, 'error-message')).not.toBeNull();
    expect(find(element, 'candidates')).toBeNull();
  });
});
