import { createElement } from 'lwc';
import ConnectorKeyForm from 'c/connectorKeyForm';
import createConnection from '@salesforce/apex/ConnectorConnectionsController.createConnection';
import replaceKey from '@salesforce/apex/ConnectorConnectionsController.replaceKey';
import saveCheckPath from '@salesforce/apex/ConnectorConnectionsController.saveCheckPath';
import saveFirstKey from '@salesforce/apex/ConnectorConnectionsController.saveFirstKey';
import saveBackupDestination from '@salesforce/apex/ConnectorConnectionsController.saveBackupDestination';
import { expectAccessible } from 'barn/a11y';

jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.saveBackupDestination',
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
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.saveCheckPath',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.saveFirstKey',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const SECRET = 'sk_live_ABCDEFGH12345678';

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

function render(props = {}) {
  const element = createElement('c-connector-key-form', { is: ConnectorKeyForm });
  Object.assign(element, props);
  document.body.appendChild(element);
  return element;
}

async function type(element, id, value) {
  const input = find(element, id);
  input.value = value;
  input.dispatchEvent(new CustomEvent('change', { detail: { value } }));
  await flush();
}

async function fillBearer(element) {
  await type(element, 'label', 'Mailing List');
  await type(element, 'base-url', 'https://api.example.org/v2');
  find(element, 'secret').value = SECRET;
}

describe('c-connector-key-form', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('asks for the key in an empty password box the browser will not fill (F10)', async () => {
    const element = render();
    await flush();
    const box = find(element, 'secret');
    expect(box.type).toBe('password');
    expect(box.autocomplete).toBe('new-password');
    expect(box.value).toBeFalsy();
    expect(find(element, 'debug-notice')).not.toBeNull();
    await expectAccessible(element);
  });

  it('creates, then sends the key once in its own call, empties the box and never puts the key in the event (F10)', async () => {
    const page = { canWrite: true, connections: [{ name: 'BarnConn_rest_abc123' }] };
    createConnection.mockResolvedValue({ outcome: 'created', name: 'BarnConn_rest_abc123' });
    saveFirstKey.mockResolvedValue({ outcome: 'keySaved', page });
    const element = render();
    await flush();
    await fillBearer(element);
    const saved = jest.fn();
    element.addEventListener('saved', saved);
    find(element, 'save').click();
    await flush();
    await flush();
    expect(createConnection).toHaveBeenCalledWith({
      label: 'Mailing List',
      authKind: 'BearerToken',
      baseUrl: 'https://api.example.org/v2',
      headerName: '',
      secretUrl: null
    });
    expect(saveFirstKey).toHaveBeenCalledWith({
      name: 'BarnConn_rest_abc123',
      userName: '',
      secret: SECRET
    });
    expect(find(element, 'secret').value).toBe('');
    expect(saved).toHaveBeenCalledTimes(1);
    expect(saved.mock.calls[0][0].detail.result).toEqual({
      outcome: 'created',
      name: 'BarnConn_rest_abc123',
      page
    });
    expect(JSON.stringify(saved.mock.calls[0][0].detail)).not.toContain(SECRET);
    expect(JSON.stringify(Object.values(element))).not.toContain(SECRET);
  });

  it('sends a Secret URL with the create and no second call (F5)', async () => {
    createConnection.mockResolvedValue({ outcome: 'created', name: 'BarnConn_rest_abc123' });
    const element = render({
      prefill: { label: 'Team Channel', authKind: 'SecretUrl', urlParams: [] }
    });
    await flush();
    find(element, 'secret').value = 'https://hooks.example.org/services/abc';
    find(element, 'save').click();
    await flush();
    await flush();
    expect(createConnection).toHaveBeenCalledWith(
      expect.objectContaining({
        authKind: 'SecretUrl',
        secretUrl: 'https://hooks.example.org/services/abc'
      })
    );
    expect(saveFirstKey).not.toHaveBeenCalled();
  });

  it('keeps a template check path with the new connection in its own call (R-CN9)', async () => {
    createConnection.mockResolvedValue({ outcome: 'created', name: 'BarnConn_rest_abc123' });
    saveCheckPath.mockResolvedValue(undefined);
    const element = render({
      prefill: {
        label: 'Mailing List',
        authKind: 'BearerToken',
        baseUrl: 'https://api.example.org/v2',
        urlParams: [],
        checkPath: '/ping'
      }
    });
    await flush();
    find(element, 'secret').value = SECRET;
    const saved = jest.fn();
    element.addEventListener('saved', saved);
    find(element, 'save').click();
    await flush();
    await flush();
    expect(saveCheckPath).toHaveBeenCalledWith({
      name: 'BarnConn_rest_abc123',
      checkPath: '/ping'
    });
    expect(JSON.stringify(saveCheckPath.mock.calls)).not.toContain(SECRET);
    expect(saveBackupDestination).not.toHaveBeenCalled();
    expect(saved).toHaveBeenCalledTimes(1);
  });

  it('saves a template backup part as the backup destination after the create (R-CN11)', async () => {
    createConnection.mockResolvedValue({ outcome: 'created', name: 'BarnConn_rest_abc123' });
    saveBackupDestination.mockResolvedValue({});
    const element = render({
      prefill: {
        label: 'Storage',
        authKind: 'BearerToken',
        baseUrl: 'https://files.example.org',
        urlParams: [],
        backup: { method: 'PUT', path: '/barncrm/{file}', headers: [{ name: 'X-Folder', value: 'crm' }] }
      }
    });
    await flush();
    find(element, 'secret').value = SECRET;
    find(element, 'save').click();
    await flush();
    await flush();
    expect(saveBackupDestination).toHaveBeenCalledWith({
      name: 'BarnConn_rest_abc123',
      method: 'PUT',
      path: '/barncrm/{file}',
      headers: 'X-Folder: crm'
    });
    expect(JSON.stringify(saveBackupDestination.mock.calls)).not.toContain(SECRET);
  });

  it('empties the box after a failure and passes on only the message', async () => {
    createConnection.mockRejectedValue({ body: { message: 'Not saved' } });
    const element = render();
    await flush();
    await fillBearer(element);
    const failed = jest.fn();
    element.addEventListener('failed', failed);
    find(element, 'save').click();
    await flush();
    expect(find(element, 'secret').value).toBe('');
    expect(failed.mock.calls[0][0].detail).toEqual({ message: 'Not saved' });
  });

  it('does not send a form with problems', async () => {
    const element = render();
    await flush();
    find(element, 'save').click();
    await flush();
    expect(createConnection).not.toHaveBeenCalled();
    expect(find(element, 'problems')).not.toBeNull();
  });

  it('shows the header name for an API key and the Secret URL disclosure (F5)', async () => {
    const element = render();
    await flush();
    await type(element, 'kind', 'ApiKeyHeader');
    expect(find(element, 'header-name')).not.toBeNull();
    await type(element, 'kind', 'SecretUrl');
    expect(find(element, 'base-url')).toBeNull();
    expect(find(element, 'secret-url-notice')).not.toBeNull();
    expect(find(element, 'secret').label).toBe('c.Connector_Form_SecretUrl');
    await expectAccessible(element);
  });

  it('replaces a key by name, asking for the user name of a Basic connection', async () => {
    replaceKey.mockResolvedValue({ outcome: 'replaced' });
    const element = render({
      mode: 'replace',
      connection: { name: 'BarnConn_rest_abc123', label: 'Ledger', authKind: 'BasicAuth' }
    });
    await flush();
    expect(find(element, 'label')).toBeNull();
    await type(element, 'user-name', 'api-user');
    find(element, 'secret').value = SECRET;
    find(element, 'save').click();
    await flush();
    expect(replaceKey).toHaveBeenCalledWith({
      name: 'BarnConn_rest_abc123',
      userName: 'api-user',
      secret: SECRET
    });
    expect(find(element, 'secret').value).toBe('');
  });

  it('empties the box on Cancel', async () => {
    const element = render();
    await flush();
    find(element, 'secret').value = SECRET;
    const cancel = jest.fn();
    element.addEventListener('cancel', cancel);
    find(element, 'cancel').click();
    expect(find(element, 'secret').value).toBe('');
    expect(cancel).toHaveBeenCalled();
  });
});
