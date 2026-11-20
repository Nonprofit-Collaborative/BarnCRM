import { createElement } from 'lwc';
import MigrationHome, { kitFromState } from 'c/migrationHome';
import getHome from '@salesforce/apex/MigrationController.getHome';
import getKit from '@salesforce/apex/MigrationController.getKit';
import getStatus from '@salesforce/apex/NpspHouseholdAdoptionController.getStatus';
import * as navigation from 'lightning/navigation';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/MigrationController.getHome', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/MigrationController.getKit', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/NpspHouseholdAdoptionController.getStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/NpspHouseholdAdoptionController.adopt',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/NpspHouseholdAdoptionController.undo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('c/jobPoller', () => ({ startPolling: jest.fn(() => jest.fn()) }));

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const { createTestWireAdapter } = require('@salesforce/wire-service-jest-util');
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return {
      NavigationMixin,
      CurrentPageReference: createTestWireAdapter(jest.fn()),
      __esModule: true
    };
  },
  { virtual: true }
);

const HOME = {
  kits: [
    { key: 'NPSP_People', label: 'NPSP People', description: 'Relationships and addresses' },
    { key: 'NPSP_Gifts', label: 'NPSP Gifts', description: 'Gifts' }
  ],
  npspHouseholds: true,
  npcHouseholds: false
};

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

function render() {
  const element = createElement('c-migration-home', { is: MigrationHome });
  document.body.appendChild(element);
  return element;
}

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

describe('c-migration-home', () => {
  beforeEach(() => {
    getHome.mockResolvedValue(HOME);
    getKit.mockResolvedValue({
      key: 'NPSP_People',
      label: 'NPSP People',
      steps: [],
      checklist: []
    });
    getStatus.mockResolvedValue({ available: true, candidateCount: 0, sample: [] });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('reads the kit from any namespace prefix of the page state', () => {
    expect(kitFromState({ c__kit: 'A' })).toBe('A');
    expect(kitFromState({ barn__kit: 'B' })).toBe('B');
    expect(kitFromState({ c__other: 'C' })).toBeUndefined();
    expect(kitFromState(undefined)).toBeUndefined();
  });

  it('lists the offered kits and the households that apply', async () => {
    const element = render();
    navigation.CurrentPageReference.emit({ state: {} });
    await flush();

    const rows = element.shadowRoot.querySelectorAll('[data-kit-row]');
    expect(rows).toHaveLength(2);
    expect(find(element, 'no-kits')).toBeNull();
    expect(find(element, 'npsp-households')).not.toBeNull();
    expect(find(element, 'npc-households')).toBeNull();
    expect(find(element, 'assistant')).toBeNull();
    await expectAccessible(element);
  });

  it('says so when no product with a kit is detected', async () => {
    getHome.mockResolvedValue({ kits: [], npspHouseholds: false, npcHouseholds: false });
    const element = render();
    navigation.CurrentPageReference.emit({ state: {} });
    await flush();

    expect(find(element, 'no-kits')).not.toBeNull();
    expect(find(element, 'households')).toBeNull();
    expect(find(element, 'uninstall')).not.toBeNull();
  });

  it('opens a kit from Start and goes back to the list', async () => {
    const element = render();
    navigation.CurrentPageReference.emit({ state: {} });
    await flush();

    element.shadowRoot.querySelectorAll('[data-id="start-kit"]')[1].click();
    await flush();
    const assistant = find(element, 'assistant');
    expect(assistant).not.toBeNull();
    expect(assistant.kitKey).toBe('NPSP_Gifts');

    assistant.dispatchEvent(new CustomEvent('back'));
    await flush();
    expect(find(element, 'assistant')).toBeNull();
    expect(getHome).toHaveBeenCalledTimes(2);
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('opens the kit the page state names and clears it on Back', async () => {
    const element = render();
    const pageReference = {
      type: 'standard__navItemPage',
      attributes: {},
      state: { c__kit: 'NPSP_People' }
    };
    navigation.CurrentPageReference.emit(pageReference);
    await flush();

    const assistant = find(element, 'assistant');
    expect(assistant.kitKey).toBe('NPSP_People');

    assistant.dispatchEvent(new CustomEvent('back'));
    await flush();
    expect(mockNavigate).toHaveBeenCalledWith(
      { type: 'standard__navItemPage', attributes: {}, state: {} },
      true
    );
  });

  it('shows the load error in words', async () => {
    getHome.mockRejectedValue({ body: { message: 'Not allowed' } });
    const element = render();
    navigation.CurrentPageReference.emit({ state: {} });
    await flush();

    expect(find(element, 'error').message).toBe('Not allowed');
  });
});
