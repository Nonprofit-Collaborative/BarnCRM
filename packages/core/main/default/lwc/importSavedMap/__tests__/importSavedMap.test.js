import { createElement } from 'lwc';
import ImportSavedMap from 'c/importSavedMap';
import listMaps from '@salesforce/apex/MapController.listMaps';
import loadMap from '@salesforce/apex/MapController.loadMap';
import saveMap from '@salesforce/apex/MapController.saveMap';
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

const MAP_ID = 'a0X000000000001AAA';
const SAVED = {
  recordId: MAP_ID,
  name: 'Sign-ups',
  definitionJson: JSON.stringify({
    version: 4,
    from: { kind: 'columns' },
    to: { kind: 'record', object: 'Contact' },
    columns: [
      { source: 'E-mail', target: 'Email', transforms: [{ op: 'trim' }] },
      { source: 'Org', target: 'AccountId', lookupField: 'Name' },
      { source: 'Not In File', target: 'LastName' },
      { source: 'Phone', target: 'Not_Allowed__c' }
    ]
  })
};

const COLUMNS = [
  { source: 'e-mail', target: '', transforms: [] },
  { source: 'Org', target: '', transforms: [] },
  { source: 'Notes', target: 'Description', transforms: [] }
];

function createComponent(props = {}) {
  const element = createElement('c-import-saved-map', { is: ImportSavedMap });
  Object.assign(element, {
    columns: COLUMNS,
    mappingDocument: JSON.stringify({
      version: 2,
      columns: [
        { source: 'e-mail', target: 'Email', transforms: [] },
        { source: 'Skip me', target: '__ignore__' }
      ]
    }),
    objectName: 'Contact',
    allowedTargets: ['Email', 'AccountId', 'LastName', 'Description'],
    lookupChoices: { AccountId: ['Id', 'Name'] },
    ignoredValues: ['__ignore__'],
    ...props
  });
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

describe('c-import-saved-map', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers only Save as Map when there are no maps', async () => {
    listMaps.mockResolvedValue([]);
    const element = createComponent();
    await flush();

    expect(find(element, 'choose')).toBeNull();
    expect(find(element, 'save').disabled).toBe(true);
    await expectAccessible(element);
  });

  it('copies a saved map onto the file columns and says what did not fit', async () => {
    listMaps.mockResolvedValue([{ recordId: MAP_ID, name: 'Sign-ups' }]);
    loadMap.mockResolvedValue(SAVED);
    const element = createComponent();
    const handler = jest.fn();
    element.addEventListener('apply', handler);
    await flush();

    const choose = find(element, 'choose');
    expect(choose.options).toEqual([{ label: 'Sign-ups', value: MAP_ID }]);
    expect(find(element, 'use').disabled).toBe(true);
    choose.dispatchEvent(new CustomEvent('change', { detail: { value: MAP_ID } }));
    await flush();
    find(element, 'use').click();
    await flush();

    expect(loadMap).toHaveBeenCalledWith({ recordId: MAP_ID });
    const columns = handler.mock.calls[0][0].detail.columns;
    expect(columns[0]).toMatchObject({
      source: 'e-mail',
      target: 'Email',
      transforms: [{ op: 'trim' }]
    });
    expect(columns[1]).toMatchObject({ source: 'Org', target: 'AccountId', lookupField: 'Name' });
    expect(columns[2]).toMatchObject({ source: 'Notes', target: 'Description' });
    // Two lines applied; one names a column the file lacks and one a field the template refuses.
    expect(find(element, 'message').textContent).toBe('c.Core_ImportSavedMap_UsedSome');
    await expectAccessible(element);
  });

  it('saves the columns shown as a new map, leaving out ignored columns', async () => {
    listMaps.mockResolvedValue([]);
    saveMap.mockResolvedValue({ recordId: MAP_ID, name: 'From import' });
    const element = createComponent();
    await flush();

    const name = find(element, 'name');
    name.dispatchEvent(new CustomEvent('change', { detail: { value: 'From import' } }));
    await flush();
    expect(find(element, 'save').disabled).toBe(false);
    find(element, 'save').click();
    await flush();

    const call = saveMap.mock.calls[0][0];
    expect(call.recordId).toBeNull();
    expect(call.name).toBe('From import');
    const saved = JSON.parse(call.definitionJson);
    expect(saved.version).toBe(4);
    expect(saved.to).toEqual({ kind: 'record', object: 'Contact' });
    expect(saved.columns.map((column) => column.target)).toEqual(['Email']);
    expect(listMaps).toHaveBeenCalledTimes(2);
    expect(find(element, 'message').textContent).toBe('c.Core_ImportSavedMap_Saved');
  });

  it('shows the server message when a save is refused', async () => {
    listMaps.mockResolvedValue([]);
    saveMap.mockRejectedValue({ body: { message: 'A map named From import already exists.' } });
    const element = createComponent();
    await flush();

    find(element, 'name').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'From import' } })
    );
    await flush();
    find(element, 'save').click();
    await flush();

    expect(find(element, 'error').message).toBe('A map named From import already exists.');
  });
});
