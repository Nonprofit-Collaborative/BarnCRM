import { createElement } from 'lwc';
import HubSeasonalAddresses from 'c/hubSeasonalAddresses';
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
  const element = createElement('c-hub-seasonal-addresses', { is: HubSeasonalAddresses });
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

describe('c-hub-seasonal-addresses', () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('says when the seasonal addresses were last swapped and what the run did', async () => {
    const element = build();
    getHomeModel.emit({
      seasonalAddressLastRun: '2027-01-15T06:30:00.000Z',
      seasonalAddressLastRunSummary:
        '3 moved to a seasonal address, 1 moved back, 0 could not be changed.',
      seasonalAddressScheduled: true,
      seasonalAddressStale: false
    });
    await settle();

    expect(byId(element, 'seasonal-last-run')).not.toBeNull();
    expect(byId(element, 'seasonal-last-run-summary').textContent.trim()).toBe(
      '3 moved to a seasonal address, 1 moved back, 0 could not be changed.'
    );
    expect(byId(element, 'seasonal-stale')).toBeNull();
    expect(byId(element, 'seasonal-not-scheduled')).toBeNull();
  });

  it('says the seasonal swap is not scheduled rather than pretending it ran', async () => {
    const element = build();
    getHomeModel.emit({
      seasonalAddressLastRun: null,
      seasonalAddressScheduled: false,
      seasonalAddressStale: false
    });
    await settle();

    expect(byId(element, 'seasonal-never')).not.toBeNull();
    expect(byId(element, 'seasonal-not-scheduled')).not.toBeNull();
    expect(byId(element, 'seasonal-stale')).toBeNull();
  });

  it('warns when a scheduled seasonal swap has missed its window, and not by color alone', async () => {
    const element = build();
    getHomeModel.emit({
      seasonalAddressLastRun: null,
      seasonalAddressScheduled: true,
      seasonalAddressStale: true
    });
    await settle();

    const warning = byId(element, 'seasonal-stale');
    expect(warning.getAttribute('aria-live')).toBe('polite');
    expect(warning.querySelector('lightning-icon').alternativeText).toBe(
      'c.Core_HubHome_WarningAltText'
    );
    // One message at a time: an overdue run is the fault worth reading, not the schedule.
    expect(byId(element, 'seasonal-not-scheduled')).toBeNull();
  });

  it('says nothing about the schedule before it knows, or when the tile cannot load', async () => {
    const element = build();
    await settle();
    expect(byId(element, 'seasonal-not-scheduled')).toBeNull();

    getHomeModel.error();
    await settle();
    expect(byId(element, 'seasonal-not-scheduled')).toBeNull();
    expect(byId(element, 'load-error')).not.toBeNull();
  });

  it('opens the Addresses section of BarnCRM Settings by page reference', async () => {
    const element = build();
    getHomeModel.emit({});
    await settle();

    byId(element, 'open-addresses').click();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'BarnCRM_Settings' },
      state: { c__section: 'Addresses' }
    });
  });
});
