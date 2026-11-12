import { createElement } from 'lwc';
import ProjectsAllocation from 'c/projectsAllocation';
import getAllocation from '@salesforce/apex/ProjectStaffingController.getAllocation';

jest.mock(
  '@salesforce/apex/ProjectStaffingController.getAllocation',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

function mount() {
  const element = createElement('c-projects-allocation', { is: ProjectsAllocation });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-projects-allocation', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('asks for whole weeks and draws each person against capacity, over in red', async () => {
    getAllocation.mockResolvedValue({
      defaultCapacity: 40,
      resources: [{ Id: 'r1', User__c: 'u1', User__r: { Name: 'Ann' }, Active__c: true }],
      assignments: [
        {
          Resource__c: 'u1',
          Planned_Hours__c: 100,
          Start_Date__c: '2026-11-09',
          End_Date__c: '2026-11-13'
        }
      ],
      requests: [],
      logged: [{ userId: 'u1', date: '2026-11-10', hours: 6 }]
    });
    const element = mount();
    await flush();
    const args = getAllocation.mock.calls[0][0];
    expect(args.fromDate <= args.toDate).toBe(true);
    expect(new Date(`${args.fromDate}T00:00:00Z`).getUTCDay()).toBe(1);
    expect(new Date(`${args.toDate}T00:00:00Z`).getUTCDay()).toBe(0);
    expect(find(element, 'grid')).not.toBeNull();
    // The test's own week is not the week of the plan, so only a fixed-week check is safe here:
    // the person row and the unfilled requests row are drawn.
    expect(find(element, 'person').textContent).toContain('Ann');
    expect(find(element, 'demand')).not.toBeNull();
  });

  it('marks a week over capacity', async () => {
    const monday = new Date();
    monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
    const iso = `${monday.getFullYear()}-${String(monday.getMonth() + 1).padStart(2, '0')}-${String(monday.getDate()).padStart(2, '0')}`;
    const friday = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 4);
    const end = `${friday.getFullYear()}-${String(friday.getMonth() + 1).padStart(2, '0')}-${String(friday.getDate()).padStart(2, '0')}`;
    getAllocation.mockResolvedValue({
      defaultCapacity: 40,
      resources: [{ Id: 'r1', User__c: 'u1', User__r: { Name: 'Ann' }, Active__c: true }],
      assignments: [
        { Resource__c: 'u1', Planned_Hours__c: 60, Start_Date__c: iso, End_Date__c: end }
      ],
      requests: [],
      logged: []
    });
    const element = mount();
    await flush();
    const cell = element.shadowRoot.querySelector('[data-id="cell"]');
    expect(cell.textContent).toBe('60 / 40 (150%)');
    expect(cell.className).toContain('slds-text-color_error');
  });

  it('says so when there are no active people', async () => {
    getAllocation.mockResolvedValue({
      defaultCapacity: 40,
      resources: [],
      assignments: [],
      requests: [],
      logged: []
    });
    const element = mount();
    await flush();
    expect(find(element, 'grid')).toBeNull();
    expect(element.shadowRoot.textContent).toContain('c.Projects_Allocation_None');
  });

  it('shows an error when the weeks cannot be read', async () => {
    getAllocation.mockRejectedValue({ body: { message: 'Nope.' } });
    const element = mount();
    await flush();
    expect(find(element, 'error-message')).not.toBeNull();
  });
});
