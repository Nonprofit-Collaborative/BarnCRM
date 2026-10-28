import { createElement } from 'lwc';
import OrgOptimizer from 'c/orgOptimizer';
import getReport from '@salesforce/apex/HealthCheckController.getReport';
import getChecks from '@salesforce/apex/DataHygieneController.getChecks';
import getStorage from '@salesforce/apex/OrgOptimizerStorageController.getStorage';
import getFindings from '@salesforce/apex/OrgOptimizerSetupController.getFindings';

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Find_And_Export_Records', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Review_Duplicate_Suggestions', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_OrgOptimizer_OpenAria', () => ({ default: 'Open {0}' }), {
  virtual: true
});
jest.mock('@salesforce/apex/HealthCheckController.getReport', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/OrgOptimizerStorageController.getStorage',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/OrgOptimizerSetupController.getFindings',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/DataHygieneController.getChecks', () => ({ default: jest.fn() }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function one(element, selector) {
  return element.shadowRoot.querySelector(selector);
}

async function render() {
  const element = createElement('c-org-optimizer', { is: OrgOptimizer });
  document.body.appendChild(element);
  await flush();
  return element;
}

async function activate(element, name) {
  one(element, `lightning-tab[data-id="tab-${name}"]`).dispatchEvent(new CustomEvent('active'));
  await flush();
}

describe('c-org-optimizer as an administrator', () => {
  beforeEach(() => {
    getReport.mockResolvedValue({ findings: [] });
    getChecks.mockResolvedValue([]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('leaves the page name to the App Page header, with no card around the page', async () => {
    const element = await render();

    const shell = element.shadowRoot.querySelector('c-barn-page-shell');
    expect(shell.titleHidden).toBe(true);
    expect(shell.title).toBe('c.Core_OrgOptimizer_Title');
    expect(shell.purpose).toBe('c.Core_OrgOptimizer_Intro');
    expect(element.shadowRoot.querySelector('lightning-card')).toBeNull();
  });

  it('names each Overview Open button for its section', async () => {
    const element = await render();

    const buttons = Array.from(
      element.shadowRoot.querySelectorAll('lightning-button[data-section]')
    );
    expect(buttons.length).toBeGreaterThan(1);
    const names = buttons.map((button) => button.ariaLabel);
    names.forEach((name) => expect(name).toMatch(/^Open \S/));
    expect(new Set(names).size).toBe(names.length);
  });

  it('opens on the Overview and runs no section', async () => {
    const element = await render();

    expect(one(element, 'lightning-tabset').activeTabValue).toBe('overview');
    expect(one(element, 'c-data-hygiene-console')).toBeNull();
    expect(one(element, 'c-duplicate-review')).toBeNull();
    expect(one(element, 'c-field-utilization')).toBeNull();
    expect(one(element, 'c-health-check-panel')).toBeNull();
    expect(getReport).not.toHaveBeenCalled();
    expect(getChecks).not.toHaveBeenCalled();
    const names = Array.from(
      element.shadowRoot.querySelectorAll('lightning-button[data-section]')
    ).map((button) => button.dataset.section);
    // Duplicates moved to the Duplicate Matching tab.
    expect(names).toEqual([
      'quality',
      'fieldUtilization',
      'healthCheck',
      'errors',
      'storage',
      'setup'
    ]);
  });

  it('creates a section the first time its tab is opened, and keeps it', async () => {
    const element = await render();

    await activate(element, 'quality');
    expect(one(element, 'c-data-hygiene-console')).not.toBeNull();

    await activate(element, 'fieldUtilization');
    expect(one(element, 'c-field-utilization')).not.toBeNull();
    expect(one(element, 'c-data-hygiene-console')).not.toBeNull();
    expect(one(element, 'c-duplicate-review')).toBeNull();
  });

  it('opens a section from the Overview', async () => {
    const element = await render();

    one(element, 'lightning-button[data-section="fieldUtilization"]').click();
    await flush();

    expect(one(element, 'lightning-tabset').activeTabValue).toBe('fieldUtilization');
    expect(one(element, 'c-field-utilization')).not.toBeNull();
    expect(one(element, 'c-duplicate-review')).toBeNull();
  });

  it('reads storage and errors only when their sections are opened', async () => {
    getStorage.mockResolvedValue({ countCap: 10000, limits: [], ownObjects: [] });
    const element = await render();
    expect(getStorage).not.toHaveBeenCalled();
    expect(one(element, 'c-error-log-tile')).toBeNull();

    await activate(element, 'storage');
    expect(one(element, 'c-optimizer-storage')).not.toBeNull();
    expect(getStorage).toHaveBeenCalledTimes(1);

    await activate(element, 'errors');
    expect(one(element, 'c-error-log-tile')).not.toBeNull();
  });

  it('reads unused setup only when its section is opened', async () => {
    getFindings.mockResolvedValue({ countCap: 1000, findings: [] });
    const element = await render();
    expect(getFindings).not.toHaveBeenCalled();

    await activate(element, 'setup');
    expect(one(element, 'c-optimizer-setup')).not.toBeNull();
    expect(getFindings).toHaveBeenCalledTimes(1);
  });

  it('runs Health Check only when asked', async () => {
    const element = await render();

    await activate(element, 'healthCheck');
    expect(one(element, 'c-health-check-panel')).toBeNull();
    expect(getReport).not.toHaveBeenCalled();

    one(element, 'lightning-button[data-id="run-health-check"]').click();
    await flush();

    expect(one(element, 'c-health-check-panel')).not.toBeNull();
    expect(getReport).toHaveBeenCalledTimes(1);
  });
});
