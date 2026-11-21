import { createElement } from 'lwc';
import SuperConnector from 'c/superConnector';
import getConnections from '@salesforce/apex/ConnectorConnectionsController.getConnections';
import { expectAccessible } from 'barn/a11y';

// A Connector Viewer: no Manage BarnCRM Connector, so no Connections Apex is called (m10).
jest.mock('@salesforce/customPermission/Manage_BarnCRM_Connector', () => ({ default: false }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.getConnections',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.checkConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.disconnect',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.deleteConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.createConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.replaceKey',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.getRecipes',
  () => ({ default: jest.fn(() => Promise.resolve({ canManage: false, recipes: [] })) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.getRecipeAccess',
  () => ({
    default: jest.fn(() => Promise.resolve({ ready: true, saved: true, options: [], chosen: [] }))
  }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.getRuns',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-super-connector for a Viewer', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('keeps Recipes and Run History without Retry, and never asks for connections', async () => {
    const element = createElement('c-super-connector', { is: SuperConnector });
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'recipes')).not.toBeNull();
    expect(find(element, 'runs').canManage).toBe(false);
    expect(find(element, 'viewer-notice').message).toBe('c.Connector_Page_ViewerNotice');
    expect(getConnections).not.toHaveBeenCalled();
    expect(find(element, 'error')).toBeNull();
    expect(find(element, 'loading')).toBeNull();
    await expectAccessible(element);
  });
});
