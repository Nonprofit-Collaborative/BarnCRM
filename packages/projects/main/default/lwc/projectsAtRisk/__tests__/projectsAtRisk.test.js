import { createElement } from 'lwc';
import ProjectsAtRisk from 'c/projectsAtRisk';
import getAtRisk from '@salesforce/apex/ProjectsController.getAtRisk';

jest.mock('@salesforce/apex/ProjectsController.getAtRisk', () => ({ default: jest.fn() }), {
  virtual: true
});

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

function mount() {
  const element = createElement('c-projects-at-risk', { is: ProjectsAtRisk });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-projects-at-risk', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists projects with their reasons and reloads for Only Mine', async () => {
    getAtRisk.mockResolvedValue([
      {
        id: 'a01000000000001AAA',
        name: 'Rollout',
        health: 'Off Track',
        healthReasons: 'Late\nOver budget',
        ownerName: 'Ann'
      }
    ]);
    const element = mount();
    await flush();
    const row = find(element, 'row');
    expect(row.textContent).toContain('Late; Over budget');
    expect(row.querySelector('.slds-theme_error')).not.toBeNull();
    const onlyMine = find(element, 'only-mine');
    onlyMine.checked = true;
    onlyMine.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(getAtRisk).toHaveBeenLastCalledWith({ onlyMine: true });
  });

  it('says when nothing is at risk and shows a failure', async () => {
    getAtRisk.mockResolvedValueOnce([]);
    const element = mount();
    await flush();
    expect(find(element, 'none')).not.toBeNull();
    getAtRisk.mockRejectedValueOnce({ body: { message: 'No access' } });
    find(element, 'only-mine').dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(find(element, 'error-message').message).toBe('No access');
  });
});
