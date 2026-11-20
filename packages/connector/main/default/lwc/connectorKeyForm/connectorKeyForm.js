import { LightningElement, api } from 'lwc';
import createConnection from '@salesforce/apex/ConnectorConnectionsController.createConnection';
import replaceKey from '@salesforce/apex/ConnectorConnectionsController.replaceKey';
import { KINDS, API_KEY, BASIC, SECRET_URL, formProblems } from 'c/connectorRules';
import { say as text } from 'c/connectorText';
import { lockedUrl, partOfKey } from 'c/connectorFileRules';

/**
 * New Connection and Replace Key on Super Connector (CN-01). This form alone calls the two Apex
 * methods that take a key, so the key never leaves it: it is read from the password box at the
 * moment of sending, never kept in a field, a store, the URL or an event, and the box is emptied
 * after every call, success or failure (security review F10). `saved` carries the outcome and
 * the refreshed list, never the key.
 */
export default class ConnectorKeyForm extends LightningElement {
  /** `create` or `replace`. */
  @api mode = 'create';
  /** For Replace Key: the connection's name, label and auth kind (no key). */
  @api connection;

  /**
   * A template's connection (CN-08, R-CR12): label, auth kind, header name and base URL, never a
   * key. Its host is locked: only the URL parts the template names are typed, each checked
   * against the template's pattern (F4).
   */
  @api
  get prefill() {
    return this._prefill;
  }
  set prefill(value) {
    this._prefill = value;
    this.urlValues = {};
    if (value) {
      this.label = value.label || '';
      this.authKind = value.authKind || this.authKind;
      this.baseUrl = value.baseUrl || '';
      this.headerName = value.headerName || '';
    }
  }

  _prefill;
  urlValues = {};
  label = '';
  authKind = 'BearerToken';
  baseUrl = '';
  headerName = '';
  userName = '';
  problems = [];
  working = false;

  labels = {
    get name() {
      return text('Connector_Form_Name');
    },
    get kind() {
      return text('Connector_Form_Kind');
    },
    get baseUrl() {
      return text('Connector_Form_BaseUrl');
    },
    get baseUrlHelp() {
      return text('Connector_Form_BaseUrlHelp');
    },
    get headerName() {
      return text('Connector_Form_HeaderName');
    },
    get userName() {
      return text('Connector_Form_UserName');
    },
    get cancel() {
      return text('Connector_Form_Cancel');
    },
    get secretUrlNotice() {
      return text('Connector_Form_SecretUrlNotice');
    },
    get debugNotice() {
      return text('Connector_Form_DebugNotice');
    }
  };

  get creating() {
    return this.mode !== 'replace';
  }

  get kind() {
    return this.creating ? this.authKind : this.connection && this.connection.authKind;
  }

  get heading() {
    return this.creating
      ? text('Connector_Form_NewTitle')
      : text('Connector_Form_ReplaceTitle', this.connection ? this.connection.label : '');
  }

  get kindOptions() {
    return KINDS.map((entry) => ({ value: entry.value, label: text(entry.key) }));
  }

  get isSecretUrl() {
    return this.kind === SECRET_URL;
  }

  get showBaseUrl() {
    return this.creating && !this.isSecretUrl;
  }

  get showHeaderName() {
    return this.creating && this.kind === API_KEY;
  }

  get showUserName() {
    return this.kind === BASIC;
  }

  get secretLabel() {
    return this.isSecretUrl ? text('Connector_Form_SecretUrl') : text('Connector_Form_Key');
  }

  get saveLabel() {
    return this.creating ? text('Connector_Form_Create') : text('Connector_Form_Replace');
  }

  get problemText() {
    return this.problems.map((key) => text(key)).join(' ');
  }

  handleField(event) {
    this[event.target.dataset.field] = event.detail.value;
  }

  /** True when a template set the address: the host is fixed, only its parts are typed. */
  get locked() {
    return this.creating && Boolean(this._prefill && this._prefill.baseUrl);
  }

  get urlParamRows() {
    return ((this._prefill && this._prefill.urlParams) || []).map((param) => ({
      ...param,
      key: `url-${param.name}`,
      value: this.urlValues[param.name] || '',
      help: param.fromParam ? text('Connector_Form_UrlPartFromKey', param.help || '') : param.help
    }));
  }

  handleUrlPart(event) {
    this.urlValues = { ...this.urlValues, [event.target.dataset.name]: event.detail.value };
  }

  /**
   * The template's address with its parts filled, or null. A part the template reads from the
   * key (Mailchimp's data center) is taken from the key box at this moment when left blank, and
   * is never kept (F10).
   */
  lockedBaseUrl(box) {
    const params = (this._prefill && this._prefill.urlParams) || [];
    const values = { ...this.urlValues };
    params.forEach((param) => {
      if (!values[param.name] && param.fromParam && param.after) {
        values[param.name] = partOfKey(box && box.value, param.after);
      }
    });
    return lockedUrl(this._prefill.baseUrl, params, values);
  }

  get secretBox() {
    return this.template.querySelector('[data-id="secret"]');
  }

  async handleSave() {
    const box = this.secretBox;
    const baseUrl = this.locked ? this.lockedBaseUrl(box) : this.baseUrl;
    this.problems = formProblems(
      {
        label: this.label,
        authKind: this.kind,
        baseUrl: baseUrl || '',
        headerName: this.headerName,
        userName: this.userName,
        hasSecret: Boolean(box && box.value)
      },
      !this.creating
    );
    if (this.locked && !baseUrl) {
      this.problems = [...this.problems, 'Connector_Form_ErrorLockedUrl'];
    }
    if (this.problems.length) {
      return;
    }
    this.working = true;
    try {
      const result = this.creating
        ? await createConnection({
            label: this.label,
            authKind: this.authKind,
            baseUrl,
            headerName: this.headerName,
            userName: this.userName,
            secret: box.value
          })
        : await replaceKey({
            name: this.connection.name,
            userName: this.userName,
            secret: box.value
          });
      this.dispatchEvent(new CustomEvent('saved', { detail: { result } }));
    } catch (failure) {
      this.problems = [];
      this.dispatchEvent(
        new CustomEvent('failed', {
          detail: {
            message:
              (failure && failure.body && failure.body.message) ||
              text('Connector_Error_Unexpected')
          }
        })
      );
    } finally {
      box.value = '';
      this.working = false;
    }
  }

  handleCancel() {
    const box = this.secretBox;
    if (box) {
      box.value = '';
    }
    this.dispatchEvent(new CustomEvent('cancel'));
  }
}
