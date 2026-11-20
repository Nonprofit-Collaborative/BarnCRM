import { createElement } from 'lwc';
import SuperConnector from 'c/superConnector';
import getConnections from '@salesforce/apex/ConnectorConnectionsController.getConnections';
import checkConnection from '@salesforce/apex/ConnectorConnectionsController.checkConnection';
import disconnect from '@salesforce/apex/ConnectorConnectionsController.disconnect';
import deleteConnection from '@salesforce/apex/ConnectorConnectionsController.deleteConnection';
import BarnConfirmModal from 'c/barnConfirmModal';
import { expectAccessible } from 'barn/a11y';

const fs = require('fs');
const path = require('path');

jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.getConnections',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.checkConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.disconnect',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.deleteConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.createConnection',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.replaceKey',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const READY = {
  name: 'BarnConn_rest_abc123',
  label: 'Mailing List',
  authKind: 'BearerToken',
  host: 'api.example.org',
  calloutsEnabled: true,
  accessGranted: true,
  keyStored: true
};
const WAITING = {
  name: 'BarnConn_rest_def456',
  label: 'Ledger',
  authKind: 'SecretUrl',
  host: 'hooks.example.org',
  lastFour: 'WXYZ',
  calloutsEnabled: false,
  accessGranted: false,
  keyStored: true
};
const PAGE = { canWrite: true, connections: [READY, WAITING] };

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

async function render(page = PAGE) {
  getConnections.mockResolvedValue(page);
  const element = createElement('c-super-connector', { is: SuperConnector });
  document.body.appendChild(element);
  await flush();
  return element;
}

describe('c-super-connector', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists connections with status and the Setup step, never a key', async () => {
    const element = await render();
    expect(find(element, READY.name)).not.toBeNull();
    expect(find(element, `status-${READY.name}`).message).toBe('c.Connector_Status_Ready');
    expect(find(element, `steps-${READY.name}`)).toBeNull();
    expect(find(element, `status-${WAITING.name}`).message).toBe('c.Connector_Status_CalloutsOff');
    expect(find(element, `steps-${WAITING.name}`)).not.toBeNull();
    expect(find(element, `check-${WAITING.name}`).label).toBe('c.Connector_Page_CheckAgain');
    expect(find(element, `disconnect-${READY.name}`)).not.toBeNull();
    expect(find(element, `disconnect-${WAITING.name}`)).toBeNull();
    expect(element.shadowRoot.querySelector('lightning-input[type="password"]')).toBeNull();
    await expectAccessible(element);
  });

  it('shows the empty state and hides writes for a manager without the credential permission', async () => {
    const element = await render({ canWrite: false, connections: [] });
    expect(find(element, 'empty')).not.toBeNull();
    expect(find(element, 'new')).toBeNull();
    expect(find(element, 'no-write')).not.toBeNull();
    await expectAccessible(element);
  });

  it('opens the key form for New Connection and closes it on save', async () => {
    const element = await render();
    find(element, 'new').click();
    await flush();
    const form = find(element, 'key-form');
    expect(form.mode).toBe('create');
    form.dispatchEvent(
      new CustomEvent('saved', {
        detail: { result: { outcome: 'created', page: { canWrite: true, connections: [READY] } } }
      })
    );
    await flush();
    expect(find(element, 'key-form')).toBeNull();
    expect(find(element, 'message').message).toBe('c.Connector_Outcome_Created');
    expect(find(element, WAITING.name)).toBeNull();
  });

  it('opens Replace Key for the row and shows a failure', async () => {
    const element = await render();
    find(element, `replace-${READY.name}`).click();
    await flush();
    const form = find(element, 'key-form');
    expect(form.mode).toBe('replace');
    expect(form.connection.name).toBe(READY.name);
    form.dispatchEvent(new CustomEvent('failed', { detail: { message: 'Not saved' } }));
    await flush();
    expect(find(element, 'error').message).toBe('Not saved');
    form.dispatchEvent(new CustomEvent('cancel'));
    await flush();
    expect(find(element, 'key-form')).toBeNull();
  });

  it('checks a connection and shows the answer', async () => {
    checkConnection.mockResolvedValue({ outcome: 'answered', status: 401, page: PAGE });
    const element = await render();
    find(element, `check-${READY.name}`).click();
    await flush();
    expect(checkConnection).toHaveBeenCalledWith({ name: READY.name });
    expect(find(element, 'message').message).toBe('c.Connector_Outcome_KeyRefused');
  });

  it('disconnects and deletes only after confirming', async () => {
    BarnConfirmModal.open = jest.fn().mockResolvedValueOnce(false).mockResolvedValue(true);
    disconnect.mockResolvedValue({ outcome: 'disconnected', page: PAGE });
    deleteConnection.mockResolvedValue({ outcome: 'deleted', page: PAGE });
    const element = await render();
    find(element, `disconnect-${READY.name}`).click();
    await flush();
    expect(disconnect).not.toHaveBeenCalled();
    find(element, `disconnect-${READY.name}`).click();
    await flush();
    expect(disconnect).toHaveBeenCalledWith({ name: READY.name });
    find(element, `delete-${WAITING.name}`).click();
    await flush();
    expect(deleteConnection).toHaveBeenCalledWith({ name: WAITING.name });
    expect(find(element, 'message').message).toBe('c.Connector_Outcome_Deleted');
  });

  it('offers no Replace Key for a Secret URL and shows the Setup step after Delete', async () => {
    BarnConfirmModal.open = jest.fn().mockResolvedValue(true);
    deleteConnection.mockResolvedValue({ outcome: 'deleteInSetup', page: PAGE });
    const element = await render();
    expect(find(element, `replace-${READY.name}`)).not.toBeNull();
    expect(find(element, `replace-${WAITING.name}`)).toBeNull();
    find(element, `delete-${READY.name}`).click();
    await flush();
    expect(find(element, 'message').message).toBe('c.Connector_Outcome_DeleteInSetup');
    expect(find(element, 'message').variant).toBe('warning');
  });

  it('shows a load failure', async () => {
    getConnections.mockRejectedValue({ body: { message: 'No access' } });
    const element = createElement('c-super-connector', { is: SuperConnector });
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'error').message).toBe('No access');
  });

  it('never logs to the console in any Connector component (F10)', () => {
    // eslint-disable-next-line no-undef
    const root = path.resolve(__dirname, '..', '..');
    ['superConnector', 'connectorKeyForm', 'connectorRules', 'connectorText'].forEach((bundle) => {
      const source = fs.readFileSync(path.join(root, bundle, `${bundle}.js`), 'utf8');
      expect(source).not.toMatch(/console\./);
    });
  });
});
