import { createElement } from 'lwc';
import ProjectsApprovals from 'c/projectsApprovals';
import getQueue from '@salesforce/apex/ProjectApprovalsController.getQueue';
import decide from '@salesforce/apex/ProjectApprovalsController.decide';

jest.mock('@salesforce/apex/ProjectApprovalsController.getQueue', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ProjectApprovalsController.decide', () => ({ default: jest.fn() }), {
  virtual: true
});

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

const row = (id, date, hours) => ({
  Id: id,
  Project__c: 'p1',
  Project__r: { Name: 'Rollout', OwnerId: 'u9' },
  User__c: 'u1',
  User__r: { Name: 'Ann' },
  Date__c: date,
  Hours__c: hours
});

const QUEUE = {
  enabled: true,
  entries: [row('t1', '2026-11-09', 4), row('t2', '2026-11-10', 3)],
  expenses: [
    {
      Id: 'x1',
      Project__r: { Name: 'Rollout' },
      User__c: 'u1',
      User__r: { Name: 'Ann' },
      Date__c: '2026-11-11',
      Category__c: 'Travel',
      Amount__c: 20
    }
  ]
};

function mount() {
  const element = createElement('c-projects-approvals', { is: ProjectsApprovals });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-projects-approvals', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says it is off when approvals are off', async () => {
    getQueue.mockResolvedValue({ enabled: false, entries: [], expenses: [] });
    const element = mount();
    await flush();
    expect(find(element, 'off')).not.toBeNull();
  });

  it('says nothing is waiting for an empty queue', async () => {
    getQueue.mockResolvedValue({ enabled: true, entries: [], expenses: [] });
    const element = mount();
    await flush();
    expect(find(element, 'empty')).not.toBeNull();
  });

  it('groups a person-week and approves all of it at once', async () => {
    getQueue.mockResolvedValue(QUEUE);
    decide.mockResolvedValue(3);
    const element = mount();
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="group"]')).toHaveLength(1);
    find(element, 'approve').click();
    await flush();
    expect(decide).toHaveBeenCalledWith({ ids: ['t1', 't2', 'x1'], approve: true, reason: null });
  });

  it('rejects one line with the reason typed for its week and shows a refusal', async () => {
    getQueue.mockResolvedValue(QUEUE);
    decide.mockRejectedValue({ body: { message: 'Enter a reason for the rejection.' } });
    const element = mount();
    await flush();
    const reason = find(element, 'reason');
    reason.dispatchEvent(new CustomEvent('change', { detail: { value: 'Wrong project' } }));
    find(element, 'details').click();
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="line"]')).toHaveLength(3);
    element.shadowRoot.querySelectorAll('[data-id="reject-line"]')[0].click();
    await flush();
    expect(decide).toHaveBeenCalledWith({
      ids: ['t1'],
      approve: false,
      reason: 'Wrong project'
    });
    expect(find(element, 'error-message').message).toBe('Enter a reason for the rejection.');
  });
});
