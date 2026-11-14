import { createElement } from 'lwc';
import ProjectsRequestPanel from 'c/projectsRequestPanel';
import getRequest from '@salesforce/apex/ProjectRequestsController.getRequest';
import saveRequest from '@salesforce/apex/ProjectRequestsController.saveRequest';
import addComment from '@salesforce/apex/ProjectRequestsController.addComment';
import createTask from '@salesforce/apex/ProjectRequestsController.createTask';
import createChangeRequest from '@salesforce/apex/ProjectRequestsController.createChangeRequest';

jest.mock('@salesforce/apex/ProjectRequestsController.getRequest', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ProjectRequestsController.saveRequest',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/ProjectRequestsController.addComment', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectRequestsController.createTask', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ProjectRequestsController.createChangeRequest',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

const DETAIL = {
  id: 'r1',
  name: 'REQ-000001',
  subject: 'Report wrong',
  status: 'New',
  priority: 'Medium',
  ownerId: 'u1',
  dueDate: '2026-11-20',
  projectId: 'p1',
  channel: 'Portal',
  changeRequestsEnabled: true,
  comments: [
    { id: 'c1', body: 'Hi', shared: true, fromRequester: true, author: 'API' },
    { id: 'c2', body: 'Note', shared: false, fromRequester: false, author: 'Ann' }
  ]
};

function mount() {
  const element = createElement('c-projects-request-panel', { is: ProjectsRequestPanel });
  element.recordId = 'r1';
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-projects-request-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the thread with what the requester sees marked, and saves only changes', async () => {
    getRequest.mockResolvedValue(DETAIL);
    saveRequest.mockResolvedValue();
    const element = mount();
    const changed = jest.fn();
    element.addEventListener('changed', changed);
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="comment"]')).toHaveLength(2);
    expect(find(element, 'save').disabled).toBe(true);
    const status = find(element, 'status');
    status.dispatchEvent(new CustomEvent('change', { detail: { value: 'In Progress' } }));
    await flush();
    find(element, 'save').click();
    await flush();
    expect(saveRequest).toHaveBeenCalledWith({
      requestId: 'r1',
      changes: { Status__c: 'In Progress' }
    });
    expect(changed).toHaveBeenCalled();
    expect(find(element, 'notice')).not.toBeNull();
  });

  it('adds a shared comment and creates a task and a change request', async () => {
    getRequest.mockResolvedValue(DETAIL);
    addComment.mockResolvedValue();
    createTask.mockResolvedValue('t1');
    createChangeRequest.mockResolvedValue('x1');
    const element = mount();
    await flush();
    find(element, 'comment-body').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'On it' } })
    );
    find(element, 'share').dispatchEvent(new CustomEvent('change', { detail: { checked: true } }));
    await flush();
    find(element, 'add-comment').click();
    await flush();
    expect(addComment).toHaveBeenCalledWith({ requestId: 'r1', body: 'On it', shared: true });
    find(element, 'create-task').click();
    await flush();
    expect(createTask).toHaveBeenCalledWith({ requestId: 'r1' });
    find(element, 'create-change').click();
    await flush();
    expect(createChangeRequest).toHaveBeenCalledWith({ requestId: 'r1' });
  });

  it('cannot make a task without a project, and shows a refusal', async () => {
    getRequest.mockResolvedValue({ ...DETAIL, projectId: null, comments: [] });
    saveRequest.mockRejectedValue({
      body: { message: 'Enter a resolution before marking the request Resolved.' }
    });
    const element = mount();
    await flush();
    expect(find(element, 'create-task').disabled).toBe(true);
    expect(find(element, 'no-comments')).not.toBeNull();
    find(element, 'resolution').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Done' } })
    );
    await flush();
    find(element, 'save').click();
    await flush();
    expect(find(element, 'error-message')).not.toBeNull();
  });
});
