import { createElement } from 'lwc';
import ConnectorRecipeClock from 'c/connectorRecipeClock';
import getClock from '@salesforce/apex/ConnectorRecipesController.getClock';
import setRecipesPaused from '@salesforce/apex/ConnectorRecipesController.setRecipesPaused';
import restartClock from '@salesforce/apex/ConnectorRecipesController.restartClock';
import getIntegrationUser from '@salesforce/apex/ConnectorRecipesController.getIntegrationUser';
import chooseIntegrationUser from '@salesforce/apex/ConnectorRecipesController.chooseIntegrationUser';
import { expectAccessible } from 'barn/a11y';

jest.mock('@salesforce/apex/ConnectorRecipesController.getClock', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.setRecipesPaused',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.restartClock',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.getIntegrationUser',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorRecipesController.chooseIntegrationUser',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const CLOCK = {
  paused: false,
  automationPaused: false,
  lanes: [
    { lane: 'Automation', needed: true, beating: false },
    { lane: 'IntegrationUser', needed: false, beating: false }
  ]
};
const USER = {
  id: '005000000000001',
  name: 'BarnCRM Integration',
  active: true,
  hasConnections: true,
  orgConnectionReady: true,
  confirmed: false,
  lastWrite: 'Completed'
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render() {
  const element = createElement('c-connector-recipe-clock', { is: ConnectorRecipeClock });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-connector-recipe-clock', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows each lane, the integration user and the Setup step, and is accessible', async () => {
    getClock.mockResolvedValue(CLOCK);
    getIntegrationUser.mockResolvedValue(USER);
    const element = await render();
    expect(find(element, 'lane-Automation').textContent).toContain('c.Connector_Lane_Automation');
    expect(find(element, 'lane-Automation').querySelector('c-barn-status-badge').label).toBe(
      'c.Connector_Clock_Stopped'
    );
    expect(find(element, 'pending')).not.toBeNull();
    expect(find(element, 'user-steps')).not.toBeNull();
    expect(find(element, 'last-write')).not.toBeNull();
    expect(find(element, 'paused')).toBeNull();
    await expectAccessible(element);
  });

  it('pauses every recipe and restarts the clock', async () => {
    getClock.mockResolvedValue(CLOCK);
    getIntegrationUser.mockResolvedValue(USER);
    setRecipesPaused.mockResolvedValue({ ...CLOCK, paused: true });
    restartClock.mockResolvedValue({
      ...CLOCK,
      lanes: [{ lane: 'Automation', needed: true, beating: true }]
    });
    const element = await render();

    const toggle = find(element, 'pause-all');
    toggle.checked = true;
    toggle.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(setRecipesPaused).toHaveBeenCalledWith({ paused: true });
    expect(find(element, 'paused')).not.toBeNull();

    find(element, 'restart').click();
    await flush();
    expect(restartClock).toHaveBeenCalled();
    expect(find(element, 'lane-Automation').querySelector('c-barn-status-badge').label).toBe(
      'c.Connector_Clock_Going'
    );
  });

  it('saves the chosen user and tells the Recipes tab', async () => {
    getClock.mockResolvedValue(CLOCK);
    getIntegrationUser.mockResolvedValue({ orgConnectionReady: true });
    chooseIntegrationUser.mockResolvedValue({ ...USER, hasConnections: false });
    const element = await render();
    expect(find(element, 'none')).not.toBeNull();
    const changed = jest.fn();
    element.addEventListener('changed', changed);

    find(element, 'user-picker').dispatchEvent(
      new CustomEvent('change', { detail: { recordId: USER.id } })
    );
    find(element, 'user-save').click();
    await flush();
    expect(chooseIntegrationUser).toHaveBeenCalledWith({ userId: USER.id });
    expect(changed).toHaveBeenCalled();
    expect(find(element, 'access')).not.toBeNull();
    expect(find(element, 'message').message).toBe('c.Connector_User_Saved');
  });

  it('cannot save without the org connection and shows a refusal plainly', async () => {
    getClock.mockResolvedValue({ ...CLOCK, automationPaused: true });
    getIntegrationUser.mockResolvedValue({ ...USER, orgConnectionReady: false, active: false });
    restartClock.mockRejectedValue({ body: { message: 'Not allowed.' } });
    const element = await render();
    expect(find(element, 'user-save').disabled).toBe(true);
    expect(find(element, 'org')).not.toBeNull();
    expect(find(element, 'inactive')).not.toBeNull();
    expect(find(element, 'automation-paused')).not.toBeNull();

    find(element, 'restart').click();
    await flush();
    expect(find(element, 'error').message).toBe('Not allowed.');
  });
});
