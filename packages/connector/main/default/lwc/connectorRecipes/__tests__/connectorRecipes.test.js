import { createElement } from 'lwc';
import ConnectorRecipes from 'c/connectorRecipes';
import getRecipes from '@salesforce/apex/ConnectorRecipesController.getRecipes';
import getRecipeAccess from '@salesforce/apex/ConnectorRecipesController.getRecipeAccess';
import saveRecipeAccess from '@salesforce/apex/ConnectorRecipesController.saveRecipeAccess';
import { expectAccessible } from 'barn/a11y';

jest.mock(
  '@salesforce/apex/ConnectorRecipesController.getRecipes',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.getRecipeAccess',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.saveRecipeAccess',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
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

const WELCOME = {
  id: 'a0R000000000001',
  name: 'Welcome',
  status: 'Active',
  runAs: 'Automation',
  version: 2,
  unpublished: true,
  draftJson: '{"version":1,"trigger":{"kind":"manual","sample":{}},"steps":[]}'
};
const PAGE = { canManage: true, recipes: [WELCOME], connections: [], maps: [], queries: [] };

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render(page = PAGE, openRecipeId) {
  getRecipes.mockResolvedValue(page);
  const element = createElement('c-connector-recipes', { is: ConnectorRecipes });
  if (openRecipeId) {
    element.openRecipeId = openRecipeId;
  }
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-connector-recipes', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists recipes with status, Run As and unpublished changes, and is accessible', async () => {
    const element = await render();
    expect(find(element, WELCOME.id)).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('c-barn-status-badge')).toHaveLength(2);
    expect(find(element, 'new')).not.toBeNull();
    await expectAccessible(element);
  });

  it('shows the empty state and no admin buttons for a Viewer', async () => {
    const element = await render({ canManage: false, recipes: [] });
    expect(find(element, 'empty')).not.toBeNull();
    expect(find(element, 'new')).toBeNull();
    expect(find(element, 'access-toggle')).toBeNull();
  });

  it('opens the editor for New Recipe and for a recipe, and closes it', async () => {
    const element = await render();
    find(element, 'new').click();
    await flush();
    expect(find(element, 'editor')).not.toBeNull();
    expect(find(element, 'editor').recipe).toBeUndefined();
    find(element, 'editor').dispatchEvent(new CustomEvent('close'));
    await flush();
    expect(find(element, 'editor')).toBeNull();

    find(element, `open-${WELCOME.id}`).click();
    await flush();
    expect(find(element, 'editor').recipe.id).toBe(WELCOME.id);
  });

  it('opens the recipe a Where Used link names, and reloads when the editor changes it', async () => {
    const element = await render(PAGE, WELCOME.id);
    expect(find(element, 'editor').recipe.id).toBe(WELCOME.id);
    find(element, 'editor').dispatchEvent(
      new CustomEvent('changed', { detail: { deleted: true, message: 'Gone.' } })
    );
    await flush();
    expect(getRecipes).toHaveBeenCalledTimes(2);
    expect(find(element, 'editor')).toBeNull();
    expect(find(element, 'message').message).toBe('Gone.');
  });

  it('saves Recipe Access with the ticked permission sets', async () => {
    getRecipeAccess.mockResolvedValue({
      ready: true,
      saved: false,
      choices: [
        { id: '0PS000000000001', label: 'BarnCRM Connections', picked: true },
        { id: '0PS000000000002', label: 'Gift Entry', picked: false }
      ]
    });
    saveRecipeAccess.mockResolvedValue({ ready: true, saved: true, choices: [] });
    const element = await render();
    find(element, 'access-toggle').click();
    await flush();
    expect(find(element, 'access-not-saved')).not.toBeNull();
    expect(find(element, 'access-sets').value).toEqual(['0PS000000000001']);
    find(element, 'access-sets').dispatchEvent(
      new CustomEvent('change', { detail: { value: ['0PS000000000001', '0PS000000000002'] } })
    );
    await expectAccessible(element);
    find(element, 'access-save').click();
    await flush();
    expect(saveRecipeAccess).toHaveBeenCalledWith({
      permissionSetIds: ['0PS000000000001', '0PS000000000002']
    });
    expect(find(element, 'message').message).toBe('c.Connector_Access_Saved');
    expect(find(element, 'access')).toBeNull();
  });

  it('warns when the Automated Process user cannot be found and shows a load failure', async () => {
    getRecipeAccess.mockResolvedValue({ ready: false, saved: false, choices: [] });
    const element = await render();
    find(element, 'access-toggle').click();
    await flush();
    expect(find(element, 'access-not-ready')).not.toBeNull();

    getRecipes.mockRejectedValue({ body: { message: 'No access.' } });
    const failed = createElement('c-connector-recipes', { is: ConnectorRecipes });
    document.body.appendChild(failed);
    await flush();
    expect(find(failed, 'error').message).toBe('No access.');
  });
});
