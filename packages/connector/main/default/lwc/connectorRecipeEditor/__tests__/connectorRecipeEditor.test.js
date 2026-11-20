import { createElement } from 'lwc';
import ConnectorRecipeEditor from 'c/connectorRecipeEditor';
import saveDraft from '@salesforce/apex/ConnectorRecipesController.saveDraft';
import publish from '@salesforce/apex/ConnectorRecipesController.publish';
import setRunAs from '@salesforce/apex/ConnectorRecipesController.setRunAs';
import deleteRecipe from '@salesforce/apex/ConnectorRecipesController.deleteRecipe';
import runNow from '@salesforce/apex/ConnectorRecipesController.runNow';
import testRecipe from '@salesforce/apex/ConnectorRecipesController.testRecipe';
import getRun from '@salesforce/apex/ConnectorRecipesController.getRun';
import BarnConfirmModal from 'c/barnConfirmModal';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/ConnectorRecipesController.saveDraft', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ConnectorRecipesController.publish', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ConnectorRecipesController.setRunAs', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.deleteRecipe',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/ConnectorRecipesController.runNow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.testRecipe',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/ConnectorRecipesController.getRun', () => ({ default: jest.fn() }), {
  virtual: true
});

const PAGE = {
  canManage: true,
  recipes: [],
  connections: [{ value: 'BarnConn_rest_a', label: 'Mailing List' }],
  maps: [
    { value: 'a0M000000000001', label: 'Contact by Email', kind: 'record' },
    { value: 'a0M000000000002', label: 'Person Body', kind: 'json' }
  ],
  queries: [
    {
      value: 'a0Q000000000001',
      label: 'Contacts by Email',
      kind: 'Contact',
      document: JSON.stringify({
        version: 1,
        object: 'Contact',
        fields: ['Email'],
        filter: {
          version: 1,
          conditions: [{ id: 1, field: 'Email', operator: 'equals', value: '' }]
        }
      })
    }
  ]
};
const DOCUMENT = {
  version: 1,
  trigger: { kind: 'manual', sample: { email: 'ada@example.org' } },
  steps: [{ id: 'stop1', kind: 'stop', outcome: 'Succeeded', message: '' }]
};
const SAVED = {
  id: 'a0R000000000001',
  name: 'Welcome',
  description: '',
  status: 'Draft',
  runAs: 'Automation',
  version: 0,
  unpublished: true,
  draftJson: JSON.stringify(DOCUMENT)
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render(recipe, page = PAGE) {
  const element = createElement('c-connector-recipe-editor', { is: ConnectorRecipeEditor });
  element.page = page;
  element.recipe = recipe;
  document.body.appendChild(element);
  await flush();
  return element;
}

function field(element, stepId, name) {
  return element.shadowRoot.querySelector(`[data-id="${stepId}"] [data-field="${name}"]`);
}

function change(target, value) {
  target.value = value;
  target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-connector-recipe-editor', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('starts a new recipe with no steps and is accessible', async () => {
    const element = await render(undefined);
    expect(find(element, 'no-steps')).not.toBeNull();
    expect(find(element, 'save-first')).not.toBeNull();
    expect(find(element, 'problems')).not.toBeNull();
    await expectAccessible(element);
  });

  it('adds a Call an App step, checks it as you type and fills path slots', async () => {
    const element = await render(undefined);
    find(element, 'add-step').dispatchEvent(
      new CustomEvent('select', { detail: { value: 'callApp' } })
    );
    await flush();
    expect(find(element, 'callApp1')).not.toBeNull();
    expect(find(element, 'problems').message).toContain('c.Connector_Recipe_ErrorConnection');

    change(field(element, 'callApp1', 'connection'), 'BarnConn_rest_a');
    await flush();
    change(field(element, 'callApp1', 'path'), '/people/{id}');
    await flush();
    expect(find(element, 'problems').message).toContain('c.Connector_Recipe_ErrorSlot');

    change(field(element, 'callApp1', 'shown'), 'trigger.email');
    await flush();
    expect(find(element, 'problems')).toBeNull();
    await expectAccessible(element);
  });

  it('refuses a merge field typed into a header value (F1)', async () => {
    const element = await render(undefined);
    find(element, 'add-step').dispatchEvent(
      new CustomEvent('select', { detail: { value: 'callApp' } })
    );
    await flush();
    change(field(element, 'callApp1', 'connection'), 'BarnConn_rest_a');
    await flush();
    const addHeader = element.shadowRoot.querySelector(
      '[data-id="callApp1"] lightning-button[data-list="headers"]'
    );
    addHeader.click();
    await flush();
    change(
      element.shadowRoot.querySelector(
        '[data-id="callApp1"] [data-list="headers"][data-field="name"]'
      ),
      'X-Id'
    );
    await flush();
    change(
      element.shadowRoot.querySelector(
        '[data-id="callApp1"] [data-list="headers"][data-field="shown"]'
      ),
      '{!$Credential.Password}'
    );
    await flush();
    expect(find(element, 'problems').message).toBe('c.Connector_Recipe_ErrorMergeField');
  });

  it('copies a saved query into a Find step', async () => {
    const element = await render(undefined);
    find(element, 'add-step').dispatchEvent(
      new CustomEvent('select', { detail: { value: 'find' } })
    );
    await flush();
    const query = element.shadowRoot.querySelector('[data-id="find1"] lightning-combobox');
    change(query, 'a0Q000000000001');
    await flush();
    expect(find(element, 'problems')).toBeNull();
  });

  it('saves the draft and publishes it, telling the list', async () => {
    saveDraft.mockResolvedValue(SAVED);
    publish.mockResolvedValue({ ...SAVED, status: 'Active', version: 1, unpublished: false });
    const element = await render(SAVED);
    const changed = jest.fn();
    element.addEventListener('changed', changed);

    find(element, 'save').click();
    await flush();
    expect(saveDraft).toHaveBeenCalledWith(
      expect.objectContaining({
        recipeId: SAVED.id,
        name: 'Welcome',
        draftJson: JSON.stringify(DOCUMENT)
      })
    );
    expect(changed.mock.calls[0][0].detail).toEqual({
      recipeId: SAVED.id,
      message: 'c.Connector_Editor_Saved'
    });

    find(element, 'publish').click();
    await flush();
    expect(publish).toHaveBeenCalledWith({ recipeId: SAVED.id });
    expect(changed.mock.calls[1][0].detail.message).toBe('c.Connector_Editor_Published');
  });

  it('asks before System and records the choice only when confirmed', async () => {
    BarnConfirmModal.open = jest.fn().mockResolvedValueOnce(false).mockResolvedValue(true);
    setRunAs.mockResolvedValue({
      ...SAVED,
      runAs: 'System',
      runAsChosenBy: 'Ada',
      runAsChosenAt: '2026-11-20T10:00:00Z'
    });
    const element = await render(SAVED);

    find(element, 'run-as').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'System' } })
    );
    await flush();
    expect(setRunAs).not.toHaveBeenCalled();

    find(element, 'run-as').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'System' } })
    );
    await flush();
    expect(setRunAs).toHaveBeenCalledWith({ recipeId: SAVED.id, runAs: 'System', confirmed: true });
    expect(find(element, 'run-as-chosen')).not.toBeNull();
  });

  it('tests on the sample data and shows what each step would have done', async () => {
    saveDraft.mockResolvedValue(SAVED);
    testRecipe.mockResolvedValue({ id: 'a0S000000000001', name: 'R-1', status: 'Queued' });
    getRun.mockResolvedValue({
      id: 'a0S000000000001',
      name: 'R-1',
      status: 'Succeeded',
      stepLogJson: JSON.stringify([{ step: 'stop1', kind: 'stop', outcome: 'Succeeded', ms: 1 }]),
      resultsJson: '{}'
    });
    const element = await render(SAVED);
    find(element, 'test').click();
    await flush();
    expect(testRecipe).toHaveBeenCalledWith(
      expect.objectContaining({ recipeId: SAVED.id, recordId: '', sendForReal: false })
    );
    expect(find(element, 'message').message).toBe('c.Connector_Editor_TestQueued');

    find(element, 'check-result').click();
    await flush();
    expect(getRun).toHaveBeenCalledWith({ runId: 'a0S000000000001' });
    expect(find(element, 'test-result')).not.toBeNull();
    await expectAccessible(element);
  });

  it('runs an Active recipe now and shows a server refusal plainly', async () => {
    runNow
      .mockResolvedValueOnce({ name: 'R-2' })
      .mockRejectedValueOnce({ body: { message: 'Not allowed.' } });
    const element = await render({ ...SAVED, status: 'Active', version: 1, unpublished: false });
    find(element, 'run-now').click();
    await flush();
    expect(find(element, 'message').message).toBe('c.Connector_Editor_RunQueued');
    find(element, 'run-now').click();
    await flush();
    expect(find(element, 'error').message).toBe('Not allowed.');
  });

  it('deletes only after confirming', async () => {
    BarnConfirmModal.open = jest.fn().mockResolvedValueOnce(false).mockResolvedValue(true);
    deleteRecipe.mockResolvedValue(undefined);
    const element = await render(SAVED);
    const changed = jest.fn();
    element.addEventListener('changed', changed);
    find(element, 'delete').click();
    await flush();
    expect(deleteRecipe).not.toHaveBeenCalled();
    find(element, 'delete').click();
    await flush();
    expect(deleteRecipe).toHaveBeenCalledWith({ recipeId: SAVED.id });
    expect(changed.mock.calls[0][0].detail.deleted).toBe(true);
  });

  it('is read only for a Viewer', async () => {
    const element = await render(SAVED, { ...PAGE, canManage: false });
    expect(find(element, 'name').readOnly).toBe(true);
    expect(find(element, 'save')).toBeNull();
    expect(find(element, 'publish')).toBeNull();
  });
});
