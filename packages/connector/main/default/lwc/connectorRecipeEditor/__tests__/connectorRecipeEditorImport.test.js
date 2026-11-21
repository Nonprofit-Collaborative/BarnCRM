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
  connections: [],
  maps: [],
  queries: [],
  templates: [{ value: 'a0T000000000001', label: 'Weekly Sign Ups' }]
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

function change(target, value) {
  target.value = value;
  target.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('c-connector-recipe-editor Load Rows (CN-09)', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('adds Load Rows with its limits showing, and checks them as you type', async () => {
    const element = createElement('c-connector-recipe-editor', { is: ConnectorRecipeEditor });
    element.page = PAGE;
    document.body.appendChild(element);
    await flush();

    find(element, 'add-step').dispatchEvent(
      new CustomEvent('select', { detail: { value: 'importRows' } })
    );
    await flush();
    const step = find(element, 'importRows1');
    expect(step).not.toBeNull();
    const limits = [...step.querySelectorAll('[data-limit]')];
    expect(limits.map((input) => input.value)).toEqual([1000, 0, 1000, 1000]);
    expect(find(element, 'problems').message).toContain('c.Connector_Recipe_ErrorTemplate');

    const template = step.querySelector('[data-field="template"]');
    expect(template.options).toEqual([{ label: 'Weekly Sign Ups', value: 'a0T000000000001' }]);
    change(template, 'a0T000000000001');
    await flush();
    expect(find(element, 'problems')).toBeNull();

    change(find(element, 'importRows1').querySelector('[data-limit="rejected"]'), '5000');
    await flush();
    expect(find(element, 'problems').message).toContain('c.Connector_Recipe_ErrorLimits');

    change(find(element, 'importRows1').querySelector('[data-limit="rejected"]'), '');
    await flush();
    expect(find(element, 'problems')).toBeNull();
    expect(find(element, 'importRows1').querySelector('[data-limit="rejected"]').value).toBe(0);
    await expectAccessible(element);
  });
});
