import { LightningElement } from 'lwc';
import getSetup from '@salesforce/apex/PaymentsSetupController.getSetup';
import saveKeys from '@salesforce/apex/PaymentsSetupController.saveKeys';
import clearKeys from '@salesforce/apex/PaymentsSetupController.clearKeys';
import scheduleProcessing from '@salesforce/apex/PaymentsSetupController.scheduleProcessing';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/** Each key's box label, read when the help text has loaded. */
function keyLabels() {
  return {
    stripeSecretKey: helpText('Payments', 'Payments_Setup_StripeSecretKey'),
    stripeWebhookSecret: helpText('Payments', 'Payments_Setup_StripeWebhookSecret'),
    payPalClientId: helpText('Payments', 'Payments_Setup_PayPalClientId'),
    payPalClientSecret: helpText('Payments', 'Payments_Setup_PayPalClientSecret'),
    payPalWebhookId: helpText('Payments', 'Payments_Setup_PayPalWebhookId')
  };
}

/**
 * The Payments Setup page (PAY-01). The controller returns the receiver addresses and whether
 * each key is entered (last four characters only); the page takes new keys, which are never
 * shown again, and clears one processor's keys.
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
    }
  };

  icons = { page: iconFor('Payments_Setup') };

  setup;
  typed = {};
  working = false;
  savedShown = false;
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
    return helpText('Payments', 'Payments_Setup_Mode')
      .replace('{0}', this.setup.mode)
      .replace('{1}', this.setup.processor);
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

  get keys() {
    const labels = keyLabels();
    return (this.setup.keys || []).map((key) => ({
      ...key,
      label: labels[key.name],
      status: key.lastFour
        ? helpText('Payments', 'Payments_Setup_KeySet').replace('{0}', key.lastFour)
        : helpText('Payments', 'Payments_Setup_KeyNotSet'),
      value: this.typed[key.name] || ''
    }));
  }

  get stripeKeys() {
    return this.keys.filter((key) => key.processor === 'Stripe');
  }

  get payPalKeys() {
    return this.keys.filter((key) => key.processor === 'PayPal');
  }

  handleType(event) {
    this.typed = { ...this.typed, [event.target.dataset.name]: event.target.value };
    this.savedShown = false;
  }

  handleSave() {
    return this.run(() => saveKeys({ keys: this.typed }));
  }

  get scheduled() {
    return this.setup.scheduled === true;
  }

  /** Scheduling stays the admin's click, never automatic (D-195). */
  handleSchedule() {
    return this.run(() => scheduleProcessing());
  }

  handleClear(event) {
    return this.run(() => clearKeys({ processor: event.target.dataset.processor }));
  }

  async run(call) {
    this.error = undefined;
    this.savedShown = false;
    this.working = true;
    try {
      this.setup = await call();
      this.typed = {};
      this.savedShown = true;
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
