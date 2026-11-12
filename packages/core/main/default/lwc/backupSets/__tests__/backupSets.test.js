import { createElement } from 'lwc';
import BackupSets from 'c/backupSets';
import getPage from '@salesforce/apex/BackupSetController.getPage';
import setBackup from '@salesforce/apex/BackupSetController.setBackup';
import runNow from '@salesforce/apex/BackupSetController.runNow';

jest.mock('@salesforce/apex/BackupSetController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BackupSetController.setBackup', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BackupSetController.runNow', () => ({ default: jest.fn() }), {
  virtual: true
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const PAGE = {
  rowLimit: 50000,
  sets: [{ id: 'q1', name: 'Volunteers', objectName: 'Contact', ownerName: 'Maria', mine: true }],
  candidates: [{ id: 'q2', name: 'Donors', objectName: 'Contact', mine: true }],
  runs: [
    {
      id: 'j1',
      name: 'IB-0001',
      setName: 'Volunteers',
      status: 'Complete',
      running: false,
      rows: 30,
      fileId: '069000000000001',
      fileName: 'Contact-2026-11-11-abc123-part-1'
    }
  ]
};

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function render(page = PAGE) {
  getPage.mockResolvedValue(page);
  const element = createElement('c-backup-sets', { is: BackupSets });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-backup-sets', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the sets, the queries to add and the runs with their first file', async () => {
    const element = await render();
    expect(one(element, 'sets').textContent).toContain('Volunteers');
    expect(one(element, 'choose').options).toEqual([{ label: 'Donors', value: 'q2' }]);
    const file = one(element, 'file');
    expect(file.href).toContain('/lightning/r/ContentDocument/069000000000001/view');
    expect(file.textContent).toBe('Contact-2026-11-11-abc123-part-1');
    expect(one(element, 'limit').textContent).toContain('c.Core_BackupSets_Limit');
  });

  it('runs a set now and says the file comes later', async () => {
    runNow.mockResolvedValue(PAGE);
    const element = await render();
    element.shadowRoot.querySelector('[data-action="run"]').click();
    await flush();
    expect(runNow).toHaveBeenCalledWith({ queryId: 'q1' });
    expect(one(element, 'notice').message).toBe('c.Core_BackupSets_Started');
  });

  it('adds the chosen query and removes a set', async () => {
    setBackup.mockResolvedValue(PAGE);
    const element = await render();
    const choose = one(element, 'choose');
    choose.dispatchEvent(new CustomEvent('change', { detail: { value: 'q2' } }));
    await flush();
    one(element, 'add-button').click();
    await flush();
    expect(setBackup).toHaveBeenCalledWith({ queryId: 'q2', asSet: true });

    element.shadowRoot.querySelector('[data-action="remove"]').click();
    await flush();
    expect(setBackup).toHaveBeenLastCalledWith({ queryId: 'q1', asSet: false });
  });

  it('shows a refusal as it came and an empty state with no sets', async () => {
    getPage.mockRejectedValue({ body: { message: 'Backup Sets need Manage BarnCRM Settings.' } });
    const element = createElement('c-backup-sets', { is: BackupSets });
    document.body.appendChild(element);
    await flush();
    expect(one(element, 'error').message).toBe('Backup Sets need Manage BarnCRM Settings.');

    const empty = await render({ rowLimit: 10, sets: [], candidates: [], runs: [] });
    expect(one(empty, 'none')).not.toBeNull();
    expect(one(empty, 'runs-none')).not.toBeNull();
  });
});
