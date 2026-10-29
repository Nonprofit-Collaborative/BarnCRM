import { createElement } from 'lwc';
import OptimizerSetup from 'c/optimizerSetup';
import getFindings from '@salesforce/apex/OrgOptimizerSetupController.getFindings';

jest.mock(
  '@salesforce/apex/OrgOptimizerSetupController.getFindings',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_OrgOptimizer_CheckInactiveUsers',
  () => ({ default: 'Active users who have not logged in for {0} days' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_OrgOptimizer_MoreThan', () => ({ default: 'More than {0}' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_OrgOptimizer_CouldNotCheck',
  () => ({ default: 'Could not check' }),
  { virtual: true }
);

const RESULT = {
  countCap: 1000,
  loginDays: 90,
  reportDays: 365,
  findings: [
    {
      key: 'inactiveUsers',
      count: 2,
      moreThan: false,
      failed: false,
      examples: ['Ana Lopez', 'Sam Reed'],
      setupUrl: '/lightning/setup/ManageUsers/home'
    },
    {
      key: 'staleReports',
      count: 1000,
      moreThan: true,
      failed: false,
      examples: ['Old report'],
      setupUrl: '/lightning/o/Report/home'
    },
    {
      key: 'inactiveFlows',
      count: null,
      moreThan: false,
      failed: true,
      examples: [],
      setupUrl: '/lightning/setup/Flows/home'
    }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render() {
  const element = createElement('c-optimizer-setup', { is: OptimizerSetup });
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

describe('c-optimizer-setup', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows each check with its count, examples and Setup link', async () => {
    getFindings.mockResolvedValue(RESULT);
    const element = await render();

    const users = element.shadowRoot.querySelector('[data-id="inactiveUsers"]');
    expect(users.textContent).toContain('Active users who have not logged in for 90 days');
    expect(users.querySelector('[data-id="count"]').textContent).toBe('2');
    expect(users.querySelector('[data-id="examples"]').textContent).toBe('Ana Lopez, Sam Reed');
    const link = users.querySelector('[data-id="setup-link"]');
    expect(link.getAttribute('href')).toBe('/lightning/setup/ManageUsers/home');
    // The new-tab cue: an icon, and words for screen readers.
    expect(link.querySelector('lightning-icon').iconName).toBe('utility:new_window');
    expect(link.querySelector('.slds-assistive-text')).not.toBeNull();
    expect(users.querySelector('[data-id="count"]').classList.contains('slds-theme_warning')).toBe(
      true
    );

    const reports = element.shadowRoot.querySelector('[data-id="staleReports"]');
    expect(reports.querySelector('[data-id="count"]').textContent).toBe('More than 1000');
  });

  it('says a check could not run, without examples', async () => {
    getFindings.mockResolvedValue(RESULT);
    const element = await render();

    const flows = element.shadowRoot.querySelector('[data-id="inactiveFlows"]');
    expect(flows.querySelector('[data-id="count"]').textContent).toBe('Could not check');
    expect(flows.querySelector('[data-id="examples"]')).toBeNull();
  });

  it('shows the server refusal and reads again on Refresh', async () => {
    getFindings.mockRejectedValueOnce({ body: { message: 'Needs Manage BarnCRM Settings' } });
    const element = await render();
    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toBe(
      'Needs Manage BarnCRM Settings'
    );

    getFindings.mockResolvedValue(RESULT);
    element.shadowRoot.querySelector('[data-id="refresh"]').click();
    await flush();
    await flush();
    expect(getFindings).toHaveBeenCalledTimes(2);
    expect(element.shadowRoot.querySelector('[data-id="error"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="inactiveUsers"]')).not.toBeNull();
  });
});
