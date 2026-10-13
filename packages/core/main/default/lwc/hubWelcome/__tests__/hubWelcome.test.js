// The test wire adapters below are emitted to on purpose, which is how a wired component is
// driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import HubWelcome from 'c/hubWelcome';
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
      name: 'Household',
      available: true
    },
    '012000000000002AAA': {
      recordTypeId: '012000000000002AAA',
      developerName: 'Organization',
      name: 'Organization',
      available: true
    }
  }
};

function model(overrides) {
  return { canEdit: true, automationPaused: false, stepsCompleted: 1, stepsTotal: 2, ...overrides };
}

function build() {
  const element = createElement('c-hub-welcome', { is: HubWelcome });
  document.body.appendChild(element);
  return element;
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

function message(element) {
  return element.shadowRoot.querySelector('[data-id="welcome-message"]').textContent;
}

describe('c-hub-welcome', () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('welcomes Maria and points her at the checklist while setup is unfinished', async () => {
    const element = build();
    getHomeModel.emit(model());
    await settle();

    expect(element.shadowRoot.querySelector('h1').textContent).toContain(
      'Core_HubHome_WelcomeHeading'
    );
    expect(message(element)).toContain('Core_HubHome_WelcomeMessage');
    expect(message(element)).not.toContain('Ready');
  });

  it('points at the tabs once setup is done', async () => {
    const element = build();
    getHomeModel.emit(model({ stepsCompleted: 2, stepsTotal: 2 }));
    await settle();

    expect(message(element)).toContain('Core_HubHome_WelcomeMessageReady');
  });

  it('never tells staff to start a checklist they cannot finish', async () => {
    const element = build();
    getHomeModel.emit(model({ canEdit: false }));
    await settle();

    expect(message(element)).toContain('Core_HubHome_WelcomeMessageReady');
  });

  it('says so while automation is paused', async () => {
    const element = build();
    getHomeModel.emit(model({ automationPaused: true }));
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="paused-banner"]').textContent).toContain(
      'Core_HubHome_AutomationPausedBanner'
    );
  });

  it('says the page could not load everything when the model fails', async () => {
    const element = build();
    getHomeModel.error();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="load-error"]').textContent).toContain(
      'Core_HubHome_LoadErrorMessage'
    );
  });

  it('hides the New household button until the record type is resolved', async () => {
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="new-household"]')).toBeNull();
  });

  it('hides the New household button when the user cannot create accounts', async () => {
    const element = build();
    getObjectInfo.emit({ ...ACCOUNT_INFO, createable: false });
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="new-household"]')).toBeNull();
  });

  it('hides the New household button when the user may not use the household record type', async () => {
    const element = build();
    const infos = { ...ACCOUNT_INFO.recordTypeInfos };
    infos[HOUSEHOLD_RECORD_TYPE_ID] = { ...infos[HOUSEHOLD_RECORD_TYPE_ID], available: false };
    getObjectInfo.emit({ ...ACCOUNT_INFO, recordTypeInfos: infos });
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="new-household"]')).toBeNull();
  });

  it('navigates straight to a new household, skipping the record-type chooser', async () => {
    const element = build();
    getObjectInfo.emit(ACCOUNT_INFO);
    await settle();

    element.shadowRoot.querySelector('[data-id="new-household"]').click();

    expect(mockEncodeDefaultFieldValues).toHaveBeenCalledWith({
      Name: 'c.Core_Households_NamePlaceholder'
    });
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__objectPage',
      attributes: { objectApiName: 'Account', actionName: 'new' },
      state: {
        recordTypeId: HOUSEHOLD_RECORD_TYPE_ID,
        defaultFieldValues: 'encoded:Name=c.Core_Households_NamePlaceholder'
      }
    });
  });
});
