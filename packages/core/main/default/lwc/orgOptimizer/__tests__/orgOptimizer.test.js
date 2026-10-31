import { createElement } from 'lwc';
import * as navigation from 'lightning/navigation';
import { createApexTestWireAdapter as mockCreateApexTestWireAdapter } from '@salesforce/sfdx-lwc-jest';
import OrgOptimizer from 'c/orgOptimizer';
import getOpenLink from '@salesforce/apex/AccessExplorerController.getOpenLink';
import getReport from '@salesforce/apex/HealthCheckController.getReport';
import getLastRun from '@salesforce/apex/HealthCheckController.getLastRun';
import getTile from '@salesforce/apex/ErrorLogController.getTile';
import getChecks from '@salesforce/apex/DataHygieneController.getChecks';
import getStorage from '@salesforce/apex/OrgOptimizerStorageController.getStorage';
import getFindings from '@salesforce/apex/OrgOptimizerSetupController.getFindings';
import getChangeSummary from '@salesforce/apex/SetupChangeController.getSummary';
import getChanges from '@salesforce/apex/SetupChangeController.getChanges';

jest.mock('@salesforce/customPermission/Manage_BarnCRM_Settings', () => ({ default: true }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/AccessExplorerController.getOpenLink',
  () => ({ default: mockCreateApexTestWireAdapter(jest.fn()) }),
  { virtual: true }
);
jest.mock('@salesforce/customPermission/Find_And_Export_Records', () => ({ default: true }), {
  virtual: true
});
jest.mock('@salesforce/customPermission/Review_Duplicate_Suggestions', () => ({ default: false }), {
  virtual: true
});
jest.mock('@salesforce/apex/HealthCheckController.getReport', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HealthCheckController.getLastRun', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ErrorLogController.getTile',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
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
jest.mock('@salesforce/apex/SetupChangeController.getSummary', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SetupChangeController.getChanges', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SetupChangeController.copyNow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_OrgOptimizer_BadgeNew', () => ({ default: '{0} New' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_OrgOptimizer_BadgeNeedAttention',
  () => ({ default: '{0} Need Attention' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_OrgOptimizer_BadgeWarnings',
  () => ({ default: 'Warnings: {0}' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_OrgOptimizer_BadgePassed', () => ({ default: 'Passed' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_OrgOptimizer_BadgeNotRun', () => ({ default: 'Not Run Yet' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_OrgOptimizer_BadgeDataStorage',
  () => ({ default: 'Data Storage {0}%' }),
  { virtual: true }
);

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

function tiles(element) {
  return one(element, 'c-barn-tool-grid').groups.flatMap((group) => group.tiles);
}

function tileNamed(element, name) {
  return tiles(element).find((tile) => tile.name === name);
}

describe('c-org-optimizer as an administrator', () => {
  beforeEach(() => {
    getReport.mockResolvedValue({ findings: [] });
    getChecks.mockResolvedValue([]);
    getLastRun.mockResolvedValue({ ranAt: null });
    getTile.mockResolvedValue({ newCount: 0, newCountCapped: false, recent: [] });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('sits in the page shell, with the title kept for screen readers only', async () => {
    const element = await render();

    const shell = one(element, 'c-barn-page-shell');
    expect(shell.titleHidden).toBe(true);
    expect(shell.title).toBe('c.Core_OrgOptimizer_Title');
    expect(shell.purpose).toBe('c.Core_OrgOptimizer_Intro');
    expect(one(element, 'lightning-card')).toBeNull();
    expect(one(element, '[data-id="help"] c-barn-help').learnMoreUrl).toContain(
      'admin-guide/org-optimizer.md'
    );
  });

  it('opens on the Overview with a tile per section, in two groups, and runs no section', async () => {
    const element = await render();

    expect(one(element, 'lightning-tabset').activeTabValue).toBe('overview');
    expect(one(element, 'c-data-hygiene-console')).toBeNull();
    expect(one(element, 'c-field-utilization')).toBeNull();
    expect(one(element, 'c-health-check-panel')).toBeNull();
    expect(getReport).not.toHaveBeenCalled();
    expect(getChecks).not.toHaveBeenCalled();
    const groups = one(element, 'c-barn-tool-grid').groups;
    expect(groups.map((group) => group.tiles.map((tile) => tile.name))).toEqual([
      ['quality', 'fieldUtilization', 'dataDictionary', 'aiExport'],
      ['healthCheck', 'errors', 'storage', 'setup', 'setupChanges', 'accessExplorer']
    ]);
    tiles(element).forEach((tile) => expect(tile.iconName).toMatch(/^standard:/));
  });

  it('uses only icon names that exist in the SLDS icon set', async () => {
    // The SLDS icon list ships with the SLDS linter (@salesforce-ux/slds-linter).
    const sets = require('@salesforce-ux/sds-metadata/next').icons;
    const known = new Set(
      sets.flatMap((set) => set.icons.map((icon) => `${icon.sprite}:${icon.symbol}`))
    );
    const element = await render();

    tiles(element).forEach((tile) => expect(known.has(tile.iconName)).toBe(true));
  });

  it('badges Errors and Health Check from two small reads, and nothing else yet', async () => {
    getTile.mockResolvedValue({ newCount: 3, newCountCapped: false, recent: [] });
    const element = await render();

    expect(getTile).toHaveBeenCalledWith({ rowCount: 1 });
    expect(tileNamed(element, 'errors')).toMatchObject({
      badgeLabel: '3 New',
      badgeVariant: 'warning'
    });
    expect(tileNamed(element, 'healthCheck').badgeLabel).toBe('Not Run Yet');
    expect(tileNamed(element, 'quality').badgeLabel).toBeUndefined();
    expect(tileNamed(element, 'storage').badgeLabel).toBeUndefined();
  });

  it('badges Health Check from its last run', async () => {
    getLastRun.mockResolvedValue({ ranAt: '2026-10-28T10:00:00Z', errors: 0, warnings: 2 });
    const element = await render();

    expect(tileNamed(element, 'healthCheck')).toMatchObject({
      badgeLabel: 'Warnings: 2',
      badgeVariant: 'warning'
    });
  });

  it('leaves a badge off when its read fails', async () => {
    getTile.mockRejectedValue({ body: { message: 'No access' } });
    const element = await render();

    expect(tileNamed(element, 'errors').badgeLabel).toBeUndefined();
  });

  it('badges Data Quality and Storage once their sections report', async () => {
    const element = await render();

    await activate(element, 'quality');
    one(element, 'c-data-hygiene-console').dispatchEvent(
      new CustomEvent('summary', { detail: { needsAttention: 2 } })
    );
    await activate(element, 'storage');
    one(element, 'c-optimizer-storage').dispatchEvent(
      new CustomEvent('summary', { detail: { dataStoragePercent: 85 } })
    );
    await flush();

    expect(tileNamed(element, 'quality')).toMatchObject({
      badgeLabel: '2 Need Attention',
      badgeVariant: 'warning'
    });
    expect(tileNamed(element, 'storage')).toMatchObject({
      badgeLabel: 'Data Storage 85%',
      badgeVariant: 'warning'
    });
  });

  it('creates a section the first time its tab is opened, and keeps it', async () => {
    const element = await render();

    await activate(element, 'quality');
    expect(one(element, 'c-data-hygiene-console')).not.toBeNull();

    await activate(element, 'fieldUtilization');
    expect(one(element, 'c-field-utilization')).not.toBeNull();
    expect(one(element, 'c-data-hygiene-console')).not.toBeNull();
  });

  it('creates the Data Dictionary only when its tab is first opened', async () => {
    const element = await render();
    expect(one(element, 'c-data-dictionary')).toBeNull();

    await activate(element, 'dataDictionary');

    expect(one(element, 'c-data-dictionary')).not.toBeNull();
  });

  it('creates Access Explorer only when its tab is first opened', async () => {
    const element = await render();
    expect(one(element, 'c-access-explorer')).toBeNull();

    await activate(element, 'accessExplorer');

    expect(one(element, 'c-access-explorer')).not.toBeNull();
  });

  it('opens Access Explorer when the page is opened for it from the Access page', async () => {
    const element = await render();
    navigation.CurrentPageReference.emit({ state: { c__section: 'accessExplorer' } });
    await flush();
    expect(one(element, 'c-access-explorer')).toBeNull();

    getOpenLink.emit({ url: '/x', stateKey: 'c__section', section: 'accessExplorer' });
    await flush();

    expect(one(element, 'lightning-tabset').activeTabValue).toBe('accessExplorer');
    expect(one(element, 'c-access-explorer')).not.toBeNull();
  });

  it('stays on the Overview when the page names no section', async () => {
    const element = await render();
    getOpenLink.emit({ url: '/x', stateKey: 'c__section', section: 'accessExplorer' });
    navigation.CurrentPageReference.emit({ state: {} });
    await flush();

    expect(one(element, 'lightning-tabset').activeTabValue).toBe('overview');
  });

  it('creates the AI-Readiness Export only when its tab is first opened', async () => {
    const element = await render();
    expect(one(element, 'c-ai-readiness-export')).toBeNull();

    await activate(element, 'aiExport');

    expect(one(element, 'c-ai-readiness-export')).not.toBeNull();
  });

  it('opens a section from its Overview tile', async () => {
    const element = await render();

    one(element, 'c-barn-tool-grid').dispatchEvent(
      new CustomEvent('select', { detail: { name: 'fieldUtilization' } })
    );
    await flush();

    expect(one(element, 'lightning-tabset').activeTabValue).toBe('fieldUtilization');
    expect(one(element, 'c-field-utilization')).not.toBeNull();
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

  // Owner QA 2026-10-31: the tile said Warnings: 2 while the section said Health Check had not
  // run. With a stored run, the section shows that run (no new run) so the two agree.
  it('shows the stored run in the Health Check section without running it', async () => {
    getLastRun.mockResolvedValue({ ranAt: '2026-10-28T10:00:00Z', errors: 0, warnings: 2 });
    const element = await render();

    await activate(element, 'healthCheck');
    const panel = one(element, 'c-health-check-panel');
    expect(panel).not.toBeNull();
    expect(panel.lastResultFirst).toBe(true);
    expect(one(element, 'c-barn-empty-state[data-id="health-check-empty"]')).toBeNull();
    expect(getReport).not.toHaveBeenCalled();
  });

  it('reads setup changes only when their section is opened', async () => {
    getChangeSummary.mockResolvedValue({ keptCount: 0, sections: [], pageRows: 200 });
    getChanges.mockResolvedValue({ rows: [], more: false, scanStopped: false });
    const element = await render();
    expect(getChangeSummary).not.toHaveBeenCalled();

    await activate(element, 'setupChanges');
    expect(one(element, 'c-setup-change-log')).not.toBeNull();
    expect(getChangeSummary).toHaveBeenCalledTimes(1);
  });

  it('runs Health Check only when asked, and refreshes its badge back on the Overview', async () => {
    const element = await render();

    await activate(element, 'healthCheck');
    expect(one(element, 'c-health-check-panel')).toBeNull();
    expect(one(element, 'c-barn-empty-state[data-id="health-check-empty"]')).not.toBeNull();
    expect(getReport).not.toHaveBeenCalled();

    one(element, 'lightning-button[data-id="run-health-check"]').click();
    await flush();

    expect(one(element, 'c-health-check-panel')).not.toBeNull();
    expect(getReport).toHaveBeenCalledTimes(1);

    getLastRun.mockResolvedValue({ ranAt: '2026-10-28T10:00:00Z', errors: 0, warnings: 0 });
    await activate(element, 'overview');
    expect(tileNamed(element, 'healthCheck')).toMatchObject({
      badgeLabel: 'Passed',
      badgeVariant: 'success'
    });
  });
});
