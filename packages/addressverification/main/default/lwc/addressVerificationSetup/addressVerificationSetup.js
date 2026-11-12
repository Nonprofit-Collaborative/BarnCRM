import { LightningElement } from 'lwc';
import getSetup from '@salesforce/apex/AddressVerificationController.getSetup';
import saveKeys from '@salesforce/apex/AddressVerificationController.saveKeys';
import clearKeys from '@salesforce/apex/AddressVerificationController.clearKeys';
import verifyWaiting from '@salesforce/apex/AddressVerificationController.verifyWaiting';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/** Each key's box label, read when the help text has loaded. */
function keyLabels() {
  return {
    smartyAuthId: helpText('AddressVerification', 'AddressVerification_Setup_SmartyAuthId'),
    smartyAuthToken: helpText('AddressVerification', 'AddressVerification_Setup_SmartyAuthToken'),
    googleApiKey: helpText('AddressVerification', 'AddressVerification_Setup_GoogleApiKey')
  };
}

/**
 * The Address Verification Setup page (C-46). The controller returns the provider in use and
 * whether each key is entered (last four characters only); the page takes new keys, which are
 * never shown again, clears one provider's keys and starts the check of waiting addresses.
 */
export default class AddressVerificationSetup extends LightningElement {
  helpReady = isHelpLoaded('AddressVerification');

  // No custom labels: the label budget is full (check-label-budget), so every text is help text.
  labels = {
    get title() {
      return helpText('AddressVerification', 'AddressVerification_Setup_Title');
    },
    get intro() {
      return helpText('AddressVerification', 'AddressVerification_Setup_Intro');
    },
    get saveKeys() {
      return helpText('AddressVerification', 'AddressVerification_Setup_SaveKeys');
    },
    get clear() {
      return helpText('AddressVerification', 'AddressVerification_Setup_Clear');
    },
    get verify() {
      return helpText('AddressVerification', 'AddressVerification_Setup_Verify');
    },
    get noManage() {
      return helpText('AddressVerification', 'AddressVerification_Setup_NoManage');
    },
    get saved() {
      return helpText('AddressVerification', 'AddressVerification_Setup_Saved');
    },
    get smarty() {
      return helpText('AddressVerification', 'AddressVerification_Setup_SmartyHeading');
    },
    get google() {
      return helpText('AddressVerification', 'AddressVerification_Setup_GoogleHeading');
    }
  };

  icons = { page: iconFor('Address_Verification_Setup') };

  setup;
  typed = {};
  working = false;
  message;
  error;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('AddressVerification').then(() => {
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

  get providerText() {
    return helpText('AddressVerification', 'AddressVerification_Setup_Provider').replace(
      '{0}',
      this.setup.provider
    );
  }

  get noManageShown() {
    return this.loaded && !this.setup.canManage;
  }

  get locked() {
    return this.working || !this.loaded || !this.setup.canManage;
  }

  get verifyLocked() {
    return this.locked || !this.setup.ready;
  }

  get keys() {
    const labels = keyLabels();
    return (this.setup.keys || []).map((key) => ({
      ...key,
      label: labels[key.name],
      status: key.lastFour
        ? helpText('AddressVerification', 'AddressVerification_Setup_KeySet').replace(
            '{0}',
            key.lastFour
          )
        : helpText('AddressVerification', 'AddressVerification_Setup_KeyNotSet'),
      value: this.typed[key.name] || ''
    }));
  }

  get smartyKeys() {
    return this.keys.filter((key) => key.provider === 'Smarty');
  }

  get googleKeys() {
    return this.keys.filter((key) => key.provider === 'Google');
  }

  handleType(event) {
    this.typed = { ...this.typed, [event.target.dataset.name]: event.target.value };
    this.message = undefined;
  }

  handleSave() {
    return this.run(async () => {
      this.setup = await saveKeys({ keys: this.typed });
      this.typed = {};
      return this.labels.saved;
    });
  }

  handleClear(event) {
    const provider = event.target.dataset.provider;
    return this.run(async () => {
      this.setup = await clearKeys({ provider });
      return this.labels.saved;
    });
  }

  handleVerify() {
    return this.run(() => verifyWaiting());
  }

  async run(call) {
    this.error = undefined;
    this.message = undefined;
    this.working = true;
    try {
      this.message = await call();
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  messageOf(failure) {
    return (
      (failure && failure.body && failure.body.message) ||
      helpText('AddressVerification', 'AddressVerification_Setup_Failed')
    );
  }
}
