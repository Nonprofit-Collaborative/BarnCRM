import { createElement } from 'lwc';
import AutomationDeactivate from 'c/automationDeactivate';
import deactivate from '@salesforce/apex/OrgAutomationController.deactivate';
import restore from '@salesforce/apex/OrgAutomationController.restore';
import BarnConfirmModal from 'c/barnConfirmModal';

jest.mock('@salesforce/apex/OrgAutomationController.deactivate', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/OrgAutomationController.restore', () => ({ default: jest.fn() }), {
  virtual: true
});

const ROWS = [
  {
    key: 'Flow|My_Gift_Flow',
    kind: 'Flow',
    recordId: '300000000000001AAA',
    name: 'My Gift Flow',
    objectName: 'Account',
    objectLabel: 'Account',
    typeText: 'Flow',
    canDeactivate: true
  },
  {
    key: 'ValidationRule|03d000000000001AAA',
    kind: 'ValidationRule',
    recordId: '03d000000000001AAA',
    name: 'Amount_Required',
    objectName: 'Account',
    objectLabel: 'Account',
    typeText: 'Validation rule',
    canDeactivate: true
  }
];

const SNAPSHOT = {
  id: 'a0X000000000001AAA',
  name: 'ASN-000001',
  status: 'Partial',
  createdAt: '2026-11-06T10:00:00.000Z',
  createdBy: 'Pat Admin',
  items: [
    { kind: 'Flow', recordId: '300000000000001AAA', name: 'My Gift Flow', result: 'Changed' },
    {
      kind: 'ValidationRule',
      recordId: '03d000000000001AAA',
      name: 'Amount_Required',
      result: 'Failed',
      message: 'The formula has an error'
    }
  ]
};

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

function render(props) {
  const element = createElement('c-automation-deactivate', { is: AutomationDeactivate });
  Object.assign(element, { rows: ROWS, snapshots: [], isSandbox: false }, props);
  document.body.appendChild(element);
  return element;
}

function select(element, rows) {
  element.shadowRoot
    .querySelector('[data-id="choose"]')
    .dispatchEvent(new CustomEvent('rowselection', { detail: { selectedRows: rows } }));
}

describe('c-automation-deactivate', () => {
  beforeEach(() => {
    BarnConfirmModal.open = jest.fn().mockResolvedValue(true);
    deactivate.mockResolvedValue('a0X000000000002AAA');
    restore.mockResolvedValue('a0X000000000001AAA');
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the items it can deactivate and waits for a choice', async () => {
    const element = render();
    await flush();
    const table = element.shadowRoot.querySelector('[data-id="choose"]');
    expect(table.data).toHaveLength(2);
    expect(element.shadowRoot.querySelector('[data-id="deactivate-button"]').disabled).toBe(true);
  });

  it('asks for the typed phrase in production, then sends the chosen items', async () => {
    const element = render();
    const changed = jest.fn();
    element.addEventListener('changed', changed);
    await flush();
    select(element, [ROWS[0]]);
    await flush();
    const button = element.shadowRoot.querySelector('[data-id="deactivate-button"]');
    expect(button.disabled).toBe(false);
    button.click();
    await flush();

    const dialog = BarnConfirmModal.open.mock.calls[0][0];
    expect(dialog.typeToConfirm).toBe('c.Core_OrgAutomation_ConfirmPhrase');
    expect(dialog.details).toHaveLength(1);
    expect(dialog.items).toEqual(['My Gift Flow']);
    const sent = JSON.parse(deactivate.mock.calls[0][0].itemsJson);
    expect(sent).toEqual([
      { kind: 'Flow', recordId: '300000000000001AAA', name: 'My Gift Flow', objectName: 'Account' }
    ]);
    expect(changed).toHaveBeenCalled();
  });

  it('asks a plain confirm in a sandbox, and nothing changes when it is declined', async () => {
    BarnConfirmModal.open = jest.fn().mockResolvedValue(false);
    const element = render({ isSandbox: true });
    await flush();
    select(element, ROWS);
    await flush();
    element.shadowRoot.querySelector('[data-id="deactivate-button"]').click();
    await flush();
    const dialog = BarnConfirmModal.open.mock.calls[0][0];
    expect(dialog.typeToConfirm).toBeUndefined();
    expect(dialog.details).toHaveLength(0);
    expect(deactivate).not.toHaveBeenCalled();
  });

  it('shows each item result and restores a finished run', async () => {
    const element = render({ snapshots: [SNAPSHOT] });
    await flush();
    const items = element.shadowRoot.querySelector('[data-id="snapshot-items"]').data;
    expect(items[0].resultText).toBe('c.Core_OrgAutomation_ResultDeactivated');
    expect(items[1].resultText).toBe('c.Core_OrgAutomation_ResultFailed');
    expect(items[1].reason).toBe('The formula has an error');

    element.shadowRoot.querySelector('[data-id="restore"]').click();
    await flush();
    expect(restore).toHaveBeenCalledWith({ snapshotId: SNAPSHOT.id });
  });

  it('offers no new run or restore while one is running, and says so', async () => {
    const running = { ...SNAPSHOT, id: 'a0X000000000003AAA', status: 'Running', items: [] };
    const element = render({ snapshots: [running, SNAPSHOT] });
    await flush();
    select(element, [ROWS[0]]);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="deactivate-button"]').disabled).toBe(true);
    expect(element.shadowRoot.querySelector('[data-id="restore"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="snapshot-running"]')).not.toBeNull();
  });

  it('says why a refused run did not start', async () => {
    deactivate.mockRejectedValue({ body: { message: 'A deactivation is still running.' } });
    const element = render();
    await flush();
    select(element, [ROWS[0]]);
    await flush();
    element.shadowRoot.querySelector('[data-id="deactivate-button"]').click();
    await flush();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="deactivate-error"]').message).toBe(
      'A deactivation is still running.'
    );
  });

  it('says there is nothing to choose when no row fits', async () => {
    const element = render({ rows: [] });
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="none-to-choose"]')).not.toBeNull();
  });
});
