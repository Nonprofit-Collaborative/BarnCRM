import { LightningElement } from 'lwc';
import getSetup from '@salesforce/apex/AddressVerificationController.getSetup';
import checkConnection from '@salesforce/apex/AddressVerificationController.checkConnection';
import clearKeys from '@salesforce/apex/AddressVerificationController.clearKeys';
import verifyWaiting from '@salesforce/apex/AddressVerificationController.verifyWaiting';
import BarnConfirmModal from 'c/barnConfirmModal';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/** Fills `{0}`, `{1}` ... in a help text, in order. */
function fill(text, values) {
  return values.reduce((result, value, index) => result.replace(`{${index}}`, value), text);
}

/**
 * The Address Verification Setup page (C-46, N-13). The controller returns the provider in use,
 * where each provider's key goes in Setup (External Credential and principal names, never a
 * value) and whether each is connected; the page checks a connection, forgets one, and starts the
 * check of waiting addresses. No key passes through it.
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
    get check() {
      return helpText('AddressVerification', 'AddressVerification_Setup_CheckConnection');
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
    }
  };

  icons = { page: iconFor('Address_Verification_Setup') };

  setup;
  working = false;
  message;
  messageVariant = 'success';
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
    return fill(helpText('AddressVerification', 'AddressVerification_Setup_Provider'), [
      this.setup.provider
    ]);
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

  /** Each provider's connection, with the Setup steps filled with this org's names. */
  get credentials() {
    return (this.setup.credentials || []).map((credential) => {
      const id = credential.provider.toLowerCase();
      return {
        ...credential,
        dataId: id,
        statusId: `status-${id}`,
        stepsId: `steps-${id}`,
        checkId: `check-${id}`,
        clearId: `clear-${id}`,
        heading:
          credential.provider === 'Google'
            ? helpText('AddressVerification', 'AddressVerification_Setup_GoogleHeading')
            : helpText('AddressVerification', 'AddressVerification_Setup_SmartyHeading'),
        status: credential.connected
          ? helpText('AddressVerification', 'AddressVerification_Setup_StatusConnected')
          : helpText('AddressVerification', 'AddressVerification_Setup_StatusNotConnected'),
        steps: fill(helpText('AddressVerification', 'AddressVerification_Setup_CredentialSteps'), [
          credential.externalCredential,
          credential.principal,
          credential.parameters
        ])
      };
    });
  }

  /** Checks the connection, then reloads the page so its status shows what was found. */
  handleCheck(event) {
    const provider = event.target.dataset.provider;
    return this.run(async () => {
      const said = await checkConnection({ provider });
      this.setup = await getSetup();
      const connected = (this.setup.credentials || []).some(
        (credential) => credential.provider === provider && credential.connected
      );
      this.messageVariant = connected ? 'success' : 'warning';
      return said;
    });
  }

  /** Disconnecting stops verification with the provider, so it asks first. */
  async handleClear(event) {
    const provider = event.target.dataset.provider;
    const confirmed = await BarnConfirmModal.open({
      size: 'small',
      label: fill(helpText('AddressVerification', 'AddressVerification_Setup_DisconnectTitle'), [
        provider
      ]),
      message: fill(
        helpText('AddressVerification', 'AddressVerification_Setup_DisconnectConfirm'),
        [provider]
      ),
      confirmLabel: this.labels.clear,
      confirmVariant: 'destructive',
      cancelLabel: helpText('AddressVerification', 'AddressVerification_Setup_Cancel')
    });
    if (!confirmed) {
      return undefined;
    }
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
    this.messageVariant = 'success';
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
