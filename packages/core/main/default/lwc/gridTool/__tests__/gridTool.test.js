import { createElement } from 'lwc';
import GridTool from 'c/gridTool';
import getPage from '@salesforce/apex/FindController.getPage';
import runQuery from '@salesforce/apex/FindController.runQuery';
import saveEdits from '@salesforce/apex/FindController.saveEdits';
import saveQuery from '@salesforce/apex/FindController.saveQuery';
import listChildRelationships from '@salesforce/apex/FindController.listChildRelationships';
import getTargets from '@salesforce/apex/BulkUpdateController.getTargets';
import getObjectInfo from '@salesforce/apex/QueryFieldCatalog.getObjectInfo';

const mockNavigate = jest.fn();
jest.mock('lightning/navigation', () => {
  const Navigate = Symbol('Navigate');
  const NavigationMixin = (Base) =>
    class extends Base {
      [Navigate](...args) {
        mockNavigate(...args);
      }
    };
  NavigationMixin.Navigate = Navigate;
  return { NavigationMixin, __esModule: true };
});
jest.mock('@salesforce/apex/FindController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.runQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.saveEdits', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.saveQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.deleteQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/FindController.listChildRelationships',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/BulkUpdateController.getTargets', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/QueryFieldCatalog.getObjectInfo', () => ({ default: jest.fn() }), {
  virtual: true
});

const QUERY = {
  recordId: 'a01000000000001',
  name: 'Donors',
  mine: true,
  shared: false,
  queryJson: JSON.stringify({ version: 1, object: 'Contact', fields: ['Name', 'Email'] })
};
const ROWS = [{ Id: '003000000000001', Name: 'Ana Alvarez', Email: 'ana@example.org' }];

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render() {
  const element = createElement('c-grid-tool', { is: GridTool });
  element.stateKey = 'c__view';
  document.body.appendChild(element);
  await flush();
  return element;
}

async function chooseQuery(element) {
  const source = element.shadowRoot.querySelector('[data-id="source"]');
  source.dispatchEvent(new CustomEvent('change', { detail: { value: QUERY.recordId } }));
  await flush();
}

describe('c-grid-tool', () => {
  beforeEach(() => {
    getPage.mockResolvedValue({ savedQueries: [QUERY], canBulkUpdate: true });
    getObjectInfo.mockResolvedValue({
      fields: [
        { apiName: 'Name', label: 'Name', dataType: 'string' },
        { apiName: 'Email', label: 'Email', dataType: 'email' }
      ]
    });
    getTargets.mockResolvedValue([{ apiName: 'Email' }]);
    listChildRelationships.mockResolvedValue([]);
    runQuery.mockResolvedValue({ rows: ROWS });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('runs a saved query into an editable table', async () => {
    const element = await render();
    await chooseQuery(element);
    element.shadowRoot.querySelector('[data-id="run"]').click();
    await flush();

    const table = element.shadowRoot.querySelector('[data-id="main"]');
    expect(runQuery).toHaveBeenCalled();
    expect(table.data).toHaveLength(1);
    const email = table.columns.find((column) => column.fieldName === 'Email');
    const name = table.columns.find((column) => column.fieldName === 'Name');
    expect(email.editable).toBe(true);
    expect(Boolean(name.editable)).toBe(false);
  });

  it('saves edits through Find and runs the query again', async () => {
    saveEdits.mockResolvedValue({ saved: 1, errors: [] });
    const element = await render();
    await chooseQuery(element);
    element.shadowRoot.querySelector('[data-id="run"]').click();
    await flush();

    const table = element.shadowRoot.querySelector('[data-id="main"]');
    table.dispatchEvent(
      new CustomEvent('save', {
        detail: { draftValues: [{ Id: ROWS[0].Id, Email: 'new@example.org' }] }
      })
    );
    await flush();

    expect(saveEdits).toHaveBeenCalledWith({
      objectApiName: 'Contact',
      editsJson: JSON.stringify([{ Id: ROWS[0].Id, Email: 'new@example.org' }])
    });
    expect(runQuery).toHaveBeenCalledTimes(2);
  });

  it('saves a named grid with the grid key and opens a query in Find', async () => {
    saveQuery.mockResolvedValue({
      savedQueries: [QUERY],
      canBulkUpdate: true,
      savedId: 'a01000000000002'
    });
    const element = await render();
    await chooseQuery(element);
    const name = element.shadowRoot.querySelector('[data-id="name"]');
    name.dispatchEvent(new CustomEvent('change', { detail: { value: 'Donor grid' } }));
    await flush();
    element.shadowRoot.querySelector('[data-id="save-grid"]').click();
    await flush();

    const saved = saveQuery.mock.calls[0][0];
    expect(saved.name).toBe('Donor grid');
    expect(saved.recordId).toBeNull();
    expect(JSON.parse(saved.queryJson).grid).toEqual({ version: 1 });

    element.shadowRoot.querySelector('[data-id="open-in-find"]').click();
    await flush();
    expect(mockNavigate.mock.calls[0][0].state).toEqual({ c__savedQueryId: 'a01000000000002' });
  });
});
