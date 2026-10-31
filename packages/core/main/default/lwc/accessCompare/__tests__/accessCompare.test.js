import { createElement } from 'lwc';
import AccessCompare from 'c/accessCompare';
import searchPeople from '@salesforce/apex/AccessExplorerController.searchPeople';
import searchPermissionSets from '@salesforce/apex/AccessExplorerController.searchPermissionSets';
import getAccess from '@salesforce/apex/AccessExplorerController.getAccess';
import getFieldAccess from '@salesforce/apex/AccessExplorerController.getFieldAccess';

jest.mock(
  '@salesforce/apex/AccessExplorerController.searchPeople',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/AccessExplorerController.searchPermissionSets',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/AccessExplorerController.getAccess', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/AccessExplorerController.getFieldAccess',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_AccessCompare_OnlyIn', () => ({ default: 'Only {0}: {1}.' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_AccessCompare_None', () => ({ default: 'None' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_AccessCompare_Similarity',
  () => ({ default: 'Similarity: {0}%' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Core_AccessCompare_Counts',
  () => ({ default: '{0} of {1} rows differ.' }),
  { virtual: true }
);
jest.mock('@salesforce/label/c.Core_AccessExplorer_ColRead', () => ({ default: 'Read' }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_AccessExplorer_ColEdit', () => ({ default: 'Edit' }), {
  virtual: true
});
jest.mock(
  '@salesforce/label/c.Core_AccessExplorer_Downloaded',
  () => ({ default: 'Downloaded {0} rows.' }),
  { virtual: true }
);

const PAT = {
  id: '005A',
  label: 'Pat Doe',
  detail: 'Standard User',
  isActive: true,
  sources: [],
  objects: [
    { name: 'Gift__c', label: 'Gift', read: true, edit: true },
    { name: 'Fund__c', label: 'Fund', read: true }
  ]
};
const SAM = {
  id: '005B',
  label: 'Sam Roe',
  detail: 'Standard User',
  isActive: true,
  sources: [],
  objects: [
    { name: 'Gift__c', label: 'Gift', read: true },
    { name: 'Fund__c', label: 'Fund', read: true },
    { name: 'Event__c', label: 'Event', read: true }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
const byId = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);
const sideSearch = (element, key) =>
  element.shadowRoot.querySelector(`[data-id="search"][data-side="${key}"]`);

async function type(element, key, value) {
  const search = sideSearch(element, key);
  search.value = value;
  search.dispatchEvent(new CustomEvent('change'));
  // The search waits for a pause in typing.
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  await new Promise((resolve) => setTimeout(resolve, 350));
  await flush();
}

async function pick(element, key, term, subject) {
  searchPeople.mockResolvedValueOnce([
    { id: subject.id, label: subject.label, detail: 'Standard User', isActive: true }
  ]);
  getAccess.mockResolvedValueOnce(subject);
  await type(element, key, term);
  element.shadowRoot
    .querySelector(`lightning-button[data-side="${key}"][data-value="${subject.id}"]`)
    .click();
  await flush();
  await flush();
}

async function render() {
  const element = createElement('c-access-compare', { is: AccessCompare });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-access-compare', () => {
  let csv;
  let click;

  beforeEach(() => {
    csv = undefined;
    URL.createObjectURL = jest.fn((blob) => {
      csv = blob;
      return 'blob:x';
    });
    URL.revokeObjectURL = jest.fn();
    click = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    click.mockRestore();
    jest.clearAllMocks();
  });

  it('asks for two choices before comparing', async () => {
    const element = await render();

    expect(byId(element, 'choose')).not.toBeNull();
    expect(byId(element, 'objects')).toBeNull();
    expect(byId(element, 'kind').value).toBe('person');
  });

  it('searches only from two letters and says when nothing matches', async () => {
    searchPeople.mockResolvedValue([]);
    const element = await render();

    await type(element, 'a', 'P');
    expect(searchPeople).not.toHaveBeenCalled();
    await type(element, 'a', 'Pa');
    expect(searchPeople).toHaveBeenCalledWith({ term: 'Pa' });
    expect(byId(element, 'no-matches')).not.toBeNull();
  });

  it('shows only the differences, with a similarity score, once two are chosen', async () => {
    const element = await render();
    await pick(element, 'a', 'Pat', PAT);
    expect(byId(element, 'choose')).not.toBeNull();
    await pick(element, 'b', 'Sam', SAM);

    expect(byId(element, 'choose')).toBeNull();
    expect(byId(element, 'similarity').textContent).toContain('Similarity: 50%');
    expect(byId(element, 'differences-only').checked).toBe(true);
    const rows = byId(element, 'objects').data;
    expect(rows.map((row) => row.name)).toEqual(['Event__c', 'Gift__c']);
    expect(rows[1].difference).toBe('Only Pat Doe: Edit.');
    expect(rows[0].difference).toBe('Only Sam Roe: Read.');
    expect(byId(element, 'object-count').textContent).toBe('2 of 3 rows differ.');
  });

  it('shows every row when Differences Only is cleared', async () => {
    const element = await render();
    await pick(element, 'a', 'Pat', PAT);
    await pick(element, 'b', 'Sam', SAM);

    const checkbox = byId(element, 'differences-only');
    checkbox.checked = false;
    checkbox.dispatchEvent(new CustomEvent('change'));
    await flush();

    expect(byId(element, 'objects').data.map((row) => row.name)).toEqual([
      'Event__c',
      'Fund__c',
      'Gift__c'
    ]);
  });

  it('says so when two sides do not differ', async () => {
    const element = await render();
    await pick(element, 'a', 'Pat', PAT);
    await pick(element, 'b', 'Pat', { ...PAT, id: '005C', label: 'Pat Two' });

    expect(byId(element, 'similarity').textContent).toContain('100%');
    expect(byId(element, 'object-empty')).not.toBeNull();
    expect(byId(element, 'objects')).toBeNull();
  });

  it('compares the fields of one kind of record', async () => {
    getFieldAccess.mockImplementation(({ subjectId }) =>
      Promise.resolve(
        subjectId === '005A'
          ? [{ name: 'Amount__c', label: 'Amount', read: true, edit: true }]
          : [{ name: 'Amount__c', label: 'Amount', read: true }]
      )
    );
    const element = await render();
    await pick(element, 'a', 'Pat', PAT);
    await pick(element, 'b', 'Sam', SAM);

    expect(byId(element, 'field-object').options.map((option) => option.value)).toEqual([
      'Event__c',
      'Fund__c',
      'Gift__c'
    ]);
    byId(element, 'field-object').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Gift__c' } })
    );
    await flush();
    await flush();

    expect(getFieldAccess).toHaveBeenCalledWith({ subjectId: '005A', objectName: 'Gift__c' });
    expect(getFieldAccess).toHaveBeenCalledWith({ subjectId: '005B', objectName: 'Gift__c' });
    expect(byId(element, 'fields').data[0].difference).toBe('Only Pat Doe: Edit.');
  });

  it('clears both sides when the choice of what to compare changes', async () => {
    searchPermissionSets.mockResolvedValue([]);
    const element = await render();
    await pick(element, 'a', 'Pat', PAT);

    byId(element, 'kind').dispatchEvent(new CustomEvent('change', { detail: { value: 'set' } }));
    await flush();
    await type(element, 'a', 'St');

    expect(byId(element, 'chosen')).toBeNull();
    expect(searchPermissionSets).toHaveBeenCalledWith({ term: 'St' });
  });

  it('shows what went wrong', async () => {
    searchPeople.mockResolvedValue([
      { id: '005A', label: 'Pat Doe', detail: 'Standard User', isActive: true }
    ]);
    getAccess.mockRejectedValue({ body: { message: 'No access.' } });
    const element = await render();
    await type(element, 'a', 'Pat');
    element.shadowRoot.querySelector('lightning-button[data-value="005A"]').click();
    await flush();
    await flush();

    expect(byId(element, 'error').textContent).toContain('No access.');
  });

  it('downloads the table shown', async () => {
    const element = await render();
    await pick(element, 'a', 'Pat', PAT);
    await pick(element, 'b', 'Sam', SAM);

    element.shadowRoot.querySelector('lightning-button[data-table="objects"]').click();
    await flush();

    expect(csv).toBeDefined();
    const text = await new Promise((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.readAsText(csv);
    });
    expect(text).toContain('Only Pat Doe: Edit.');
    expect(text).not.toContain('Fund__c');
    expect(byId(element, 'notice').textContent).toBe('Downloaded 2 rows.');
  });
});
