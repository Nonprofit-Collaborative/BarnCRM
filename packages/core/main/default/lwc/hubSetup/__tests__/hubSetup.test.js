import { createElement } from 'lwc';
import HubSetup from 'c/hubSetup';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';

jest.mock(
  '@salesforce/apex/HubController.getHomeModel',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

// The assistant loads its own state; it is not under test here.
jest.mock('@salesforce/apex/SetupAssistantController.getState', () => ({ default: jest.fn() }), {
  virtual: true
});

function build() {
  const element = createElement('c-hub-setup', { is: HubSetup });
  document.body.appendChild(element);
  return element;
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-hub-setup', () => {
  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('gives the setup assistant the tile while setup is unfinished', async () => {
    const element = build();
    getHomeModel.emit({ stepsCompleted: 1, stepsTotal: 2 });
    await settle();

    expect(element.shadowRoot.querySelector('c-setup-assistant')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="reopen-setup"]')).toBeNull();
  });

  it('keeps the checklist when the home model cannot load', async () => {
    const element = build();
    getHomeModel.error();
    await settle();

    expect(element.shadowRoot.querySelector('c-setup-assistant')).not.toBeNull();
  });

  it('collapses to a tile once every step is done, and reopens on request', async () => {
    const element = build();
    getHomeModel.emit({ stepsCompleted: 2, stepsTotal: 2 });
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

  it('waits for the home model, so a finished setup never loads the assistant', async () => {
    const getState = require('@salesforce/apex/SetupAssistantController.getState').default;
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('c-setup-assistant')).toBeNull();

    getHomeModel.emit({ stepsCompleted: 2, stepsTotal: 2 });
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="reopen-setup"]')).not.toBeNull();
    expect(getState).not.toHaveBeenCalled();
  });

  it('follows the assistant progress without reloading the page', async () => {
    const element = build();
    getHomeModel.emit({ stepsCompleted: 1, stepsTotal: 2 });
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
});
