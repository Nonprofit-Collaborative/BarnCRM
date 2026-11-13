import { createElement } from 'lwc';
import HubQuickLinks from 'c/hubQuickLinks';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';

jest.mock(
  '@salesforce/apex/HubController.getHomeModel',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

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
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);

function build(model) {
  const element = createElement('c-hub-quick-links', { is: HubQuickLinks });
  document.body.appendChild(element);
  if (model) {
    getHomeModel.emit(model);
  }
  return Promise.resolve().then(() => element);
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function tiles(element) {
  return Array.from(element.shadowRoot.querySelectorAll('[data-id="quick-link"]'));
}

function select(element, name) {
  const tile = tiles(element).find((candidate) => candidate.name === name);
  tile.dispatchEvent(new CustomEvent('select', { detail: { name } }));
}

describe('c-hub-quick-links', () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows staff People, Households, Organizations and Find, without Settings', async () => {
    const element = await build({ canEdit: false, canImport: false, quickLinks: [] });

    expect(tiles(element).map((tile) => tile.name)).toEqual([
      'People',
      'Households',
      'Organizations',
      'Find'
    ]);
    expect(tiles(element).every((tile) => tile.iconName && tile.description && !tile.href)).toBe(
      true
    );
  });

  it('adds Import a File, the catalog links of modules, and Settings last for administrators', async () => {
    const element = await build({
      canEdit: true,
      canImport: true,
      quickLinks: [
        { tab: 'Quick_Gift_Entry', label: 'Enter a Gift', line: 'Record a gift.' },
        { objectApiName: 'Enrollment__c', label: 'Enroll', line: 'Start someone.' }
      ]
    });

    expect(tiles(element).map((tile) => tile.name)).toEqual([
      'People',
      'Households',
      'Organizations',
      'Find',
      'Import',
      'Quick_Gift_Entry',
      'new:Enrollment__c',
      'BarnCRM_Settings'
    ]);
    expect(tiles(element)[5].label).toBe('Enter a Gift');
    select(element, 'Quick_Gift_Entry');
    await settle();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Quick_Gift_Entry' }
    });
    select(element, 'new:Enrollment__c');
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Enrollment__c', actionName: 'new' }
    });
  });

  it('opens each tab by page reference, never by URL', async () => {
    const element = await build({ canEdit: false });

    select(element, 'Organizations');
    await settle();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Organizations' }
    });
  });

  it('opens People as the Contacts list', async () => {
    const element = await build({ canEdit: false });

    select(element, 'People');
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Contact', actionName: 'list' }
    });
  });

  it('opens Households as its list view, which works before the person has the tab', async () => {
    const element = await build();

    select(element, 'Households');
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Account', actionName: 'list' },
      state: { filterName: 'Households' }
    });
  });
});
