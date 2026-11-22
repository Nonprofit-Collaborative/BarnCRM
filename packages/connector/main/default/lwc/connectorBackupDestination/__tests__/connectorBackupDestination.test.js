import { createElement } from 'lwc';
import ConnectorBackupDestination from 'c/connectorBackupDestination';
import { expectAccessible } from 'barn/a11y';
import getBackupDestination from '@salesforce/apex/ConnectorConnectionsController.getBackupDestination';
import saveBackupDestination from '@salesforce/apex/ConnectorConnectionsController.saveBackupDestination';
import stopBackupDestination from '@salesforce/apex/ConnectorConnectionsController.stopBackupDestination';

jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.getBackupDestination',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.saveBackupDestination',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ConnectorConnectionsController.stopBackupDestination',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

const CONNECTIONS = [
  { name: 'BarnConn_rest_aaaaaa', label: 'Nextcloud' },
  { name: 'BarnConn_rest_bbbbbb', label: 'Mailing List' }
];
const SET = {
  canWrite: true,
  name: 'BarnConn_rest_aaaaaa',
  settings: {
    method: 'PUT',
    path: '/barncrm/{file}',
    headers: [{ name: 'Overwrite', value: 'T' }]
  },
  note: null
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

const find = (element, id) => element.shadowRoot.querySelector(`[data-id="${id}"]`);

function render(canWrite = true) {
  const element = createElement('c-connector-backup-destination', {
    is: ConnectorBackupDestination
  });
  element.canWrite = canWrite;
  element.connections = CONNECTIONS;
  document.body.appendChild(element);
  return element;
}

describe('c-connector-backup-destination', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says when no connection is the destination and offers to set one', async () => {
    getBackupDestination.mockResolvedValue({
      canWrite: true,
      name: null,
      settings: null,
      note: 'c.Connector_Backup_NotSet'
    });
    const element = render();
    await flush();
    expect(find(element, 'backup-summary').textContent).toBe('c.Connector_Backup_None');
    expect(find(element, 'backup-note')).toBeNull();
    expect(find(element, 'backup-edit').label).toBe('c.Connector_Backup_Set');
    expect(find(element, 'backup-stop')).toBeNull();
    await expectAccessible(element);
  });

  it('shows the destination and its note, and saves a change as header lines', async () => {
    getBackupDestination.mockResolvedValue({ ...SET, note: 'c.Connector_Backup_NoAccess' });
    saveBackupDestination.mockResolvedValue({
      ...SET,
      settings: { ...SET.settings, method: 'POST' }
    });
    const element = render();
    await flush();
    expect(find(element, 'backup-summary').textContent).toBe('Nextcloud: PUT /barncrm/{file}');
    expect(find(element, 'backup-note').message).toBe('c.Connector_Backup_NoAccess');

    find(element, 'backup-edit').click();
    await flush();
    expect(find(element, 'backup-headers').value).toBe('Overwrite: T');
    const method = find(element, 'backup-method');
    method.dispatchEvent(new CustomEvent('change', { detail: { value: 'POST' } }));
    find(element, 'backup-save').click();
    await flush();
    expect(saveBackupDestination).toHaveBeenCalledWith({
      name: 'BarnConn_rest_aaaaaa',
      method: 'POST',
      path: '/barncrm/{file}',
      headers: 'Overwrite: T',
      metadata: ''
    });
    expect(find(element, 'backup-form')).toBeNull();
    expect(find(element, 'backup-summary').textContent).toBe('Nextcloud: POST /barncrm/{file}');
  });

  it('keeps the form open with the refusal when a save is refused', async () => {
    getBackupDestination.mockResolvedValue(SET);
    saveBackupDestination.mockRejectedValue({
      body: { message: 'The path must start with one slash.' }
    });
    const element = render();
    await flush();
    find(element, 'backup-edit').click();
    await flush();
    find(element, 'backup-save').click();
    await flush();
    expect(find(element, 'backup-error').message).toBe('The path must start with one slash.');
    expect(find(element, 'backup-form')).not.toBeNull();
  });

  it('stops using the destination', async () => {
    getBackupDestination.mockResolvedValue(SET);
    stopBackupDestination.mockResolvedValue({
      canWrite: true,
      name: null,
      settings: null,
      note: 'x'
    });
    const element = render();
    await flush();
    find(element, 'backup-stop').click();
    await flush();
    expect(stopBackupDestination).toHaveBeenCalled();
    expect(find(element, 'backup-summary').textContent).toBe('c.Connector_Backup_None');
  });

  it('opens filled in from an OAuth template, offering only OAuth connections (R-CN12)', async () => {
    getBackupDestination.mockResolvedValue({
      canWrite: true,
      name: null,
      settings: null,
      note: null
    });
    saveBackupDestination.mockResolvedValue(SET);
    const element = createElement('c-connector-backup-destination', {
      is: ConnectorBackupDestination
    });
    element.canWrite = true;
    element.connections = [
      ...CONNECTIONS,
      { name: 'BarnConn_gdrive', label: 'Google Drive', authKind: 'OAuth' }
    ];
    document.body.appendChild(element);
    await flush();
    element.fromTemplate = {
      method: 'POST',
      path: '/upload/drive/v3/files?uploadType=multipart',
      headers: [],
      metadata: '{"name":"{file}"}'
    };
    await flush();
    expect(find(element, 'backup-template-note').message).toBe('c.Connector_Backup_FromTemplate');
    expect(find(element, 'backup-connection').options).toEqual([
      { label: 'Google Drive', value: 'BarnConn_gdrive' }
    ]);
    expect(find(element, 'backup-metadata').value).toBe('{"name":"{file}"}');
    find(element, 'backup-save').click();
    await flush();
    expect(saveBackupDestination).toHaveBeenCalledWith({
      name: 'BarnConn_gdrive',
      method: 'POST',
      path: '/upload/drive/v3/files?uploadType=multipart',
      headers: '',
      metadata: '{"name":"{file}"}'
    });
    expect(find(element, 'backup-form')).toBeNull();
  });

  it('offers no change to a person who may not write keys', async () => {
    getBackupDestination.mockResolvedValue({ ...SET, canWrite: false });
    const element = render(false);
    await flush();
    expect(find(element, 'backup-edit')).toBeNull();
  });
});
