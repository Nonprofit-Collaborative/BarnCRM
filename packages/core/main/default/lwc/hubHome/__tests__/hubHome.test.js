// The test wire adapter below is emitted to on purpose, which is how a wired
// component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import HubHome from 'c/hubHome';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import countInstallProblems from '@salesforce/apex/CorePostInstall.countInstallProblems';

jest.mock('@salesforce/apex/HubController.getHomeModel', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/CorePostInstall.countInstallProblems', () => ({ default: jest.fn() }), {
  virtual: true
});

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

const mockEncodeDefaultFieldValues = jest.fn(
  (fields) =>
    `encoded:${Object.keys(fields)
      .map((key) => `${key}=${fields[key]}`)
      .join(',')}`
);
jest.mock(
  'lightning/pageReferenceUtils',
  () => ({
    encodeDefaultFieldValues: (...args) => mockEncodeDefaultFieldValues(...args)
  }),
  { virtual: true }
);

const HOUSEHOLD_RECORD_TYPE_ID = '012000000000001AAA';

const ACCOUNT_INFO = {
  createable: true,
  recordTypeInfos: {
    [HOUSEHOLD_RECORD_TYPE_ID]: {
      recordTypeId: HOUSEHOLD_RECORD_TYPE_ID,
      developerName: 'Household',
      name: 'Household'
    },
    '012000000000002AAA': {
      recordTypeId: '012000000000002AAA',
      developerName: 'Organization',
      name: 'Organization'
    }
  }
};

function model(overrides) {
  return {
    canEdit: true,
    automationPaused: false,
    newErrorCount: 0,
    stepsCompleted: 1,
    stepsTotal: 2,
    steps: [
      {
        key: 'coexistence',
        position: 1,
        label: 'Confirm how BarnCRM fits your existing org',
        description: 'Person Accounts orgs use the junction model.',
        targetType: 'Settings',
        target: 'General',
        setupPath: null,
        completed: true
      },
      {
        key: 'modules',
        position: 6,
        label: 'Choose which modules to turn on',
        description: 'Turn on only what you use.',
        targetType: 'Settings',
        target: 'Modules',
        setupPath: null,
        completed: false
      }
    ],
    ...overrides
  };
}

function build() {
  const element = createElement('c-hub-home', { is: HubHome });
  document.body.appendChild(element);
  return element;
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-hub-home', () => {
  beforeEach(() => {
    getHomeModel.mockResolvedValue(model());
    countInstallProblems.mockResolvedValue(0);
  });

  afterEach(() => {
    jest.clearAllMocks();
    mockNavigate.mockClear();
    mockEncodeDefaultFieldValues.mockClear();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('welcomes Maria and gives the setup assistant the whole page', async () => {
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('h1').textContent).toContain(
      'Core_HubHome_WelcomeHeading'
    );
    expect(element.shadowRoot.querySelector('c-setup-assistant')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="reopen-setup"]')).toBeNull();
  });

  it('counts errors to review and links to the Error Log', async () => {
    getHomeModel.mockResolvedValue(model({ newErrorCount: 3 }));
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="error-count"]').textContent).toBe('3');
    const link = element.shadowRoot.querySelector('a[href="/lightning/o/Error_Log__c/list"]');
    expect(link).not.toBeNull();
  });

  it('says setup completed when the install logged nothing', async () => {
    countInstallProblems.mockResolvedValue(0);
    const element = build();
    await settle();

    const status = element.shadowRoot.querySelector('[data-id="install-status"]');
    expect(status.textContent).toContain('Core_HubHome_InstallCompleted');
    expect(status.querySelector('lightning-icon')).toBeNull();
  });

  it('says setup had problems when the install logged some, and not by color alone', async () => {
    // A partly failed install used to look exactly like a good one: every step logs and
    // carries on, and the page only offered the Error Log link.
    countInstallProblems.mockResolvedValue(2);
    const element = build();
    await settle();

    const status = element.shadowRoot.querySelector('[data-id="install-status"]');
    expect(status.textContent).toContain('Core_HubHome_InstallProblems');
    expect(status.getAttribute('aria-live')).toBe('polite');
    expect(status.querySelector('lightning-icon')).not.toBeNull();
  });

  it('says nothing about the install to someone who cannot read the Error Log', async () => {
    countInstallProblems.mockResolvedValue(null);
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="install-status"]')).toBeNull();
  });

  it('still loads the page when the install count cannot be read', async () => {
    countInstallProblems.mockRejectedValue(new Error('no'));
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="install-status"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="error-count"]').textContent).toBe('0');
  });

  it('says so while automation is paused', async () => {
    getHomeModel.mockResolvedValue(model({ automationPaused: true }));
    const element = build();
    await settle();

    const banner = element.shadowRoot.querySelector('div[role="status"]');
    expect(banner.textContent).toContain('Core_HubHome_AutomationPausedBanner');
  });

  it('collapses to a tile once every step is done, and reopens on request', async () => {
    getHomeModel.mockResolvedValue(model({ stepsCompleted: 2, stepsTotal: 2 }));
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('c-setup-assistant')).toBeNull();
    // The wording is a Custom Label with numbered slots, which jest renders as its API name.
    expect(element.shadowRoot.querySelector('[data-id="setup-progress"]').textContent).toContain(
      'Core_SetupAssistant_ProgressFormat'
    );

    element.shadowRoot.querySelector('[data-id="reopen-setup"]').click();
    await settle();

    expect(element.shadowRoot.querySelector('c-setup-assistant')).not.toBeNull();
  });

  it('follows the assistant progress without reloading the page', async () => {
    getHomeModel.mockResolvedValue(model({ stepsCompleted: 1, stepsTotal: 2 }));
    const element = build();
    await settle();

    element.shadowRoot.querySelector('c-setup-assistant').dispatchEvent(
      new CustomEvent('setupchanged', {
        detail: { stepsCompleted: 2, stepsTotal: 2, isComplete: true }
      })
    );
    await settle();

    expect(element.shadowRoot.querySelector('c-setup-assistant')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="reopen-setup"]')).not.toBeNull();
  });

  it('says when the rollups last completed', async () => {
    getHomeModel.mockResolvedValue(
      model({ rollupsLastCalculated: '2026-09-08T02:00:00.000Z', rollupsStale: false })
    );
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="rollups-last-calculated"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="rollups-stale"]')).toBeNull();
  });

  it('warns when the rollups are more than 36 hours old, and not by color alone', async () => {
    getHomeModel.mockResolvedValue(model({ rollupsLastCalculated: null, rollupsStale: true }));
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="rollups-never"]')).not.toBeNull();
    const warning = element.shadowRoot.querySelector('[data-id="rollups-stale"]');
    expect(warning).not.toBeNull();
    expect(warning.getAttribute('aria-live')).toBe('polite');
    expect(warning.querySelector('lightning-icon')).not.toBeNull();
  });

  it('lists the files that arrive regularly, and says which were never imported', async () => {
    getHomeModel.mockResolvedValue(
      model({
        recurringSources: [
          { id: 'a01', sourceName: 'Event sign-ups', templateName: 'Events', lastImportDate: null },
          {
            id: 'a02',
            sourceName: 'Monthly processor export',
            templateName: 'Processor',
            lastImportDate: '2026-08-31'
          }
        ]
      })
    );
    const element = build();
    await settle();

    const sources = element.shadowRoot.querySelectorAll('[data-id="recurring-source"]');
    expect(sources).toHaveLength(2);
    expect(sources[0].textContent).toContain('Event sign-ups');
    expect(sources[1].querySelector('lightning-formatted-date-time')).not.toBeNull();
  });

  it('shows no regular files tile when nothing is marked recurring', async () => {
    getHomeModel.mockResolvedValue(model());
    const element = build();
    await settle();
    expect(element.shadowRoot.querySelector('[data-id="recurring-source"]')).toBeNull();
  });

  it('says when the seasonal addresses were last swapped and what the run did', async () => {
    getHomeModel.mockResolvedValue(
      model({
        seasonalAddressLastRun: '2027-01-15T06:30:00.000Z',
        seasonalAddressLastRunSummary:
          '3 moved to a seasonal address, 1 moved back, 0 could not be changed.',
        seasonalAddressScheduled: true,
        seasonalAddressStale: false
      })
    );
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="seasonal-last-run"]')).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="seasonal-last-run-summary"]').textContent
    ).toBe('3 moved to a seasonal address, 1 moved back, 0 could not be changed.');
    expect(element.shadowRoot.querySelector('[data-id="seasonal-stale"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="seasonal-not-scheduled"]')).toBeNull();
  });

  it('says the seasonal swap is not scheduled rather than pretending it ran', async () => {
    getHomeModel.mockResolvedValue(
      model({
        seasonalAddressLastRun: null,
        seasonalAddressScheduled: false,
        seasonalAddressStale: false
      })
    );
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="seasonal-never"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="seasonal-not-scheduled"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="seasonal-stale"]')).toBeNull();
  });

  it('warns when a scheduled seasonal swap has missed its window, and not by color alone', async () => {
    getHomeModel.mockResolvedValue(
      model({
        seasonalAddressLastRun: null,
        seasonalAddressScheduled: true,
        seasonalAddressStale: true
      })
    );
    const element = build();
    await settle();

    const warning = element.shadowRoot.querySelector('[data-id="seasonal-stale"]');
    expect(warning).not.toBeNull();
    expect(warning.getAttribute('aria-live')).toBe('polite');
    expect(warning.querySelector('lightning-icon')).not.toBeNull();
    // One message at a time: an overdue run is the fault worth reading, not the schedule.
    expect(element.shadowRoot.querySelector('[data-id="seasonal-not-scheduled"]')).toBeNull();
  });

  it('hides the New household button until the record type is resolved', async () => {
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="new-household"]')).toBeNull();
  });

  it('hides the New household button when the user cannot create accounts', async () => {
    const element = build();
    await settle();
    getObjectInfo.emit({ ...ACCOUNT_INFO, createable: false });
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="new-household"]')).toBeNull();
  });

  it('navigates straight to a new household, skipping the record-type chooser', async () => {
    const element = build();
    await settle();
    getObjectInfo.emit(ACCOUNT_INFO);
    await settle();

    const button = element.shadowRoot.querySelector('[data-id="new-household"]');
    expect(button).not.toBeNull();
    button.click();

    expect(mockEncodeDefaultFieldValues).toHaveBeenCalledWith({
      Name: 'c.Core_Households_NamePlaceholder'
    });
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: {
        objectApiName: 'Account',
        actionName: 'new'
      },
      state: {
        recordTypeId: HOUSEHOLD_RECORD_TYPE_ID,
        defaultFieldValues: 'encoded:Name=c.Core_Households_NamePlaceholder'
      }
    });
  });
});
