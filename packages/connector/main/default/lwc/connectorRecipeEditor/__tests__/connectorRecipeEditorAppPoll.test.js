import { createElement } from 'lwc';
import ConnectorRecipeEditor from 'c/connectorRecipeEditor';
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
  { virtual: true }
);
jest.mock('@salesforce/apex/ConnectorRecipesController.runNow', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.testRecipe',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/ConnectorRecipesController.getRun', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.saveRecipeSettings',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.pauseRecipe',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.resumeRecipe',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.retryAllFailed',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const PAGE = {
  canManage: true,
  recipes: [],
  connections: [{ value: 'BarnConn_rest_abc123', label: 'Mailchimp' }],
  maps: [],
  queries: [],
  templates: []
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

function setPoll(element, detail) {
  find(element, 'app-poll').dispatchEvent(new CustomEvent('triggerchange', { detail }));
}

describe('c-connector-recipe-editor An App Has New Items (CN-13)', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the App Poll fields and checks the trigger as it is filled in', async () => {
    const element = createElement('c-connector-recipe-editor', { is: ConnectorRecipeEditor });
    element.page = PAGE;
    document.body.appendChild(element);
    await flush();

    const kinds = find(element, 'trigger-kind').options.map((option) => option.value);
    expect(kinds).toContain('appPoll');
    find(element, 'trigger-kind').dispatchEvent(
      new CustomEvent('change', { detail: { value: 'appPoll' } })
    );
    await flush();
    const setup = find(element, 'app-poll');
    expect(setup).not.toBeNull();
    expect(setup.connections).toEqual([{ label: 'Mailchimp', value: 'BarnConn_rest_abc123' }]);
    expect(find(element, 'problems').message).toContain('c.Connector_Recipe_ErrorAppPoll');

    setPoll(element, { connection: 'BarnConn_rest_abc123', path: '/members', stamp: 'changed' });
    await flush();
    expect(find(element, 'problems').message).not.toContain('c.Connector_Recipe_ErrorAppPoll');
    expect(find(element, 'app-poll').trigger).toMatchObject({
      kind: 'appPoll',
      path: '/members',
      id: 'id',
      stamp: 'changed'
    });
    await expectAccessible(element);
  });
});
