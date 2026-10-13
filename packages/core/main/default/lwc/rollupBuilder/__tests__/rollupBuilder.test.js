import { createElement } from 'lwc';
import RollupBuilder from 'c/rollupBuilder';
import getModel from '@salesforce/apex/RollupBuilderController.getModel';
import getDraft from '@salesforce/apex/RollupBuilderController.getDraft';

jest.mock(
  '@salesforce/apex/RollupBuilderController.getModel',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock('@salesforce/apex/RollupBuilderController.getDraft', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/label/c.Core_RollupBuilder_CopyOf', () => ({ default: 'Copy of {0}' }), {
  virtual: true
});
// The nested components are replaced by stubs so this test sees only the Builder's own work.
jest.mock('c/rollupDefinitions', () =>
  require('../../../../../test/jest-mocks/rollupBuilder/rollupDefinitions')
);
jest.mock('c/rollupWizard', () =>
  require('../../../../../test/jest-mocks/rollupBuilder/rollupWizard')
);
jest.mock('c/rollupNeedsAttention', () =>
  require('../../../../../test/jest-mocks/rollupBuilder/rollupNeedsAttention')
);

const MODEL = { canManage: true, multiCurrency: false, targets: [], aggregates: [], modes: [] };
const flush = () => Promise.resolve().then(() => Promise.resolve());

function build() {
  const element = createElement('c-rollup-builder', { is: RollupBuilder });
  document.body.appendChild(element);
  getModel.emit(MODEL);
  return element;
}

const list = (element) => element.shadowRoot.querySelector('c-rollup-definitions');
const wizard = (element) => element.shadowRoot.querySelector('c-rollup-wizard');

describe('c-rollup-builder', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the list in Builder mode and opens an empty wizard for New', async () => {
    const element = build();
    expect(list(element).builder).toBe(true);
    expect(wizard(element)).toBeNull();

    list(element).dispatchEvent(new CustomEvent('new'));
    await flush();

    expect(wizard(element).model).toEqual(MODEL);
    expect(wizard(element).draft).toBeNull();
  });

  it('opens Copy with no record and a new name', async () => {
    getDraft.mockResolvedValue({ recordId: 'a01', name: 'Household total giving' });
    const element = build();
    list(element).dispatchEvent(new CustomEvent('copy', { detail: { recordId: 'a01' } }));
    await flush();

    expect(getDraft).toHaveBeenCalledWith({ definitionId: 'a01' });
    expect(wizard(element).draft).toEqual({
      recordId: undefined,
      name: 'Copy of Household total giving'
    });
  });

  it('closes the wizard on save, shows the notice and refreshes the list', async () => {
    getDraft.mockResolvedValue({ recordId: 'a01', name: 'Household total giving' });
    const element = build();
    list(element).dispatchEvent(new CustomEvent('edit', { detail: { recordId: 'a01' } }));
    await flush();
    expect(wizard(element).draft.recordId).toBe('a01');

    wizard(element).dispatchEvent(new CustomEvent('saved', { detail: { notice: 'Saved.' } }));
    await flush();

    expect(wizard(element)).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="notice"]').textContent).toBe('Saved.');
    expect(list(element).refresh).toHaveBeenCalled();
  });
});
