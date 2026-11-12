import { LightningElement, api } from 'lwc';
import getPanel from '@salesforce/apex/CertificationController.panel';
import grant from '@salesforce/apex/CertificationController.grant';
import renew from '@salesforce/apex/CertificationController.renew';
import revoke from '@salesforce/apex/CertificationController.revoke';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

const PACKAGE = 'Memberships';

/**
 * The certification panel on a member certification (G-22e, canonical model R-MEM10 to
 * R-MEM11): the credits toward renewal, and Grant, Renew and Revoke. Renew is shown only when
 * the server says it is allowed; otherwise its reason is shown. The rules live in
 * `CertificationService`; this only asks.
 */
export default class CertificationActions extends LightningElement {
  @api recordId;

  helpReady = isHelpLoaded(PACKAGE);
  icon = iconFor('Member_Certification__c');
  panel;
  working = false;
  error;
  notice;

  labels = {
    get title() {
      return helpText('Memberships', 'Memberships_Cert_Title');
    },
    get grant() {
      return helpText('Memberships', 'Memberships_Cert_Grant');
    },
    get renew() {
      return helpText('Memberships', 'Memberships_Cert_Renew');
    },
    get revoke() {
      return helpText('Memberships', 'Memberships_Cert_Revoke');
    }
  };

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp(PACKAGE).then(() => {
        this.helpReady = true;
      });
    }
    this.run(() => getPanel({ holdingId: this.recordId }));
  }

  get loaded() {
    return Boolean(this.panel);
  }

  get creditsText() {
    return helpText('Memberships', 'Memberships_Cert_Credits')
      .replace('{0}', String(this.panel.openCredits || 0))
      .replace('{1}', String(this.panel.creditsRequired || 0));
  }

  get expiresText() {
    return this.panel.expiresOn
      ? helpText('Memberships', 'Memberships_Cert_Expires').replace('{0}', this.panel.expiresOn)
      : '';
  }

  get canRenew() {
    return this.panel.canEdit && !this.panel.renewRefusal;
  }

  get renewHint() {
    return this.panel.canEdit ? this.panel.renewRefusal : undefined;
  }

  handleGrant() {
    return this.act(() => grant({ holdingId: this.recordId }));
  }

  handleRenew() {
    return this.act(() => renew({ holdingId: this.recordId }));
  }

  handleRevoke() {
    return this.act(() => revoke({ holdingId: this.recordId }));
  }

  async act(call) {
    if (await this.run(call)) {
      this.notice = helpText('Memberships', 'Memberships_Cert_Done');
      // The record page shows the new status and dates once it reads the record again.
      this.dispatchEvent(new CustomEvent('refreshview', { bubbles: true, composed: true }));
    }
  }

  async run(call) {
    this.error = undefined;
    this.notice = undefined;
    this.working = true;
    try {
      this.panel = await call();
      return true;
    } catch (failure) {
      this.error =
        (failure && failure.body && failure.body.message) ||
        helpText('Memberships', 'Memberships_Panel_Failed');
      return false;
    } finally {
      this.working = false;
    }
  }
}
