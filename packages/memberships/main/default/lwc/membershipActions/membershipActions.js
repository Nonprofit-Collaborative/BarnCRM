import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPanel from '@salesforce/apex/MembershipController.panel';
import renewTerm from '@salesforce/apex/MembershipController.renew';
import emailPaymentLink from '@salesforce/apex/MembershipController.emailPaymentLink';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

const PACKAGE = 'Memberships';

/**
 * The membership panel (G-22b, PAY-02; ADR-0206 `0206-memberships-module.md`, decision 11):
 * Renew at a chosen level, and Email Payment Link when Payments is ready and the member has an
 * email. The rules live in `MembershipService` and `MembershipPayments`; this only asks.
 */
export default class MembershipActions extends NavigationMixin(LightningElement) {
  @api recordId;

  helpReady = isHelpLoaded(PACKAGE);
  icon = iconFor('Membership_Term__c');
  panel;
  levelId;
  working = false;
  error;
  notice;

  labels = {
    get title() {
      return helpText('Memberships', 'Memberships_Panel_Title');
    },
    get level() {
      return helpText('Memberships', 'Memberships_Panel_Level');
    },
    get renew() {
      return helpText('Memberships', 'Memberships_Panel_Renew');
    },
    get emailLink() {
      return helpText('Memberships', 'Memberships_Panel_EmailLink');
    },
    get cannotRenew() {
      return helpText('Memberships', 'Memberships_Panel_CannotRenew');
    },
    get paymentsOff() {
      return helpText('Memberships', 'Memberships_Panel_PaymentsOff');
    },
    get noEmail() {
      return helpText('Memberships', 'Memberships_Panel_NoEmail');
    }
  };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(PACKAGE).then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.error = undefined;
    try {
      this.panel = await getPanel({ termId: this.recordId });
      this.levelId = this.panel.levelId;
    } catch (failure) {
      this.error = this.messageOf(failure);
    }
  }

  get loaded() {
    return Boolean(this.panel);
  }

  get levelOptions() {
    return (this.panel.levels || []).map((level) => ({
      value: level.value,
      label: level.label
    }));
  }

  get renewLocked() {
    return this.working || !this.panel.canRenew || !this.levelId;
  }

  get linkShown() {
    return this.panel.paymentsReady && this.panel.hasEmail;
  }

  get linkHint() {
    if (!this.panel.paymentsReady) {
      return this.labels.paymentsOff;
    }
    return this.panel.hasEmail ? undefined : this.labels.noEmail;
  }

  handleLevel(event) {
    this.levelId = event.detail.value;
  }

  async handleRenew() {
    const made = await this.run(() => renewTerm({ termId: this.recordId, levelId: this.levelId }));
    if (made) {
      this[NavigationMixin.Navigate]({
        type: 'standard__recordPage',
        attributes: { recordId: made, actionName: 'view' }
      });
    }
  }

  async handleEmailLink() {
    const sent = await this.run(() => emailPaymentLink({ termId: this.recordId }).then(() => true));
    if (sent) {
      this.notice = helpText('Memberships', 'Memberships_Panel_LinkQueued');
    }
  }

  async run(call) {
    this.error = undefined;
    this.notice = undefined;
    this.working = true;
    try {
      return await call();
    } catch (failure) {
      this.error = this.messageOf(failure);
      return undefined;
    } finally {
      this.working = false;
    }
  }

  messageOf(failure) {
    return (
      (failure && failure.body && failure.body.message) ||
      helpText('Memberships', 'Memberships_Panel_Failed')
    );
  }
}
