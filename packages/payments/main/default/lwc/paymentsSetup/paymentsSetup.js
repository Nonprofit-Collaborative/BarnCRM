import { LightningElement } from 'lwc';
import getSetup from '@salesforce/apex/PaymentsSetupController.getSetup';
import saveKeys from '@salesforce/apex/PaymentsSetupController.saveKeys';
import clearKeys from '@salesforce/apex/PaymentsSetupController.clearKeys';
import checkConnection from '@salesforce/apex/PaymentsSetupController.checkConnection';
import scheduleProcessing from '@salesforce/apex/PaymentsSetupController.scheduleProcessing';
import regenerateToken from '@salesforce/apex/PaymentsSetupController.regenerateToken';
import BarnConfirmModal from 'c/barnConfirmModal';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/** Fills `{0}`, `{1}` ... in a help text, in order. */
function fill(text, values) {
  return values.reduce((result, value, index) => result.replace(`{${index}}`, value), text);
}

/**
 * The Payments Setup page (PAY-01, N-13). The controller returns the receiver addresses, where
 * each processor's secrets go in Setup (External Credential and principal names, never a value),
 * whether each processor is connected, and the PayPal webhook id by its last four characters. The
 * page checks a connection, forgets one, and saves the webhook id; no secret passes through it.
 */
export default class PaymentsSetup extends LightningElement {
  helpReady = isHelpLoaded('Payments');

  // No custom labels: the label budget is full (check-label-budget), so every text is help text.
  labels = {
    get title() {
      return helpText('Payments', 'Payments_Setup_Title');
    },
    get saveKeys() {
      return helpText('Payments', 'Payments_Setup_SaveKeys');
    },
    get clear() {
      return helpText('Payments', 'Payments_Setup_Clear');
    },
    get check() {
      return helpText('Payments', 'Payments_Setup_CheckConnection');
    },
    get intro() {
      return helpText('Payments', 'Payments_Setup_Intro');
    },
    get addresses() {
      return helpText('Payments', 'Payments_Setup_Addresses');
    },
    get noSite() {
      return helpText('Payments', 'Payments_Setup_NoSite');
    },
    get noManage() {
      return helpText('Payments', 'Payments_Setup_NoManage');
    },
    get saved() {
      return helpText('Payments', 'Payments_Setup_Saved');
    },
    get stripeUrl() {
      return helpText('Payments', 'Payments_Setup_StripeUrl');
    },
    get payPalUrl() {
      return helpText('Payments', 'Payments_Setup_PayPalUrl');
    },
    get scheduled() {
      return helpText('Payments', 'Payments_Setup_Scheduled');
    },
    get notScheduled() {
      return helpText('Payments', 'Payments_Setup_NotScheduled');
    },
    get schedule() {
      return helpText('Payments', 'Payments_Setup_Schedule');
    },
    get regenerate() {
      return helpText('Payments', 'Payments_Setup_RegenerateToken');
    }
  };

  icons = { page: iconFor('Payments_Setup') };

  setup;
  typed = {};
  working = false;
  notice;
  error;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Payments').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.error = undefined;
    try {
      this.setup = await getSetup();
    } catch (failure) {
      this.error = this.messageOf(failure);
    }
  }

  get loaded() {
    return Boolean(this.setup);
  }

  get loading() {
    return !this.error && (!this.loaded || this.working);
  }

  get modeText() {
    return fill(helpText('Payments', 'Payments_Setup_Mode'), [
      this.setup.mode,
      this.setup.processor
    ]);
  }

  get receivers() {
    return this.setup.receivers || [];
  }

  get noSiteShown() {
    return this.loaded && this.receivers.length === 0;
  }

  get noManageShown() {
    return this.loaded && !this.setup.canManage;
  }

  get locked() {
    return this.working || !this.loaded || !this.setup.canManage;
  }

  /** Each processor's connection, with the Setup steps filled with this org's names. */
  get credentials() {
    return (this.setup.credentials || []).map((credential) => {
      const id = credential.processor.toLowerCase();
      return {
        ...credential,
        dataId: id,
        statusId: `status-${id}`,
        stepsId: `steps-${id}`,
        checkId: `check-${id}`,
        clearId: `clear-${id}`,
        isPayPal: credential.processor === 'PayPal',
        // Disconnect has something to forget only when connected, or for PayPal a stored webhook id.
        canClear:
          credential.connected || (credential.processor === 'PayPal' && this.payPalWebhookSet),
        status: credential.connected
          ? helpText('Payments', 'Payments_Setup_StatusConnected')
          : helpText('Payments', 'Payments_Setup_StatusNotConnected'),
        steps: fill(helpText('Payments', 'Payments_Setup_CredentialSteps'), [
          credential.externalCredential,
          credential.principal,
          credential.parameters,
          credential.namedCredentials
        ])
      };
    });
  }

  /** Whether a PayPal webhook id is stored. */
  get payPalWebhookSet() {
    return (this.setup.keys || []).some((key) => key.processor === 'PayPal' && key.lastFour);
  }

  /** The PayPal webhook id: not a secret, but shown by its last four characters only. */
  get payPalKeys() {
    return (this.setup.keys || [])
      .filter((key) => key.processor === 'PayPal')
      .map((key) => ({
        ...key,
        label: helpText('Payments', 'Payments_Setup_PayPalWebhookId'),
        status: key.lastFour
          ? fill(helpText('Payments', 'Payments_Setup_KeySet'), [key.lastFour])
          : helpText('Payments', 'Payments_Setup_KeyNotSet'),
        value: this.typed[key.name] || ''
      }));
  }

  get scheduled() {
    return this.setup.scheduled === true;
  }

  handleType(event) {
    this.typed = { ...this.typed, [event.target.dataset.name]: event.target.value };
    this.notice = undefined;
  }

  handleSave() {
    return this.run(() => saveKeys({ keys: this.typed }));
  }

  /** Scheduling stays the admin's click, never automatic (D-195). */
  handleSchedule() {
    return this.run(() => scheduleProcessing());
  }

  /** Replacing the token breaks the addresses already given, so it asks first. */
  async handleRegenerate() {
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: helpText('Payments', 'Payments_Setup_RegenerateTitle'),
      message: helpText('Payments', 'Payments_Setup_RegenerateConfirm'),
      confirmLabel: this.labels.regenerate,
      confirmVariant: 'destructive',
      cancelLabel: helpText('Payments', 'Payments_Setup_Cancel')
    });
    if (!confirmed) {
      return undefined;
    }
    return this.run(() => regenerateToken());
  }

  /** Disconnecting stops use of the processor (PayPal also loses its saved Webhook ID), so it asks first. */
  async handleClear(event) {
    const processor = event.target.dataset.processor;
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: fill(helpText('Payments', 'Payments_Setup_DisconnectTitle'), [processor]),
      message: fill(
        helpText(
          'Payments',
          processor === 'PayPal'
            ? 'Payments_Setup_DisconnectConfirmPayPal'
            : 'Payments_Setup_DisconnectConfirm'
        ),
        [processor]
      ),
      confirmLabel: this.labels.clear,
      confirmVariant: 'destructive',
      cancelLabel: helpText('Payments', 'Payments_Setup_Cancel')
    });
    if (!confirmed) {
      return undefined;
    }
    return this.run(() => clearKeys({ processor }));
  }

  handleCheck(event) {
    return this.run(() => checkConnection({ processor: event.target.dataset.processor }));
  }

  async run(call) {
    this.error = undefined;
    this.notice = undefined;
    this.working = true;
    try {
      const setup = await call();
      this.setup = setup;
      this.typed = {};
      this.notice = setup.checkMessage
        ? { variant: setup.checkOk ? 'success' : 'warning', message: setup.checkMessage }
        : { variant: 'success', message: this.labels.saved };
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  messageOf(failure) {
    return (
      (failure && failure.body && failure.body.message) ||
      helpText('Payments', 'Payments_Setup_Failed')
    );
  }
}
