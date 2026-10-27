import { createElement } from 'lwc';
import RollupBuilder from 'c/rollupBuilder';
import getModel from '@salesforce/apex/RollupBuilderController.getModel';
import getDraft from '@salesforce/apex/RollupBuilderController.getDraft';
import { EnclosingTabId, setTabIcon, setTabLabel } from 'lightning/platformWorkspaceApi';

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
jest.mock('@salesforce/label/c.Core_Console_TabLabel', () => ({ default: '{0}: {1}' }), {
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
jest.mock('c/rollupDlrsImport', () =>
  require('../../../../../test/jest-mocks/rollupBuilder/rollupDlrsImport')
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

  it('says nothing about other rollup tools when the org has none', async () => {
    const element = build();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="other-rollup-tools"]')).toBeNull();
  });

  it('names DLRS as a separate tool above the list', async () => {
    const element = createElement('c-rollup-builder', { is: RollupBuilder });
    document.body.appendChild(element);
    getModel.emit({ ...MODEL, otherToolNotices: ['This org also runs DLRS.'] });
    await flush();

    const notice = element.shadowRoot.querySelector('[data-id="other-rollup-tools"]');
    expect(notice.textContent).toContain('c.Core_OtherRollupTools_Title');
    expect(notice.textContent).toContain('This org also runs DLRS.');
    expect(element.shadowRoot.querySelector('[data-id="import-from-dlrs"]')).toBeNull();
  });

  it('opens Import from DLRS in place of the list, and back with its notice', async () => {
    const element = createElement('c-rollup-builder', { is: RollupBuilder });
    document.body.appendChild(element);
    getModel.emit({
      ...MODEL,
      otherToolNotices: ['This org also runs DLRS.'],
      canImportFromDlrs: true
    });
    await flush();
    const importer = () => element.shadowRoot.querySelector('c-rollup-dlrs-import');
    expect(importer()).toBeNull();

    element.shadowRoot
      .querySelector('[data-id="import-from-dlrs"]')
      .dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(importer().model.canImportFromDlrs).toBe(true);
    expect(list(element).parentElement.className).toContain('slds-hide');
    expect(element.shadowRoot.querySelector('[data-id="import-from-dlrs"]')).toBeNull();

    importer().dispatchEvent(new CustomEvent('close', { detail: { notice: '1 turned on' } }));
    await flush();

    expect(importer()).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="notice"]').textContent).toBe('1 turned on');
    expect(list(element).refresh).toHaveBeenCalled();
  });

  it('leaves the tab alone outside a console', async () => {
    getDraft.mockResolvedValue({ recordId: 'a01', name: 'Household total giving' });
    const element = build();
    list(element).dispatchEvent(new CustomEvent('edit', { detail: { recordId: 'a01' } }));
    await flush();

    expect(setTabLabel).not.toHaveBeenCalled();
  });

  it('names the console tab for the rollup being edited, and back after save', async () => {
    getDraft.mockResolvedValue({ recordId: 'a01', name: 'Household total giving' });
    const element = build();
    EnclosingTabId.emit('tab0');
    await flush();
    expect(setTabLabel).toHaveBeenLastCalledWith('tab0', 'c.Core_RollupBuilder_Title');
    expect(setTabIcon).toHaveBeenCalledWith('tab0', 'utility:builder', {
      iconAlt: 'c.Core_RollupBuilder_Title'
    });

    list(element).dispatchEvent(new CustomEvent('edit', { detail: { recordId: 'a01' } }));
    await flush();
    expect(setTabLabel).toHaveBeenLastCalledWith(
      'tab0',
      'c.Core_RollupBuilder_Title: Household total giving'
    );

    wizard(element).dispatchEvent(new CustomEvent('saved', { detail: { notice: 'Saved.' } }));
    await flush();
    expect(setTabLabel).toHaveBeenLastCalledWith('tab0', 'c.Core_RollupBuilder_Title');
  });
});
