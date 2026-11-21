import { LightningElement, api } from 'lwc';
import getWebhook from '@salesforce/apex/ConnectorWebhooksController.getWebhook';
import newWebhookToken from '@salesforce/apex/ConnectorWebhooksController.newWebhookToken';
import saveWebhookCap from '@salesforce/apex/ConnectorWebhooksController.saveWebhookCap';
import BarnConfirmModal from 'c/barnConfirmModal';
import { helpText } from 'c/barnHelpText';
import { DEFAULT_REPLY } from 'c/connectorRecipeRules';

const HEADER = 'X-BarnCRM-Token';

/**
 * The Webhook card of a recipe whose When is Another App Sends Data (CN-04; canonical model
 * R-CR10; design Sections 3.3 and 3.3a). Shows the receiver address on each active Site and the
 * header to send the token in, makes a new token (shown this once, behind a confirmation when one
 * exists), saves Webhook Hourly Cap, and edits the trigger's Event Id and reply, which it hands to
 * the editor as `triggerchange`. The token never leaves this card's memory.
 */
export default class ConnectorWebhookSetup extends LightningElement {
  @api canManage = false;
  @api trigger = {};

  _recipeId;
  view;
  token;
  hourlyCap = 500;
  working = false;
  message;
  error;

  @api
  get recipeId() {
    return this._recipeId;
  }

  set recipeId(value) {
    const changed = value !== this._recipeId;
    this._recipeId = value;
    if (changed) {
      this.token = undefined;
      this.load();
    }
  }

  labels = {
    get heading() {
      return helpText('Connector', 'Connector_Webhook_Heading');
    },
    get intro() {
      return helpText('Connector', 'Connector_Webhook_Intro');
    },
    get saveFirst() {
      return helpText('Connector', 'Connector_Webhook_SaveFirst');
    },
    get noSite() {
      return helpText('Connector', 'Connector_Webhook_NoSite');
    },
    get address() {
      return helpText('Connector', 'Connector_Webhook_Address');
    },
    get header() {
      return helpText('Connector', 'Connector_Webhook_Header');
    },
    get addressWithToken() {
      return helpText('Connector', 'Connector_Webhook_AddressWithToken');
    },
    get hasToken() {
      return helpText('Connector', 'Connector_Webhook_HasToken');
    },
    get noToken() {
      return helpText('Connector', 'Connector_Webhook_NoToken');
    },
    get newToken() {
      return helpText('Connector', 'Connector_Webhook_NewToken');
    },
    get confirmTitle() {
      return helpText('Connector', 'Connector_Webhook_ConfirmTitle');
    },
    get confirmBody() {
      return helpText('Connector', 'Connector_Webhook_ConfirmBody');
    },
    get tokenShown() {
      return helpText('Connector', 'Connector_Webhook_TokenShown');
    },
    get token() {
      return helpText('Connector', 'Connector_Webhook_Token');
    },
    get eventId() {
      return helpText('Connector', 'Connector_Webhook_EventId');
    },
    get eventIdHelp() {
      return helpText('Connector', 'Connector_Webhook_EventIdHelp');
    },
    get replyStatus() {
      return helpText('Connector', 'Connector_Webhook_ReplyStatus');
    },
    get replyBody() {
      return helpText('Connector', 'Connector_Webhook_ReplyBody');
    },
    get replyBodyHelp() {
      return helpText('Connector', 'Connector_Webhook_ReplyBodyHelp');
    },
    get challenge() {
      return helpText('Connector', 'Connector_Webhook_Challenge');
    },
    get challengeHelp() {
      return helpText('Connector', 'Connector_Webhook_ChallengeHelp');
    },
    get hourlyCap() {
      return helpText('Connector', 'Connector_Webhook_HourlyCap');
    },
    get hourlyCapHelp() {
      return helpText('Connector', 'Connector_Webhook_HourlyCapHelp');
    },
    get saveCap() {
      return helpText('Connector', 'Connector_Webhook_SaveCap');
    },
    get capSaved() {
      return helpText('Connector', 'Connector_Webhook_CapSaved');
    },
    get fetchBack() {
      return helpText('Connector', 'Connector_Webhook_FetchBack');
    },
    get working() {
      return helpText('Connector', 'Connector_Webhook_Working');
    },
    get cancel() {
      return helpText('Connector', 'Connector_Editor_Close');
    },
    get unexpected() {
      return helpText('Connector', 'Connector_Error_Unexpected');
    }
  };

  get readOnly() {
    return !this.canManage;
  }

  get saved() {
    return Boolean(this._recipeId);
  }

  get headerName() {
    return HEADER;
  }

  get addresses() {
    const shown = this.token || '<token>';
    return ((this.view && this.view.addresses) || []).map((address) => ({
      key: address,
      address,
      withToken: `${address}?token=${shown}`
    }));
  }

  get noSite() {
    return Boolean(this.view) && !this.addresses.length;
  }

  get tokenText() {
    if (this.token) {
      return '';
    }
    return this.view && this.view.hasToken ? this.labels.hasToken : this.labels.noToken;
  }

  get reply() {
    return (this.trigger && this.trigger.reply) || {};
  }

  get replyBody() {
    return this.reply.body === undefined ? DEFAULT_REPLY : this.reply.body;
  }

  get replyStatus() {
    return String(this.reply.status || 202);
  }

  get statusOptions() {
    return [
      { label: '202', value: '202' },
      { label: '200', value: '200' }
    ];
  }

  async load() {
    this.view = undefined;
    if (!this._recipeId) {
      return;
    }
    await this.work(async () => {
      this.view = await getWebhook({ recipeId: this._recipeId });
      this.hourlyCap = this.view.hourlyCap;
    });
  }

  async handleNewToken() {
    if (this.view && this.view.hasToken) {
      const confirmed = await BarnConfirmModal.open({
        size: 'small',
        label: this.labels.confirmTitle,
        message: this.labels.confirmBody,
        confirmLabel: this.labels.newToken,
        confirmVariant: 'destructive',
        cancelLabel: this.labels.cancel
      });
      if (!confirmed) {
        return;
      }
    }
    await this.work(async () => {
      const made = await newWebhookToken({ recipeId: this._recipeId });
      this.token = made.token;
      this.view = { ...made, token: undefined };
      this.message = this.labels.tokenShown;
    });
  }

  handleCap(event) {
    this.hourlyCap = event.detail.value;
  }

  async handleSaveCap() {
    await this.work(async () => {
      this.view = await saveWebhookCap({
        recipeId: this._recipeId,
        hourlyCap: Number(this.hourlyCap)
      });
      this.hourlyCap = this.view.hourlyCap;
      this.message = this.labels.capSaved;
    });
  }

  handleEventId(event) {
    this.changeTrigger({ eventId: event.detail.value });
  }

  /** A reply field: data-field names it; the status is a number. */
  handleReply(event) {
    const field = event.target.dataset.field;
    const value = field === 'status' ? Number(event.detail.value) : event.detail.value;
    this.changeTrigger({ reply: { ...this.reply, [field]: value } });
  }

  changeTrigger(changes) {
    this.dispatchEvent(new CustomEvent('triggerchange', { detail: changes }));
  }

  async work(call) {
    this.message = undefined;
    this.error = undefined;
    this.working = true;
    try {
      await call();
    } catch (failure) {
      this.error = (failure && failure.body && failure.body.message) || this.labels.unexpected;
    } finally {
      this.working = false;
    }
  }
}
