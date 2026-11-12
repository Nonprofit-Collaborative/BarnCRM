import { createElement } from 'lwc';
import TerritoryManager from 'c/territoryManager';
import getPage from '@salesforce/apex/TerritoryController.getPage';
import startRun from '@salesforce/apex/TerritoryController.startRun';
import countRule from '@salesforce/apex/TerritoryController.countRule';
import undoRun from '@salesforce/apex/TerritoryController.undoRun';
import { createRecord } from 'lightning/uiRecordApi';
import BarnConfirmModal from 'c/barnConfirmModal';

jest.mock('@salesforce/apex/TerritoryController.getPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/TerritoryController.startRun', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/TerritoryController.countRule', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/TerritoryController.undoRun', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  'lightning/uiRecordApi',
  () => ({ createRecord: jest.fn(), updateRecord: jest.fn(), deleteRecord: jest.fn() }),
  { virtual: true }
);
jest.mock('c/barnConfirmModal', () => ({ __esModule: true, default: { open: jest.fn() } }));
jest.mock('c/filterBuilder', () => require('../../../../../test/jest-mocks/filterBuilder'));

const PAGE = {
  busy: false,
  maxRules: 50,
  territories: [
    {
      id: 'a0T000000000001',
      name: 'North',
      active: true,
      priority: 10,
      routing: 'Round Robin',
      rules: [
        {
          id: 'a0R000000000001',
          name: 'TR-000001',
          appliesTo: 'People',
          summary: 'City is Duluth',
          active: true
        }
      ],
      members: [
        { id: 'a0M000000000001', userName: 'Ana', capacity: 5, active: true, userActive: true }
      ]
    }
  ],
  runs: [
    {
      id: 'a0U000000000001',
      name: 'RUN-000001',
      mode: 'Assign',
      status: 'Done',
      checked: 10,
      changes: 2,
      failed: 0,
      canUndo: true,
      summaryJson:
        '{"territories":[{"id":"a0T000000000001","name":"North","changes":2,"noRoom":0}],"sample":[]}'
    }
  ]
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

async function render() {
  const element = createElement('c-territory-manager', { is: TerritoryManager });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-territory-manager', () => {
  beforeEach(() => {
    getPage.mockResolvedValue(PAGE);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists territories with their rules, members and runs', async () => {
    const element = await render();
    const territory = element.shadowRoot.querySelector('[data-id="territory"]');
    expect(territory.textContent).toContain('North');
    expect(territory.textContent).toContain('People: City is Duluth');
    expect(element.shadowRoot.querySelectorAll('[data-id="run"]')).toHaveLength(1);
  });

  it('previews without asking and assigns after confirming', async () => {
    startRun.mockResolvedValue('a0U000000000002');
    BarnConfirmModal.open.mockResolvedValue(true);
    const element = await render();

    element.shadowRoot.querySelector('[data-id="preview"]').click();
    await flush();
    expect(startRun).toHaveBeenLastCalledWith({ mode: 'Preview', onlyUnassigned: false });

    element.shadowRoot.querySelector('[data-id="assign"]').click();
    await flush();
    expect(BarnConfirmModal.open).toHaveBeenCalled();
    expect(startRun).toHaveBeenLastCalledWith({ mode: 'Assign', onlyUnassigned: false });
  });

  it('adds a rule through the filter builder and checks its count', async () => {
    countRule.mockResolvedValue(7);
    createRecord.mockResolvedValue({ id: 'a0R000000000002' });
    const element = await render();

    const addRule = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
      (button) => button.label === 'c.Territory_Page_AddRule'
    );
    addRule.click();
    await flush();
    const builder = element.shadowRoot.querySelector('c-filter-builder');
    expect(builder.objectApiName).toBe('Contact');
    builder.dispatchEvent(
      new CustomEvent('change', { detail: { value: '{"version":1}', valid: true, summary: 'Any' } })
    );
    element.shadowRoot.querySelector('[data-id="check-rule"]').click();
    await flush();
    expect(countRule).toHaveBeenCalledWith({ appliesTo: 'People', filterJson: '{"version":1}' });

    element.shadowRoot.querySelector('[data-id="save-rule"]').click();
    await flush();
    const saved = createRecord.mock.calls[0][0];
    expect(saved.fields.Filter_JSON__c).toBe('{"version":1}');
    expect(saved.fields.Territory__c).toBe('a0T000000000001');
  });

  it('undoes an Assign run after confirming', async () => {
    BarnConfirmModal.open.mockResolvedValue(true);
    undoRun.mockResolvedValue('707000000000001');
    const element = await render();

    const undo = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find(
      (button) => button.label === 'c.Territory_Page_Undo'
    );
    undo.click();
    await flush();
    expect(undoRun).toHaveBeenCalledWith({ runId: 'a0U000000000001' });
  });
});
