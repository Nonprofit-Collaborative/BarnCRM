import { createElement } from 'lwc';
import { graphql } from 'lightning/graphql';
import ProjectsAtRisk from 'c/projectsAtRisk';

jest.mock('@salesforce/user/Id', () => ({ default: '005000000000001AAA' }), { virtual: true });

const ME = '005000000000001AAA';

const flush = () =>
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  new Promise((resolve) => setTimeout(resolve, 0));

function node({ id, name, health, reasons = null, ownerId = ME, owner = 'Ann' }) {
  return {
    Id: id,
    Name: { value: name },
    Health__c: { value: health },
    Health_Reasons__c: { value: reasons },
    OwnerId: { value: ownerId },
    Owner: { Name: { value: owner } }
  };
}

function emitProjects(...nodes) {
  graphql.emit({
    uiapi: { query: { Project__c: { edges: nodes.map((item) => ({ node: item })) } } }
  });
}

function mount() {
  const element = createElement('c-projects-at-risk', { is: ProjectsAtRisk });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const rows = (element) => element.shadowRoot.querySelectorAll('[data-id="row"]');

describe('c-projects-at-risk', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists projects Off Track first with their reasons, and filters to Only Mine', async () => {
    const element = mount();
    emitProjects(
      node({ id: 'a01000000000002AAA', name: 'Intake', health: 'At Risk', ownerId: '005OTHER' }),
      node({
        id: 'a01000000000001AAA',
        name: 'Rollout',
        health: 'Off Track',
        reasons: 'Late\nOver budget'
      })
    );
    await flush();
    expect(rows(element)).toHaveLength(2);
    const first = rows(element)[0];
    expect(first.textContent).toContain('Rollout');
    expect(first.textContent).toContain('Late; Over budget');
    expect(first.querySelector('.slds-theme_error')).not.toBeNull();

    const onlyMine = find(element, 'only-mine');
    onlyMine.checked = true;
    onlyMine.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(rows(element)).toHaveLength(1);
    expect(rows(element)[0].textContent).toContain('Rollout');
  });

  it('says when nothing is at risk and shows a failure', async () => {
    const element = mount();
    emitProjects();
    await flush();
    expect(find(element, 'none')).not.toBeNull();
    graphql.emitErrors([{ message: 'No access' }]);
    await flush();
    expect(find(element, 'error-message').message).toBe('c.Projects_Error_Generic');
  });
});
