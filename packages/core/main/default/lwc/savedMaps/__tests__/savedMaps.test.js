import { createElement } from 'lwc';
import SavedMaps from 'c/savedMaps';
import listMaps from '@salesforce/apex/MapController.listMaps';
import loadMap from '@salesforce/apex/MapController.loadMap';
import saveMap from '@salesforce/apex/MapController.saveMap';
import renameMap from '@salesforce/apex/MapController.renameMap';
import deleteMap from '@salesforce/apex/MapController.deleteMap';
import mapUsers from '@salesforce/apex/MapController.mapUsers';
import BarnConfirmModal from 'c/barnConfirmModal';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/MapController.listMaps', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MapController.loadMap', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MapController.saveMap', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MapController.renameMap', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MapController.deleteMap', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MapController.mapUsers', () => ({ default: jest.fn() }), {
  virtual: true
});
// The Mapper inside: its own Apex answers with nothing, so it renders empty.
jest.mock(
  '@salesforce/apex/MapController.getObjects',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/MapController.getTargetFields',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/MapController.previewMap',
  () => ({ default: jest.fn(() => Promise.resolve({})) }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/FindController.listObjects',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/QueryFieldCatalog.getObjectInfo',
  () => ({ default: jest.fn(() => Promise.resolve({})) }),
  {
    virtual: true
  }
);

const MAP_ID = 'a0X000000000001AAA';
const MAPS = [
  { recordId: MAP_ID, name: 'Sign-ups', objectName: 'Contact', objectLabel: 'Contact' },
  { recordId: 'a0X000000000002AAA', name: 'Webhook body', objectName: null, objectLabel: null }
];
const DEFINITION = JSON.stringify({
  version: 4,
  from: { kind: 'columns' },
  to: { kind: 'record', object: 'Contact' },
  columns: [{ source: 'E-mail', target: 'Record.Email' }]
});

function createComponent() {
  const element = createElement('c-saved-maps', { is: SavedMaps });
  document.body.appendChild(element);
  return element;
}

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function findAll(element, id) {
  return Array.from(element.shadowRoot.querySelectorAll(`[data-id="${id}"]`));
}

describe('c-saved-maps', () => {
  beforeEach(() => {
    listMaps.mockResolvedValue(MAPS);
    loadMap.mockResolvedValue({ recordId: MAP_ID, name: 'Sign-ups', definitionJson: DEFINITION });
    mapUsers.mockResolvedValue([]);
    BarnConfirmModal.open.mockResolvedValue(true);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists every map with what it fills', async () => {
    const element = createComponent();
    await flush();

    const rows = findAll(element, 'map-row');
    expect(rows.length).toBe(2);
    expect(rows[0].textContent).toContain('Sign-ups');
    expect(rows[0].textContent).toContain('Contact');
    expect(rows[1].textContent).toContain('c.Core_SavedMaps_FillsOther');
    await expectAccessible(element);
  });

  it('says there are no maps yet', async () => {
    listMaps.mockResolvedValue([]);
    const element = createComponent();
    await flush();

    expect(find(element, 'empty')).not.toBeNull();
  });

  it('opens a new map and saves it once it has a name', async () => {
    saveMap.mockResolvedValue({ recordId: MAP_ID, name: 'Fresh' });
    const element = createComponent();
    await flush();

    find(element, 'new').click();
    await flush();
    expect(find(element, 'mapper')).not.toBeNull();
    expect(find(element, 'save').disabled).toBe(true);

    find(element, 'name').dispatchEvent(new CustomEvent('change', { detail: { value: 'Fresh' } }));
    find(element, 'mapper').dispatchEvent(
      new CustomEvent('change', {
        detail: { document: DEFINITION, pendingGuesses: 0, problems: 0 }
      })
    );
    await flush();
    expect(find(element, 'save').disabled).toBe(false);
    find(element, 'save').click();
    await flush();

    expect(saveMap).toHaveBeenCalledWith({
      recordId: null,
      name: 'Fresh',
      definitionJson: DEFINITION
    });
    expect(BarnConfirmModal.open).not.toHaveBeenCalled();
    expect(find(element, 'mapper')).toBeNull();
    expect(find(element, 'notice').message).toBe('c.Core_SavedMaps_Saved');
  });

  it('waits while a best guess is unchecked', async () => {
    const element = createComponent();
    await flush();

    find(element, 'new').click();
    await flush();
    find(element, 'name').dispatchEvent(new CustomEvent('change', { detail: { value: 'Fresh' } }));
    find(element, 'mapper').dispatchEvent(
      new CustomEvent('change', {
        detail: { document: DEFINITION, pendingGuesses: 2, problems: 0 }
      })
    );
    await flush();

    expect(find(element, 'save').disabled).toBe(true);
    expect(find(element, 'blocked').textContent).toBe('c.Core_SavedMaps_Waiting');
  });

  it('lists the tools that use a map and asks before a change reaches them', async () => {
    mapUsers.mockResolvedValue([{ kindLabel: 'Connector', name: 'Mailing list sync' }]);
    saveMap.mockResolvedValue({ recordId: MAP_ID, name: 'Sign-ups' });
    const element = createComponent();
    await flush();

    findAll(element, 'open')[0].click();
    await flush();
    expect(loadMap).toHaveBeenCalledWith({ recordId: MAP_ID });
    expect(mapUsers).toHaveBeenCalledWith({ recordId: MAP_ID });
    const users = find(element, 'users');
    expect(users.message).toBe('c.Core_SavedMaps_UsedBy');
    expect(users.textContent).toContain('c.Core_SavedMaps_UserLine');

    find(element, 'save').click();
    await flush();
    expect(BarnConfirmModal.open).toHaveBeenCalledTimes(1);
    expect(saveMap.mock.calls[0][0].recordId).toBe(MAP_ID);
    await expectAccessible(element);
  });

  it('does not save when the change is not confirmed', async () => {
    mapUsers.mockResolvedValue([{ kindLabel: 'Connector', name: 'Mailing list sync' }]);
    BarnConfirmModal.open.mockResolvedValue(false);
    const element = createComponent();
    await flush();

    findAll(element, 'open')[0].click();
    await flush();
    find(element, 'save').click();
    await flush();

    expect(saveMap).not.toHaveBeenCalled();
    expect(find(element, 'mapper')).not.toBeNull();
  });

  it('renames a map in its row', async () => {
    renameMap.mockResolvedValue({ recordId: MAP_ID, name: 'Event sign-ups' });
    const element = createComponent();
    await flush();

    findAll(element, 'rename')[0].click();
    await flush();
    const input = find(element, 'rename-input');
    expect(input.value).toBe('Sign-ups');
    input.dispatchEvent(new CustomEvent('change', { detail: { value: 'Event sign-ups' } }));
    find(element, 'rename-save').click();
    await flush();

    expect(renameMap).toHaveBeenCalledWith({ recordId: MAP_ID, name: 'Event sign-ups' });
    expect(find(element, 'rename-input')).toBeNull();
    expect(listMaps).toHaveBeenCalledTimes(2);
  });

  it('deletes a map only after it is confirmed', async () => {
    const element = createComponent();
    await flush();

    BarnConfirmModal.open.mockResolvedValueOnce(false);
    findAll(element, 'delete')[0].click();
    await flush();
    expect(deleteMap).not.toHaveBeenCalled();

    findAll(element, 'delete')[0].click();
    await flush();
    expect(deleteMap).toHaveBeenCalledWith({ recordId: MAP_ID });
    expect(BarnConfirmModal.open.mock.calls[1][0].message).toBe('c.Core_SavedMaps_DeleteConfirm');
  });

  it('names the tools that use a map before it is renamed or deleted', async () => {
    mapUsers.mockResolvedValue([{ kindLabel: 'Connector', name: 'Mailing list sync' }]);
    renameMap.mockResolvedValue({ recordId: MAP_ID, name: 'Event sign-ups' });
    const element = createComponent();
    await flush();

    BarnConfirmModal.open.mockResolvedValueOnce(false);
    findAll(element, 'rename')[0].click();
    await flush();
    find(element, 'rename-save').click();
    await flush();
    expect(mapUsers).toHaveBeenCalledWith({ recordId: MAP_ID });
    expect(BarnConfirmModal.open.mock.calls[0][0].message).toBe(
      'c.Core_SavedMaps_RenameUsedConfirm'
    );
    expect(renameMap).not.toHaveBeenCalled();
    find(element, 'rename-save').click();
    await flush();
    expect(renameMap).toHaveBeenCalled();

    findAll(element, 'delete')[0].click();
    await flush();
    expect(BarnConfirmModal.open.mock.calls[2][0].message).toBe(
      'c.Core_SavedMaps_DeleteUsedConfirm'
    );
    expect(deleteMap).toHaveBeenCalledWith({ recordId: MAP_ID });
  });

  it('renames without asking when no tool uses the map', async () => {
    renameMap.mockResolvedValue({ recordId: MAP_ID, name: 'Event sign-ups' });
    const element = createComponent();
    await flush();

    findAll(element, 'rename')[0].click();
    await flush();
    find(element, 'rename-save').click();
    await flush();
    expect(BarnConfirmModal.open).not.toHaveBeenCalled();
    expect(renameMap).toHaveBeenCalled();
  });

  it('shows the server message when a map cannot be opened', async () => {
    loadMap.mockRejectedValue({ body: { message: 'This map was not found.' } });
    const element = createComponent();
    await flush();

    findAll(element, 'open')[0].click();
    await flush();

    expect(find(element, 'error').message).toBe('This map was not found.');
  });
});
