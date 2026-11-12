import { createElement } from 'lwc';
import MigrationAssistant from 'c/migrationAssistant';
import BarnConfirmModal from 'c/barnConfirmModal';
import getKit from '@salesforce/apex/MigrationController.getKit';
import startStep from '@salesforce/apex/MigrationController.startStep';
import setToolStep from '@salesforce/apex/MigrationController.setToolStep';
import setChecklistItem from '@salesforce/apex/MigrationController.setChecklistItem';
import getBatch from '@salesforce/apex/ImportController.getBatch';
import getRowPage from '@salesforce/apex/ImportController.getRowPage';
import getChangedValues from '@salesforce/apex/ImportController.getChangedValues';
import startCommit from '@salesforce/apex/ImportController.startCommit';
import previewUndo from '@salesforce/apex/ImportController.previewUndo';
import startUndo from '@salesforce/apex/ImportController.startUndo';

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, __esModule: true };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/MigrationController.getKit', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MigrationController.startStep', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MigrationController.setToolStep', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MigrationController.setChecklistItem', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getBatch', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getRowPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getChangedValues', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.startCommit', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.previewUndo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.startUndo', () => ({ default: jest.fn() }), {
  virtual: true
});

function importStep(extra = {}) {
  return {
    key: 'people',
    label: 'People',
    kind: 'import',
    status: 'NotStarted',
    canStart: true,
    hasVerification: false,
    ...extra
  };
}

function toolStep(extra = {}) {
  return {
    key: 'copy',
    label: 'Copy Rollups',
    kind: 'tool',
    status: 'NotStarted',
    tab: 'Rollup_Builder',
    toolLabel: 'Open Rollup Builder',
    canMarkDone: true,
    ...extra
  };
}

function kit(steps, extra = {}) {
  return {
    key: 'Test_Kit',
    label: 'Test Kit',
    description: 'Moves test records.',
    steps,
    checklist: [{ key: 'off', text: 'Switch it off.', ticked: false }],
    allDone: false,
    complete: false,
    ...extra
  };
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function build() {
  const element = createElement('c-migration-assistant', { is: MigrationAssistant });
  element.kitKey = 'Test_Kit';
  document.body.appendChild(element);
  await settle();
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-migration-assistant', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('draws the kit, its steps in order and only the actions each allows', async () => {
    getKit.mockResolvedValue(
      kit([importStep(), toolStep({ status: 'Waiting', canMarkDone: false })])
    );
    const element = await build();

    expect(getKit).toHaveBeenCalledWith({ kitKey: 'Test_Kit' });
    expect(find(element, 'title').textContent).toBe('Test Kit');
    const labels = [...element.shadowRoot.querySelectorAll('[data-id="step-label"]')].map(
      (node) => node.textContent
    );
    expect(labels).toEqual(['1. People', '2. Copy Rollups']);
    const badges = element.shadowRoot.querySelectorAll('[data-id="step-status"]');
    expect(badges[0].label).toBe('c.Core_Migration_StatusNotStarted');
    expect(badges[1].label).toBe('c.Core_Migration_StatusWaiting');
    expect(element.shadowRoot.querySelectorAll('[data-id="start"]')).toHaveLength(1);
    expect(find(element, 'mark-done')).toBeNull();
    expect(find(element, 'open-tool')).toBeNull();
    expect(find(element, 'load')).toBeNull();
    // The checklist waits for every step.
    expect(element.shadowRoot.querySelector('lightning-input[data-item="off"]').disabled).toBe(
      true
    );
  });

  it('starts a loading step and shows the refusal in words', async () => {
    getKit.mockResolvedValue(kit([importStep()]));
    startStep.mockResolvedValue(kit([importStep({ status: 'Running', canStart: false })]));
    const element = await build();

    find(element, 'start').click();
    await settle();
    expect(startStep).toHaveBeenCalledWith({ kitKey: 'Test_Kit', stepKey: 'people' });
    expect(find(element, 'step-status').label).toBe('c.Core_Migration_StatusRunning');

    getKit.mockRejectedValue({ body: { message: 'Finish the steps above this one first.' } });
    find(element, 'refresh').click();
    await settle();
    expect(find(element, 'error').message).toBe('Finish the steps above this one first.');
  });

  it('shows a previewed step with the Super Importer results and loads it on confirm', async () => {
    const review = importStep({
      status: 'Review',
      canStart: false,
      canLoad: true,
      batchId: 'a0B000000000001',
      staged: 2,
      sourceCount: 2,
      loaded: 0,
      rejected: 1,
      hasVerification: true,
      verified: false
    });
    getKit.mockResolvedValue(kit([review]));
    getBatch.mockResolvedValue({ id: 'a0B000000000001', isDryRun: true });
    getRowPage.mockResolvedValue({ rows: [{ id: 'row1' }] });
    getChangedValues.mockResolvedValue([]);
    const element = await build();

    expect(find(element, 'verdict').label).toBe('c.Core_Migration_CheckStep');
    expect(find(element, 'source').value).toBe(2);
    expect(find(element, 'rejected').value).toBe(1);

    find(element, 'results-toggle').click();
    await settle();
    expect(getRowPage).toHaveBeenCalledWith(
      expect.objectContaining({ batchId: 'a0B000000000001', status: 'Rejected' })
    );
    const results = find(element, 'results');
    expect(results.batch).toEqual({ id: 'a0B000000000001', isDryRun: true });
    expect(results.rejectedRows).toEqual([{ id: 'row1' }]);

    BarnConfirmModal.open = jest.fn().mockResolvedValue(false);
    find(element, 'load').click();
    await settle();
    expect(startCommit).not.toHaveBeenCalled();

    BarnConfirmModal.open = jest.fn().mockResolvedValue(true);
    startCommit.mockResolvedValue({});
    find(element, 'load').click();
    await settle();
    expect(startCommit).toHaveBeenCalledWith({ batchId: 'a0B000000000001' });
    expect(find(element, 'notice').message).toBe('c.Core_Migration_Started');
  });

  it('undoes the latest loaded step with the Super Importer undo and its count', async () => {
    const done = importStep({
      status: 'Done',
      canStart: false,
      canUndo: true,
      batchId: 'a0B000000000002'
    });
    getKit.mockResolvedValue(kit([done]));
    previewUndo.mockResolvedValue({ allowed: true, total: 5, updates: 1 });
    BarnConfirmModal.open = jest.fn().mockResolvedValue(true);
    startUndo.mockResolvedValue({});
    const element = await build();

    find(element, 'undo').click();
    await settle();
    expect(BarnConfirmModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ confirmVariant: 'destructive' })
    );
    expect(startUndo).toHaveBeenCalledWith({ batchId: 'a0B000000000002', confirmedTotal: 5 });

    previewUndo.mockResolvedValue({ allowed: false, reason: 'Too old to undo.' });
    BarnConfirmModal.open = jest.fn();
    find(element, 'undo').click();
    await settle();
    expect(BarnConfirmModal.open).not.toHaveBeenCalled();
    expect(find(element, 'error').message).toBe('Too old to undo.');
  });

  it('opens the tool, marks the step done and ticks the checklist to completion', async () => {
    getKit.mockResolvedValue(kit([toolStep()]));
    const element = await build();

    find(element, 'open-tool').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Rollup_Builder' }
    });

    setToolStep.mockResolvedValue(
      kit([toolStep({ status: 'Done', canMarkDone: false, canUnmark: true })], { allDone: true })
    );
    find(element, 'mark-done').click();
    await settle();
    expect(setToolStep).toHaveBeenCalledWith({ kitKey: 'Test_Kit', stepKey: 'copy', done: true });
    expect(find(element, 'mark-not-done')).not.toBeNull();

    setChecklistItem.mockResolvedValue(
      kit([toolStep({ status: 'Done', canMarkDone: false })], {
        allDone: true,
        complete: true,
        checklist: [{ key: 'off', text: 'Switch it off.', ticked: true }]
      })
    );
    const box = element.shadowRoot.querySelector('lightning-input[data-item="off"]');
    expect(box.disabled).toBe(false);
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    await settle();
    expect(setChecklistItem).toHaveBeenCalledWith({
      kitKey: 'Test_Kit',
      itemKey: 'off',
      ticked: true
    });
    expect(find(element, 'complete')).not.toBeNull();
  });

  it('shows why a kit cannot run and fires back', async () => {
    getKit.mockResolvedValue(kit([], { problem: 'The kit cannot be read.' }));
    const element = await build();
    expect(find(element, 'problem').message).toBe('The kit cannot be read.');

    const back = jest.fn();
    element.addEventListener('back', back);
    find(element, 'back').click();
    expect(back).toHaveBeenCalled();
  });
});
