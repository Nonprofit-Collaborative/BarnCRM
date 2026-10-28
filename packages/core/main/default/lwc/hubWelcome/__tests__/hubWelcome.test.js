// The test wire adapters below are emitted to on purpose, which is how a wired component is
// driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import HubWelcome from 'c/hubWelcome';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import createHousehold from '@salesforce/apex/HubController.createHousehold';

jest.mock(
  '@salesforce/apex/HubController.getHomeModel',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/HubController.createHousehold', () => ({ default: jest.fn() }), {
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

const NEW_HOUSEHOLD_ID = '001000000000001AAA';

function model(overrides) {
  return {
    canEdit: true,
    automationPaused: false,
    stepsCompleted: 1,
    stepsTotal: 2,
    canCreateHousehold: true,
    ...overrides
  };
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

function button(element) {
  return element.shadowRoot.querySelector('[data-id="new-household"]');
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

  it('hides the New household button until the home model has loaded', async () => {
    const element = build();
    await settle();

    expect(button(element)).toBeNull();
  });

  it('hides the New household button from someone who may not create a household', async () => {
    const element = build();
    getHomeModel.emit(model({ canCreateHousehold: false }));
    await settle();

    expect(button(element)).toBeNull();
  });

  it('creates the household in Apex and opens it, without the standard New form', async () => {
    createHousehold.mockResolvedValue(NEW_HOUSEHOLD_ID);
    const element = build();
    getHomeModel.emit(model());
    await settle();

    button(element).click();
    await settle();

    expect(createHousehold).toHaveBeenCalledTimes(1);
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__recordPage',
      attributes: { recordId: NEW_HOUSEHOLD_ID, objectApiName: 'Account', actionName: 'view' }
    });
    expect(element.shadowRoot.querySelector('[data-id="create-error"]')).toBeNull();
  });

  it('shows why when the household could not be created, and stays on the page', async () => {
    createHousehold.mockRejectedValue({ body: { message: 'You need permission' } });
    const element = build();
    getHomeModel.emit(model());
    await settle();

    button(element).click();
    await settle();

    expect(mockNavigate).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="create-error"]').textContent).toContain(
      'You need permission'
    );
    expect(button(element).disabled).toBe(false);
  });

  it('falls back to its own message when the error has none', async () => {
    createHousehold.mockRejectedValue({});
    const element = build();
    getHomeModel.emit(model());
    await settle();

    button(element).click();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="create-error"]').textContent).toContain(
      'Core_HubHomeActions_NewHouseholdFailed'
    );
  });
});
