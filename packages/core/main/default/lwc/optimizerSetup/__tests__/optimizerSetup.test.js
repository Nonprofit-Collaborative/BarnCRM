import { createElement } from 'lwc';
import OptimizerSetup from 'c/optimizerSetup';
import getFindings from '@salesforce/apex/OrgOptimizerSetupController.getFindings';
import { setHelpTextForTest } from 'c/barnHelpText';

setHelpTextForTest({
  Core_OrgOptimizer_CouldNotCheck: 'Could not check'
});

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
jest.mock(
  '@salesforce/label/c.Core_HealthCheck_OrphansMoreThan',
  () => ({ default: 'More than {0}' }),
  {
    virtual: true
  }
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
    const count = users.querySelector('c-barn-status-badge[data-id="count"]');
    expect(count.label).toBe('2');
    // A check that found something is a warning badge (the visual standard's vocabulary).
    expect(count.status).toBe('warning');
    expect(users.querySelector('[data-id="examples"]').textContent).toBe('Ana Lopez, Sam Reed');
    const link = users.querySelector('[data-id="setup-link"]');
    expect(link.getAttribute('href')).toBe('/lightning/setup/ManageUsers/home');
    // The new-tab cue: an icon, and words for screen readers.
    expect(link.querySelector('lightning-icon').iconName).toBe('utility:new_window');
    expect(link.querySelector('.slds-assistive-text')).not.toBeNull();

    const reports = element.shadowRoot.querySelector('[data-id="staleReports"]');
    expect(reports.querySelector('[data-id="count"]').label).toBe('More than 1000');
  });

  it('says a check could not run, without examples', async () => {
    getFindings.mockResolvedValue(RESULT);
    const element = await render();

    const flows = element.shadowRoot.querySelector('[data-id="inactiveFlows"]');
    expect(flows.querySelector('[data-id="count"]').textContent).toBe('Could not check');
    expect(flows.querySelector('[data-id="examples"]')).toBeNull();
  });

  it('keeps the technical debt checks in a collapsed For Developers part, closed by default (admin-21)', async () => {
    getFindings.mockResolvedValue({
      ...RESULT,
      apiVersion: 50,
      findings: [
        { ...RESULT.findings[0] },
        {
          key: 'apexOldApi',
          kind: 'debt',
          count: 3,
          moreThan: false,
          failed: false,
          examples: ['OldClass'],
          setupUrl: '/lightning/setup/ApexClasses/home'
        }
      ]
    });
    const element = await render();

    const debt = element.shadowRoot.querySelector('[data-id="debt-section"]');
    expect(debt.querySelector('h3').textContent).toBe('c.Core_TechDebt_DebtHeading');
    const toggle = debt.querySelector('[data-id="debt-toggle"]');
    expect(toggle.getAttribute('aria-expanded')).toBe('false');
    expect(debt.classList.contains('slds-is-open')).toBe(false);
    expect(debt.querySelector('[data-id="apexOldApi"]')).toBeNull();

    toggle.click();
    await flush();

    expect(toggle.getAttribute('aria-expanded')).toBe('true');
    expect(debt.classList.contains('slds-is-open')).toBe(true);
    expect(debt.querySelector('[data-id="debt-intro"]')).not.toBeNull();
    const apex = debt.querySelector('[data-id="apexOldApi"]');
    expect(apex).not.toBeNull();
    expect(apex.querySelector('[data-id="count"]').label).toBe('3');
    // The unused list keeps its checks, always open, under the section's own heading.
    const unused = element.shadowRoot.querySelector('[data-id="unused-section"]');
    expect(unused.querySelector('[data-id="inactiveUsers"]')).not.toBeNull();
    expect(unused.querySelector('[data-id="apexOldApi"]')).toBeNull();
    expect(unused.querySelector('h3')).toBeNull();

    toggle.click();
    await flush();
    expect(debt.querySelector('[data-id="apexOldApi"]')).toBeNull();
  });

  it('shows no heading when there are no technical debt checks', async () => {
    getFindings.mockResolvedValue(RESULT);
    const element = await render();
    expect(element.shadowRoot.querySelector('[data-id="debt-section"]')).toBeNull();
    expect(element.shadowRoot.querySelector('h3')).toBeNull();
  });

  it('shows the server refusal and reads again on Refresh', async () => {
    getFindings.mockRejectedValueOnce({ body: { message: 'Needs Manage BarnCRM Settings' } });
    const element = await render();
    expect(element.shadowRoot.querySelector('[data-id="error"]').message).toBe(
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
