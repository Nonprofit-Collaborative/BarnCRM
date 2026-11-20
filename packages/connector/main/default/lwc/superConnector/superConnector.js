import { LightningElement } from 'lwc';
import getConnections from '@salesforce/apex/ConnectorConnectionsController.getConnections';
import checkConnection from '@salesforce/apex/ConnectorConnectionsController.checkConnection';
import disconnect from '@salesforce/apex/ConnectorConnectionsController.disconnect';
import deleteConnection from '@salesforce/apex/ConnectorConnectionsController.deleteConnection';
import BarnConfirmModal from 'c/barnConfirmModal';
import { isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';
import { kindKey, statusOf, outcomeOf, SECRET_URL } from 'c/connectorRules';
import { say as text } from 'c/connectorText';

const PKG = 'Connector';

/**
 * The Super Connector tab (CN-01): the Connections section. Lists the org's BarnCRM connections
 * by name, kind, host and status (never a key or a Secret URL), shows the one Setup step a new
 * connection needs with Check Again, and offers Check Connection, Replace Key, Disconnect and
 * Delete. New Connection and Replace Key open c/connectorKeyForm, the only place a key is typed.
 */
export default class SuperConnector extends LightningElement {
  helpReady = isHelpLoaded(PKG);
  page;
  working = false;
  formMode;
  formConnection;
  message;
  messageVariant = 'success';
  error;

  labels = {
    get title() {
      return text('Connector_Page_Title');
    },
    get intro() {
      return text('Connector_Page_Intro');
    },
    get connections() {
      return text('Connector_Page_Connections');
    },
    get newConnection() {
      return text('Connector_Page_New');
    },
    get empty() {
      return text('Connector_Page_Empty');
    },
    get noWrite() {
      return text('Connector_Page_NoWrite');
    },
    get replaceKey() {
      return text('Connector_Page_ReplaceKey');
    },
    get disconnect() {
      return text('Connector_Page_Disconnect');
    },
    get delete() {
      return text('Connector_Page_Delete');
    }
  };

  icons = { page: iconFor('Super_Connector') };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(PKG).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.error = undefined;
    try {
      this.page = await getConnections();
    } catch (failure) {
      this.error = this.messageOf(failure);
    }
  }

  get loaded() {
    return Boolean(this.page);
  }

  get loading() {
    return !this.error && (!this.loaded || this.working);
  }

  get canWrite() {
    return this.loaded && this.page.canWrite === true;
  }

  get noWriteShown() {
    return this.loaded && !this.canWrite;
  }

  get formOpen() {
    return Boolean(this.formMode);
  }

  get busy() {
    return this.working || this.formOpen;
  }

  get empty() {
    return this.loaded && !(this.page.connections || []).length && !this.formOpen;
  }

  /** Each connection with its status, Setup steps and button ids. */
  get rows() {
    if (!this.loaded) {
      return [];
    }
    return (this.page.connections || []).map((connection) => {
      const status = statusOf(connection);
      const host =
        connection.authKind === SECRET_URL
          ? text('Connector_Row_SecretHost', connection.host, connection.lastFour)
          : connection.host;
      return {
        ...connection,
        detail: text('Connector_Row_Detail', text(kindKey(connection.authKind)), host),
        statusText: text(status.key),
        statusVariant: status.variant,
        showSteps: !connection.calloutsEnabled || !connection.accessGranted,
        steps: !connection.calloutsEnabled
          ? text('Connector_Row_CalloutSteps', connection.label)
          : text('Connector_Row_AccessSteps', connection.name),
        canReplace: connection.authKind !== SECRET_URL,
        checkLabel:
          connection.calloutsEnabled && connection.accessGranted
            ? text('Connector_Page_Check')
            : text('Connector_Page_CheckAgain'),
        canDisconnect: connection.authKind !== SECRET_URL && connection.keyStored,
        statusId: `status-${connection.name}`,
        stepsId: `steps-${connection.name}`,
        checkId: `check-${connection.name}`,
        replaceId: `replace-${connection.name}`,
        disconnectId: `disconnect-${connection.name}`,
        deleteId: `delete-${connection.name}`
      };
    });
  }

  find(name) {
    return (this.page.connections || []).find((connection) => connection.name === name);
  }

  handleNew() {
    this.clearMessages();
    this.formConnection = undefined;
    this.formMode = 'create';
  }

  handleReplace(event) {
    this.clearMessages();
    this.formConnection = this.find(event.target.dataset.name);
    this.formMode = 'replace';
  }

  handleCancel() {
    this.formMode = undefined;
  }

  handleSaved(event) {
    this.formMode = undefined;
    this.show(event.detail.result);
  }

  handleFailed(event) {
    this.error = event.detail.message;
  }

  handleCheck(event) {
    const name = event.target.dataset.name;
    return this.run(() => checkConnection({ name }));
  }

  async handleDisconnect(event) {
    const connection = this.find(event.target.dataset.name);
    if (await this.confirm('Disconnect', connection)) {
      await this.run(() => disconnect({ name: connection.name }));
    }
  }

  async handleDelete(event) {
    const connection = this.find(event.target.dataset.name);
    if (await this.confirm('Delete', connection)) {
      await this.run(() => deleteConnection({ name: connection.name }));
    }
  }

  /** Asks before Disconnect or Delete; `action` is the key suffix of its texts. */
  confirm(action, connection) {
    const keys = {
      Disconnect: [
        'Connector_Confirm_DisconnectTitle',
        'Connector_Confirm_Disconnect',
        'Connector_Page_Disconnect'
      ],
      Delete: ['Connector_Confirm_DeleteTitle', 'Connector_Confirm_Delete', 'Connector_Page_Delete']
    }[action];
    return BarnConfirmModal.open({
      size: 'small',
      label: text(keys[0], connection.label),
      message: text(keys[1], connection.label),
      confirmLabel: text(keys[2]),
      confirmVariant: 'destructive',
      cancelLabel: text('Connector_Form_Cancel')
    });
  }

  async run(call) {
    this.clearMessages();
    this.working = true;
    try {
      this.show(await call());
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  show(result) {
    if (result && result.page) {
      this.page = result.page;
    }
    const outcome = outcomeOf(result);
    this.message = text(outcome.key, outcome.status);
    this.messageVariant = outcome.variant;
  }

  clearMessages() {
    this.message = undefined;
    this.error = undefined;
  }

  messageOf(failure) {
    return (failure && failure.body && failure.body.message) || text('Connector_Error_Unexpected');
  }
}
