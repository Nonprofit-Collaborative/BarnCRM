import { createElement } from 'lwc';
import ProjectsRequests from 'c/projectsRequests';
import getRequests from '@salesforce/apex/ProjectRequestsController.getRequests';

jest.mock(
  '@salesforce/apex/ProjectRequestsController.getRequests',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/ProjectRequestsController.getRequest',
  () => ({ default: jest.fn(() => Promise.resolve(null)) }),
  {
    virtual: true
  }
);

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

const PAGE = {
  enabled: true,
  rows: [
    {
      id: 'r1',
      name: 'REQ-000001',
      subject: 'Report wrong',
      status: 'New',
      priority: 'High',
      overdue: true
    },
    {
      id: 'r2',
      name: 'REQ-000002',
      subject: 'Add a user',
      status: 'In Progress',
      priority: 'Low',
      overdue: false
    }
  ]
};

function mount() {
  const element = createElement('c-projects-requests', { is: ProjectsRequests });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const findAll = (element, id) => element.shadowRoot.querySelectorAll(`[data-id="${id}"]`);

describe('c-projects-requests', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says requests are off', async () => {
    getRequests.mockResolvedValue({ enabled: false, rows: [] });
    const element = mount();
    await flush();
    expect(find(element, 'off')).not.toBeNull();
  });

  it('lists my open requests, flags the overdue one and switches views', async () => {
    getRequests.mockResolvedValue(PAGE);
    const element = mount();
    await flush();
    expect(getRequests).toHaveBeenCalledWith({ view: 'mine' });
    expect(findAll(element, 'row')).toHaveLength(2);
    expect(findAll(element, 'overdue')).toHaveLength(1);
    findAll(element, 'view')[3].click();
    await flush();
    expect(getRequests).toHaveBeenLastCalledWith({ view: 'overdue' });
  });

  it('opens the panel for the chosen request', async () => {
    getRequests.mockResolvedValue(PAGE);
    const element = mount();
    await flush();
    expect(find(element, 'panel')).toBeNull();
    findAll(element, 'open')[1].click();
    await flush();
    expect(find(element, 'panel').recordId).toBe('r2');
  });

  it('says so when a view is empty and shows a refusal', async () => {
    getRequests.mockResolvedValueOnce({ enabled: true, rows: [] });
    const element = mount();
    await flush();
    expect(find(element, 'empty')).not.toBeNull();
    getRequests.mockRejectedValueOnce({ body: { message: 'No access' } });
    findAll(element, 'view')[1].click();
    await flush();
    expect(find(element, 'error-message')).not.toBeNull();
  });
});
