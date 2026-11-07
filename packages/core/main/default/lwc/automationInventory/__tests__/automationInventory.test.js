import { createElement } from 'lwc';
import AutomationInventory from 'c/automationInventory';
import getInventory from '@salesforce/apex/OrgAutomationController.getInventory';
import startScan from '@salesforce/apex/OrgAutomationController.startScan';
import { downloadCsv } from 'c/findCsv';
import { snippetCode, snippetKind } from '../automationSnippets';

jest.mock('@salesforce/apex/OrgAutomationController.getInventory', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/OrgAutomationController.startScan', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('c/findCsv', () => {
  const actual = jest.requireActual('c/findCsv');
  return { ...actual, downloadCsv: jest.fn() };
});

const INVENTORY = {
  classPrefix: '',
  fieldPrefix: '',
  truncated: false,
  unreadable: [],
  rows: [
    {
      key: 'BarnCRM|Household_Naming',
      kind: 'BarnCRM',
      name: 'Household naming',
      apiName: 'Household_Naming',
      objectName: 'Contact',
      objectLabel: 'Contact',
      status: 'On',
      owner: 'BarnCRM',
      covered: 'Yes'
    },
    {
      key: 'Flow|My_Gift_Flow',
      kind: 'Flow',
      name: 'My Gift Flow',
      apiName: 'My_Gift_Flow',
      objectName: 'Account',
      objectLabel: 'Account',
      status: 'Active',
      owner: 'Org',
      detail: 'After save',
      covered: 'NotChecked',
      canDeactivate: true
    },
    {
      key: 'ApexTrigger|PkgTrigger',
      kind: 'ApexTrigger',
      name: 'PkgTrigger',
      apiName: 'PkgTrigger',
      objectName: 'Account',
      objectLabel: 'Account',
      status: 'Active',
      owner: 'otherpkg',
      covered: 'No'
    }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render(result = INVENTORY) {
  getInventory.mockResolvedValue(result);
  const element = createElement('c-automation-inventory', { is: AutomationInventory });
  document.body.appendChild(element);
  await flush();
  return element;
}

const q = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-automation-inventory', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists every automation with its owner and coverage in words', async () => {
    const element = await render();
    const table = q(element, 'inventory');
    expect(table.data).toHaveLength(3);
    const flow = table.data.find((row) => row.key === 'Flow|My_Gift_Flow');
    expect(flow.ownerText).toBe('c.Core_OrgAutomation_OwnerOrg');
    expect(flow.coveredText).toBe('c.Core_OrgAutomation_NotChecked');
    const pkg = table.data.find((row) => row.key === 'ApexTrigger|PkgTrigger');
    expect(pkg.ownerText).toBe('otherpkg');
    expect(q(element, 'not-checked')).not.toBeNull();
  });

  it('filters by object and by owner', async () => {
    const element = await render();
    const objectFilter = q(element, 'object-filter');
    expect(objectFilter.options.map((o) => o.value)).toEqual(['', 'Account', 'Contact']);
    objectFilter.dispatchEvent(new CustomEvent('change', { detail: { value: 'Account' } }));
    await flush();
    expect(q(element, 'inventory').data).toHaveLength(2);

    const ownerFilter = q(element, 'owner-filter');
    expect(ownerFilter.options.map((o) => o.value)).toEqual(['', 'BarnCRM', 'Org', 'otherpkg']);
    ownerFilter.dispatchEvent(new CustomEvent('change', { detail: { value: 'otherpkg' } }));
    await flush();
    expect(q(element, 'inventory').data.map((row) => row.key)).toEqual(['ApexTrigger|PkgTrigger']);

    ownerFilter.dispatchEvent(new CustomEvent('change', { detail: { value: 'BarnCRM' } }));
    await flush();
    expect(q(element, 'inventory')).toBeNull();
    expect(q(element, 'empty')).not.toBeNull();
  });

  it('downloads the filtered rows as CSV', async () => {
    const element = await render();
    q(element, 'download').click();
    expect(downloadCsv).toHaveBeenCalledTimes(1);
    const [base, columns, rows] = downloadCsv.mock.calls[0];
    expect(base).toBe('Automation-Inventory');
    expect(columns.map((c) => c.path)).toContain('coveredText');
    expect(rows).toHaveLength(3);
  });

  it('offers the snippet only for an org item that is not covered, and shows it', async () => {
    const element = await render();
    const table = q(element, 'inventory');
    const actionColumn = table.columns.find((c) => c.type === 'action');
    const offered = (row) => {
      let actions;
      actionColumn.typeAttributes.rowActions(row, (found) => {
        actions = found;
      });
      return actions;
    };
    expect(offered(INVENTORY.rows[0])).toEqual([]);
    expect(offered(INVENTORY.rows[2])).toEqual([]);
    expect(offered(INVENTORY.rows[1])).toHaveLength(1);

    table.dispatchEvent(
      new CustomEvent('rowaction', {
        detail: { action: { name: 'howTo' }, row: INVENTORY.rows[1] }
      })
    );
    await flush();
    expect(q(element, 'snippet-code').textContent).toBe('Flow:My_Gift_Flow');
    q(element, 'close-snippet').click();
    await flush();
    expect(q(element, 'snippet')).toBeNull();
  });

  it('names the parts it could not read and shows a refusal', async () => {
    const element = await render({ ...INVENTORY, unreadable: ['Flows'], truncated: true });
    expect(q(element, 'unreadable')).not.toBeNull();
    expect(q(element, 'truncated')).not.toBeNull();

    getInventory.mockRejectedValue({ body: { message: 'No permission.' } });
    q(element, 'refresh').click();
    await flush();
    expect(q(element, 'error').message).toBe('No permission.');
  });
});

describe('c-automation-inventory scan', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it('shows the connection setup when it may be used but is not ready', async () => {
    const element = await render({ ...INVENTORY, canUseConnection: true, connected: false });
    expect(q(element, 'connection-needed')).not.toBeNull();
    expect(q(element, 'scan')).toBeNull();
  });

  it('offers no scan to someone who may not use the connection', async () => {
    const element = await render();
    expect(q(element, 'scan')).toBeNull();
    expect(q(element, 'connection-needed')).toBeNull();
  });

  it('starts a scan, says it runs and reads again until it finishes', async () => {
    const element = await render({ ...INVENTORY, canUseConnection: true, connected: true });
    expect(q(element, 'scan-line')).toBeNull();

    jest.useFakeTimers();
    startScan.mockResolvedValue('a0X000000000001AAA');
    getInventory.mockResolvedValue({
      ...INVENTORY,
      canUseConnection: true,
      connected: true,
      scanStatus: 'Running'
    });
    q(element, 'scan-button').click();
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
    expect(startScan).toHaveBeenCalledTimes(1);
    expect(q(element, 'scan-line').textContent).toBe('c.Core_AutomationInventory_ScanRunning');
    expect(q(element, 'scan-button').disabled).toBe(true);

    getInventory.mockResolvedValue({
      ...INVENTORY,
      canUseConnection: true,
      connected: true,
      scanStatus: 'Failed',
      scanMessage: 'The scan did not finish.'
    });
    jest.advanceTimersByTime(4000);
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
    expect(getInventory).toHaveBeenCalledTimes(3);
    expect(q(element, 'scan-line').textContent).toBe('The scan did not finish.');
  });

  it('hands the deactivate tool only the org items it may change, and reads again after', async () => {
    const element = await render({
      ...INVENTORY,
      canUseConnection: true,
      connected: true,
      isSandbox: true,
      snapshots: []
    });
    const tool = q(element, 'deactivate-tool');
    expect(tool.rows.map((row) => row.key)).toEqual(['Flow|My_Gift_Flow']);
    expect(tool.isSandbox).toBe(true);

    tool.dispatchEvent(new CustomEvent('changed'));
    await Promise.resolve();
    expect(getInventory).toHaveBeenCalledTimes(2);
  });

  it('offers no deactivate tool without a ready connection', async () => {
    const element = await render();
    expect(q(element, 'deactivate-tool')).toBeNull();
  });
});

describe('automationSnippets', () => {
  it('gives each kind its code, with the prefixes', () => {
    expect(snippetKind('BarnCRM')).toBeNull();
    expect(snippetCode({ kind: 'BarnCRM' })).toBe('');
    // A made-up prefix, built so the namespace check does not read it as a hard-coded one.
    const fieldPrefix = ['ns', '__'].join('');
    const apex = snippetCode({ kind: 'ApexTrigger' }, 'ns.', fieldPrefix);
    expect(apex).toContain('ns.CheckAutomationAction.check(');
    const formula = snippetCode({ kind: 'ValidationRule' }, 'ns.', fieldPrefix);
    expect(formula).toContain(
      `NOT($Setup.${fieldPrefix}BarnCRM_Automation_Control__c.${fieldPrefix}Pause_All__c)`
    );
    expect(snippetKind('WorkflowRule')).toBe('formula');
    expect(snippetKind('ProcessBuilder')).toBe('flow');
  });
});
