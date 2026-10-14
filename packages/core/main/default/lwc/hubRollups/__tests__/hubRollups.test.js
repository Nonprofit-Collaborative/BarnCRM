import { createElement } from 'lwc';
import HubRollups from 'c/hubRollups';
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

function build() {
  const element = createElement('c-hub-rollups', { is: HubRollups });
  document.body.appendChild(element);
  return element;
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-hub-rollups', () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('says when the rollups last completed', async () => {
    const element = build();
    getHomeModel.emit({
      rollupsInstalled: true,
      rollupsLastCalculated: '2026-09-08T02:00:00.000Z',
      rollupsStale: false
    });
    await settle();

    expect(byId(element, 'rollups-last-calculated')).not.toBeNull();
    expect(byId(element, 'rollups-stale')).toBeNull();
  });

  it('warns when the rollups are more than 36 hours old, and not by color alone', async () => {
    const element = build();
    getHomeModel.emit({ rollupsInstalled: true, rollupsLastCalculated: null, rollupsStale: true });
    await settle();

    expect(byId(element, 'rollups-never')).not.toBeNull();
    const warning = byId(element, 'rollups-stale');
    expect(warning.getAttribute('aria-live')).toBe('polite');
    // A screen reader hears "Warning", not the tile's own heading.
    expect(warning.querySelector('lightning-icon').alternativeText).toBe(
      'c.Core_HubHome_WarningAltText'
    );
  });

  it('claims nothing about the rollups while the model is still loading', async () => {
    const element = build();
    await settle();

    expect(byId(element, 'rollups-never')).toBeNull();
    expect(byId(element, 'rollups-last-calculated')).toBeNull();
  });

  it('says the tile could not load rather than claiming rollups never ran', async () => {
    const element = build();
    getHomeModel.error();
    await settle();

    expect(byId(element, 'rollups-never')).toBeNull();
    expect(byId(element, 'load-error')).not.toBeNull();
  });

  it('shows no tile when the Rollup Builder module is not installed', async () => {
    const element = build();
    getHomeModel.emit({ rollupsInstalled: false, rollupsStale: false });
    await settle();

    expect(byId(element, 'rollups-card')).toBeNull();
    expect(byId(element, 'rollups-never')).toBeNull();
  });

  it('opens the Rollups section of BarnCRM Settings by page reference', async () => {
    const element = build();
    getHomeModel.emit({ rollupsInstalled: true });
    await settle();

    byId(element, 'open-rollups').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'BarnCRM_Settings' },
      state: { c__section: 'Rollups' }
    });
  });
});
