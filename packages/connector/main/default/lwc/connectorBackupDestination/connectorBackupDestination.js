import { LightningElement, api } from 'lwc';
import getBackupDestination from '@salesforce/apex/ConnectorConnectionsController.getBackupDestination';
import saveBackupDestination from '@salesforce/apex/ConnectorConnectionsController.saveBackupDestination';
import stopBackupDestination from '@salesforce/apex/ConnectorConnectionsController.stopBackupDestination';
import { helpText } from 'c/barnHelpText';
import { headerLines } from 'c/connectorFileRules';
import { OAUTH } from 'c/connectorRules';

/**
 * Backup Destination on the Connections tab of Super Connector (BK-10; canonical model R-CN11;
 * admin guide connector.md#backup-destination): which connection Backup Sets and archives send
 * their CSV files through, by PUT or POST to a path with `{file}`, with fixed headers that hold
 * no secret. Read again whenever the connection list changes, so a template that set it, or a
 * deleted connection, shows at once.
 */
export default class ConnectorBackupDestination extends LightningElement {
  @api canWrite = false;
  setup;
  editing = false;
  busy = false;
  errorMessage;
  draft = {};
  _connections = [];

  @api
  get connections() {
    return this._connections;
  }

  set connections(value) {
    this._connections = value || [];
    this.load();
  }

  /**
   * An OAuth template's Backup Settings (R-CN12): the connection is made in Setup, so the form
   * opens filled in, offering only OAuth connections, for the admin to choose one and save.
   */
  @api
  get fromTemplate() {
    return this._fromTemplate;
  }

  set fromTemplate(value) {
    this._fromTemplate = value;
    if (value && value.path) {
      const oauth = this._connections.find((connection) => connection.authKind === OAUTH);
      this.draft = {
        name: oauth ? oauth.name : undefined,
        method: value.method || 'PUT',
        path: value.path,
        headers: headerLines(value.headers),
        metadata: value.metadata || ''
      };
      this.templateNote = helpText('Connector', 'Connector_Backup_FromTemplate');
      this.editing = true;
    }
  }

  _fromTemplate;
  templateNote;

  get labels() {
    return {
      heading: helpText('Connector', 'Connector_Backup_Heading'),
      intro: helpText('Connector', 'Connector_Backup_Intro'),
      connection: helpText('Connector', 'Connector_Backup_Connection'),
      method: helpText('Connector', 'Connector_Backup_Method'),
      path: helpText('Connector', 'Connector_Backup_Path'),
      pathHelp: helpText('Connector', 'Connector_Backup_PathHelp'),
      headers: helpText('Connector', 'Connector_Backup_Headers'),
      headersHelp: helpText('Connector', 'Connector_Backup_HeadersHelp'),
      metadata: helpText('Connector', 'Connector_Backup_Metadata'),
      metadataHelp: helpText('Connector', 'Connector_Backup_MetadataHelp'),
      set: helpText('Connector', 'Connector_Backup_Set'),
      change: helpText('Connector', 'Connector_Backup_Change'),
      save: helpText('Connector', 'Connector_Backup_Save'),
      stop: helpText('Connector', 'Connector_Backup_Stop'),
      cancel: helpText('Connector', 'Connector_Form_Cancel')
    };
  }

  async load() {
    try {
      this.setup = await getBackupDestination();
      this.errorMessage = undefined;
    } catch (failure) {
      this.errorMessage = messageOf(failure);
    }
  }

  get isSet() {
    return Boolean(this.setup && this.setup.name);
  }

  get showChange() {
    return this.canWrite && !this.editing && this._connections.length > 0;
  }

  get changeLabel() {
    return this.isSet ? this.labels.change : this.labels.set;
  }

  /** The destination in one line: connection, method and path. */
  get summary() {
    if (!this.isSet) {
      return helpText('Connector', 'Connector_Backup_None');
    }
    const found = this._connections.find((connection) => connection.name === this.setup.name);
    const label = found ? found.label : this.setup.name;
    return `${label}: ${this.setup.settings.method} ${this.setup.settings.path}`;
  }

  get note() {
    return this.isSet && this.setup.note ? this.setup.note : '';
  }

  get connectionOptions() {
    return this._connections
      .filter((connection) => !this.templateNote || connection.authKind === OAUTH)
      .map((connection) => ({ label: connection.label, value: connection.name }));
  }

  get methodOptions() {
    return [
      { label: 'PUT', value: 'PUT' },
      { label: 'POST', value: 'POST' }
    ];
  }

  handleEdit() {
    const settings = (this.setup && this.setup.settings) || {};
    this.draft = {
      name: (this.setup && this.setup.name) || (this._connections[0] && this._connections[0].name),
      method: settings.method || 'PUT',
      path: settings.path || '/{file}',
      headers: headerLines(settings.headers),
      metadata: settings.metadata || ''
    };
    this.templateNote = undefined;
    this.editing = true;
  }

  handleChange(event) {
    this.draft = { ...this.draft, [event.target.dataset.field]: event.detail.value };
  }

  handleCancel() {
    this.editing = false;
    this.templateNote = undefined;
    this.errorMessage = undefined;
  }

  async handleSave() {
    if (await this.act(() => saveBackupDestination({ ...this.draft }))) {
      this.editing = false;
      this.templateNote = undefined;
    }
  }

  handleStop() {
    return this.act(() => stopBackupDestination());
  }

  async act(call) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      this.setup = await call();
      return true;
    } catch (failure) {
      this.errorMessage = messageOf(failure);
      return false;
    } finally {
      this.busy = false;
    }
  }
}

function messageOf(failure) {
  return (
    (failure && failure.body && failure.body.message) ||
    helpText('Connector', 'Connector_Error_Unexpected')
  );
}
