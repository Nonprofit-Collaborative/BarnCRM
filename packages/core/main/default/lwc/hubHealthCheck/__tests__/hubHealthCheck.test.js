import { createElement } from 'lwc';
import HubHealthCheck from 'c/hubHealthCheck';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import { expectAccessible } from 'barn/a11y';

jest.mock(
  '@salesforce/apex/HubController.getHomeModel',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// A namespaced org answers with a qualified section key; the tab arrives qualified too.
jest.mock(
  '@salesforce/apex/SettingsController.getSettingsLink',
  () => ({
    default: jest.fn(() =>
      Promise.resolve({ tabApiName: 'ns__BarnCRM_Settings', sectionKey: 'ns__section' })
    )
  }),
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

const TAB = 'ns__Optimizer_Tab';

function build() {
  const element = createElement('c-hub-health-check', { is: HubHealthCheck });
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

describe('c-hub-health-check', () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows the last run: its badge, when it ran and its counts by severity', async () => {
    const element = build();
    getHomeModel.emit({
      healthCheckTab: TAB,
      healthCheckRanAt: '2026-11-20T09:00:00.000Z',
      healthCheckLastResult: '2,1,4'
    });
    await settle();

    expect(byId(element, 'health-check-badge').label).toBe('c.Core_OrgOptimizer_BadgeErrors');
    expect(byId(element, 'health-check-badge').status).toBe('error');
    expect(byId(element, 'health-check-ran-at').value).toBe('2026-11-20T09:00:00.000Z');
    expect(byId(element, 'health-check-result').textContent).toBe('c.Core_HealthCheck_LastResult');
    expect(byId(element, 'health-check-never')).toBeNull();
    await expectAccessible(element);
  });

  it('says Not Run Yet before the first full run', async () => {
    const element = build();
    getHomeModel.emit({ healthCheckTab: TAB, healthCheckRanAt: null, healthCheckLastResult: null });
    await settle();

    expect(byId(element, 'health-check-badge').label).toBe('c.Core_OrgOptimizer_BadgeNotRun');
    expect(byId(element, 'health-check-badge').status).toBe('neutral');
    expect(byId(element, 'health-check-never').textContent).toBe('c.Core_HubHome_HealthCheckNever');
    expect(byId(element, 'health-check-result')).toBeNull();
  });

  it('shows no tile while the Org Optimizer module is not installed', async () => {
    const element = build();
    getHomeModel.emit({ healthCheckTab: null, healthCheckRanAt: '2026-11-20T09:00:00.000Z' });
    await settle();

    expect(byId(element, 'health-check-card')).toBeNull();
  });

  it('says the tile could not load rather than claiming anything about the run', async () => {
    const element = build();
    getHomeModel.error();
    await settle();

    expect(byId(element, 'load-error')).not.toBeNull();
    expect(byId(element, 'health-check-badge')).toBeNull();
  });

  it('opens the Health Check section of the Org Optimizer tab the model named', async () => {
    const element = build();
    getHomeModel.emit({ healthCheckTab: TAB, healthCheckRanAt: null });
    await settle();

    byId(element, 'open-health-check').click();
    await settle();
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: TAB },
      state: { ns__section: 'healthCheck' }
    });
  });
});
