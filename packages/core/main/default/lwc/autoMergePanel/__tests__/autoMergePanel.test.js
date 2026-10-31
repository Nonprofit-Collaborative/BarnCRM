import { createElement } from 'lwc';
import AutoMergePanel from 'c/autoMergePanel';
import BarnConfirmModal from 'c/barnConfirmModal';
import getView from '@salesforce/apex/AutoMergeController.getView';
import preview from '@salesforce/apex/AutoMergeController.preview';
import startRun from '@salesforce/apex/AutoMergeController.startRun';
import undoRun from '@salesforce/apex/AutoMergeController.undoRun';

jest.mock('@salesforce/apex/AutoMergeController.getView', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/AutoMergeController.preview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/AutoMergeController.startRun', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/AutoMergeController.undoRun', () => ({ default: jest.fn() }), {
  virtual: true
});

const VIEW = {
  canRun: true,
  running: false,
  exactRule: 'Name and email',
  runs: [
    {
      runId: 'run-1',
      startedAt: '2026-10-30T10:00:00Z',
      canUndo: true,
      merged: 3,
      undone: 0,
      notUndone: 0,
      notes: []
    }
  ]
};

function flushPromises() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function build() {
  const element = createElement('c-auto-merge-panel', { is: AutoMergePanel });
  document.body.appendChild(element);
  await flushPromises();
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-auto-merge-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the recent runs with undo, and no pairs before a preview', async () => {
    getView.mockResolvedValue(VIEW);
    const element = await build();

    expect(find(element, 'runs')).not.toBeNull();
    expect(find(element, 'undo')).not.toBeNull();
    expect(find(element, 'pairs')).toBeNull();
    expect(find(element, 'preview').disabled).toBe(false);
  });

  it('lists the previewed pairs and their value changes', async () => {
    getView.mockResolvedValue({ ...VIEW, runs: [] });
    preview.mockResolvedValue({
      total: 1,
      exactRule: 'Name and email',
      pairs: [
        {
          ref: 'set:a:b',
          survivorName: 'Ann Lee',
          mergedName: 'Ann Lee',
          changes: [{ label: 'Phone', before: '', after: '555' }]
        }
      ]
    });
    const element = await build();
    expect(find(element, 'no-runs')).not.toBeNull();

    find(element, 'preview').click();
    await flushPromises();

    expect(element.shadowRoot.querySelectorAll('[data-id="pairs"] li').length).toBe(1);
    expect(find(element, 'merge')).not.toBeNull();
  });

  it('merges only after the confirm, then shows the run started', async () => {
    getView.mockResolvedValue({ ...VIEW, runs: [] });
    preview.mockResolvedValue({
      total: 1,
      pairs: [{ ref: 'set:a:b', survivorName: 'A', mergedName: 'B', changes: [] }]
    });
    startRun.mockResolvedValue({ ...VIEW, running: true });
    const element = await build();
    find(element, 'preview').click();
    await flushPromises();

    BarnConfirmModal.open.mockResolvedValue(false);
    find(element, 'merge').click();
    await flushPromises();
    expect(startRun).not.toHaveBeenCalled();

    BarnConfirmModal.open.mockResolvedValue(true);
    find(element, 'merge').click();
    await flushPromises();
    expect(startRun).toHaveBeenCalled();
    expect(find(element, 'status').textContent).toBe('c.Core_AutoMerge_Started');
    expect(find(element, 'running')).not.toBeNull();
  });

  it('undoes a run after the confirm', async () => {
    getView.mockResolvedValue(VIEW);
    undoRun.mockResolvedValue({ ...VIEW, running: true });
    BarnConfirmModal.open.mockResolvedValue(true);
    const element = await build();

    find(element, 'undo').click();
    await flushPromises();

    expect(BarnConfirmModal.open).toHaveBeenCalledWith(
      expect.objectContaining({ confirmVariant: 'destructive' })
    );
    expect(undoRun).toHaveBeenCalledWith({ runId: 'run-1' });
    expect(find(element, 'status').textContent).toBe('c.Core_AutoMerge_UndoStarted');
  });

  it('shows the server error in one sentence', async () => {
    getView.mockRejectedValue({ body: { message: 'You need permission.' } });
    const element = await build();

    expect(find(element, 'error').textContent).toBe('You need permission.');
  });

  it('turns the preview off without the run permission', async () => {
    getView.mockResolvedValue({ ...VIEW, canRun: false });
    const element = await build();

    expect(find(element, 'no-access')).not.toBeNull();
    expect(find(element, 'preview').disabled).toBe(true);
  });
});
