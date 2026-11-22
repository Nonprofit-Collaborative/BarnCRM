import { createElement } from 'lwc';
import ArchivedRecords from 'c/archivedRecords';
import getArchive from '@salesforce/apex/ArchiveController.getArchive';
import getArchivedRows from '@salesforce/apex/ArchiveController.getArchivedRows';
import getArchivedRow from '@salesforce/apex/ArchiveController.getArchivedRow';
import restoreArchivedRows from '@salesforce/apex/ArchiveController.restoreArchivedRows';
import BarnConfirmModal from 'c/barnConfirmModal';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/ArchiveController.getArchive', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ArchiveController.getArchivedRows', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ArchiveController.getArchivedRow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ArchiveController.restoreArchivedRows',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('c/barnConfirmModal', () => ({ __esModule: true, default: { open: jest.fn() } }));

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

const VIEWER = {
  objects: [
    { name: 'Gift__c', label: 'Gift' },
    { name: 'Thing__c', label: 'Thing__c' }
  ],
  archivedCount: 12,
  cap: 1000000,
  warnAt: 900000,
  canRestore: true,
  mostRestored: 50
};

function rowsFrom(start, count) {
  const rows = [];
  for (let i = start; i < start + count; i++) {
    rows.push({
      id: `1000|006${i}`,
      originalId: `006${i}`,
      name: `Gift ${i}`,
      archivedAt: '2026-11-01T00:00:00Z'
    });
  }
  return rows;
}

function one(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function render(viewer = VIEWER) {
  getArchive.mockResolvedValue(viewer);
  const element = createElement('c-archived-records', { is: ArchivedRecords });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-archived-records', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says viewers see every field and lists the archived objects', async () => {
    const element = await render();
    expect(one(element, 'every-field').message).toBe('c.Core_ArchiveViewer_EveryField');
    const picker = one(element, 'object');
    expect(picker.value).toBe('Gift__c');
    expect(picker.options.map((option) => option.label)).toEqual(['Gift (Gift__c)', 'Thing__c']);
    expect(one(element, 'usage')).not.toBeNull();
    await expectAccessible(element);
  });

  it('says when nothing is archived', async () => {
    const element = await render({ ...VIEWER, objects: [] });
    expect(one(element, 'no-objects')).not.toBeNull();
    expect(one(element, 'filters')).toBeNull();
  });

  it('shows the refusal for a person without the grant', async () => {
    getArchive.mockRejectedValue({ body: { message: 'No access' } });
    const element = createElement('c-archived-records', { is: ArchivedRecords });
    document.body.appendChild(element);
    await flush();
    expect(one(element, 'error').message).toBe('No access');
  });

  it('reads rows by object and date range, pages on and back', async () => {
    const element = await render();
    const from = one(element, 'from');
    from.value = '2026-01-01';
    from.dispatchEvent(new CustomEvent('change'));
    getArchivedRows.mockResolvedValueOnce({ rows: rowsFrom(0, 2), more: true });
    one(element, 'show').click();
    await flush();
    expect(getArchivedRows).toHaveBeenLastCalledWith({
      objectName: 'Gift__c',
      fromDay: '2026-01-01',
      toDay: null,
      afterRowId: null
    });
    expect(one(element, 'rows').data).toHaveLength(2);
    expect(one(element, 'previous').disabled).toBe(true);

    getArchivedRows.mockResolvedValueOnce({ rows: rowsFrom(2, 1), more: false });
    one(element, 'next').click();
    await flush();
    expect(getArchivedRows).toHaveBeenLastCalledWith(
      expect.objectContaining({ afterRowId: '1000|0061' })
    );
    expect(one(element, 'next').disabled).toBe(true);

    getArchivedRows.mockResolvedValueOnce({ rows: rowsFrom(0, 2), more: true });
    one(element, 'previous').click();
    await flush();
    expect(getArchivedRows).toHaveBeenLastCalledWith(expect.objectContaining({ afterRowId: null }));
    await expectAccessible(element);
  });

  it('says when the range holds no rows', async () => {
    const element = await render();
    getArchivedRows.mockResolvedValueOnce({ rows: [], more: false });
    one(element, 'show').click();
    await flush();
    expect(one(element, 'no-rows')).not.toBeNull();
  });

  it('shows a row fields and related records from its JSON', async () => {
    const element = await render();
    getArchivedRows.mockResolvedValueOnce({ rows: rowsFrom(0, 1), more: false });
    one(element, 'show').click();
    await flush();
    getArchivedRow.mockResolvedValue({
      id: '1000|0060',
      name: 'Gift 0',
      fields: [{ name: 'Amount', label: 'Amount', value: '50' }],
      children: [{ objectName: 'Note__c', label: 'Note', count: 2 }]
    });
    one(element, 'rows').dispatchEvent(
      new CustomEvent('rowaction', {
        detail: { action: { name: 'view' }, row: { id: '1000|0060', name: 'Gift 0' } }
      })
    );
    await flush();
    expect(getArchivedRow).toHaveBeenCalledWith({ objectName: 'Gift__c', rowId: '1000|0060' });
    expect(one(element, 'fields').textContent).toContain('50');
    expect(one(element, 'related').textContent).toContain('c.Core_ArchiveViewer_RelatedCount');
    await expectAccessible(element);
    one(element, 'close').click();
    await flush();
    expect(one(element, 'detail')).toBeNull();
  });

  it('restores the chosen rows after a confirmation that names new Ids', async () => {
    const element = await render();
    getArchivedRows.mockResolvedValueOnce({ rows: rowsFrom(0, 2), more: false });
    one(element, 'show').click();
    await flush();
    expect(one(element, 'restore').disabled).toBe(true);
    one(element, 'rows').dispatchEvent(
      new CustomEvent('rowselection', { detail: { selectedRows: [{ id: '1000|0060' }] } })
    );
    await flush();
    expect(one(element, 'restore').disabled).toBe(false);

    BarnConfirmModal.open.mockResolvedValueOnce(false);
    one(element, 'restore').click();
    await flush();
    expect(restoreArchivedRows).not.toHaveBeenCalled();

    BarnConfirmModal.open.mockResolvedValueOnce(true);
    restoreArchivedRows.mockResolvedValue('a0J000000000001');
    one(element, 'restore').click();
    await flush();
    expect(BarnConfirmModal.open.mock.calls[1][0].message).toBe(
      'c.Core_ArchiveViewer_RestoreConfirm'
    );
    expect(restoreArchivedRows).toHaveBeenCalledWith({
      objectName: 'Gift__c',
      rowIds: ['1000|0060']
    });
    expect(one(element, 'notice')).not.toBeNull();
  });

  it('shows a restore refusal', async () => {
    const element = await render();
    getArchivedRows.mockResolvedValueOnce({ rows: rowsFrom(0, 1), more: false });
    one(element, 'show').click();
    await flush();
    one(element, 'rows').dispatchEvent(
      new CustomEvent('rowselection', { detail: { selectedRows: [{ id: '1000|0060' }] } })
    );
    BarnConfirmModal.open.mockResolvedValueOnce(true);
    restoreArchivedRows.mockRejectedValue({ body: { message: 'Refused' } });
    one(element, 'restore').click();
    await flush();
    expect(one(element, 'error').message).toBe('Refused');
  });

  it('offers no selection or Restore to a viewer who may not restore', async () => {
    const element = await render({ ...VIEWER, canRestore: false });
    getArchivedRows.mockResolvedValueOnce({ rows: rowsFrom(0, 1), more: false });
    one(element, 'object').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Thing__c' } })
    );
    one(element, 'show').click();
    await flush();
    expect(getArchivedRows).toHaveBeenLastCalledWith(
      expect.objectContaining({ objectName: 'Thing__c' })
    );
    expect(one(element, 'rows').hideCheckboxColumn).toBe(true);
    expect(one(element, 'restore')).toBeNull();
  });
});
