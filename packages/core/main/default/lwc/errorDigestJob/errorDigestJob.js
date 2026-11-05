import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
// Bare, and correctly so: a custom permission defined in the same package resolves without a
// namespace prefix.
import canManageSettings from '@salesforce/customPermission/Manage_BarnCRM_Settings';
import getDigest from '@salesforce/apex/ErrorDigestController.getDigest';
import setSchedule from '@salesforce/apex/ErrorDigestController.setSchedule';
import sendNow from '@salesforce/apex/ErrorDigestController.sendNow';

import TITLE from '@salesforce/label/c.Core_ErrorDigest_PageTitle';
import LAST_RUN_TITLE from '@salesforce/label/c.Core_ErrorDigest_LastRunTitle';
import NEVER_RUN from '@salesforce/label/c.Core_ErrorDigest_NeverRun';
import SCHEDULE_BUTTON from '@salesforce/label/c.Core_ErrorDigest_ScheduleButton';
import STOP_BUTTON from '@salesforce/label/c.Core_ErrorDigest_StopButton';
import SEND_NOW from '@salesforce/label/c.Core_ErrorDigest_SendNow';
import RECIPIENTS_TITLE from '@salesforce/label/c.Core_ErrorDigest_RecipientsTitle';
import TO_ADMINISTRATORS from '@salesforce/label/c.Core_ErrorDigest_ToAdministrators';
import { bodyMessage } from 'c/findCsv';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

/**
 * The error digest panel on the Error Log page of the BarnCRM Settings console (C-23).
 *
 * A job that sends email has to say, before anybody trusts it, whether it is on, when it runs,
 * what it did last time and who it goes to. This panel says all four and carries the buttons
 * that start it, stop it and send one now. Recipients and frequency are ordinary settings on the
 * same page, so they are saved and audited like every other setting.
 */
export default class ErrorDigestJob extends LightningElement {
  helpReady = isHelpLoaded('Core');

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
  }

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Core', 'Core_ErrorDigest_PageIntro');
    },
    lastRunTitle: LAST_RUN_TITLE,
    neverRun: NEVER_RUN,
    sendNow: SEND_NOW,
    recipientsTitle: RECIPIENTS_TITLE,
    get readOnly() {
      return helpText('Core', 'Core_ErrorDigest_ReadOnly');
    }
  };

  digest;
  errorMessage;
  busy = false;
  wiredDigestResult;

  @wire(getDigest)
  wiredDigest(result) {
    this.wiredDigestResult = result;
    if (result.data) {
      this.digest = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = bodyMessage(
        result.error,
        helpText('Core', 'Core_ErrorDigest_UnexpectedError')
      );
    }
  }

  get isScheduled() {
    return !!(this.digest && this.digest.scheduled);
  }

  get nextRunAt() {
    return this.digest ? this.digest.nextRunAt : undefined;
  }

  get lastRun() {
    return this.digest ? this.digest.lastRun : undefined;
  }

  get lastRunSummary() {
    return this.digest ? this.digest.lastRunSummary : undefined;
  }

  get scheduleMessage() {
    return this.isScheduled
      ? helpText('Core', 'Core_ErrorDigest_ScheduleActive')
      : helpText('Core', 'Core_ErrorDigest_NotScheduled');
  }

  get scheduleButtonLabel() {
    return this.isScheduled ? STOP_BUTTON : SCHEDULE_BUTTON;
  }

  /** "everyone with the permission: Maria Lopez, David Chen", or the listed people by name. */
  get recipientsText() {
    const names = this.digest && this.digest.recipients ? this.digest.recipients : [];
    if (names.length === 0) {
      return helpText('Core', 'Core_ErrorDigest_NoRecipients');
    }
    const list = names.join(', ');
    return this.digest.toAdministrators ? `${TO_ADMINISTRATORS} ${list}` : list;
  }

  /**
   * Read from the platform rather than the payload, so the buttons are disabled before the first
   * round trip ends. The controller checks it again, which is where the real gate is.
   */
  get canManage() {
    return canManageSettings === true;
  }

  get controlsDisabled() {
    return this.busy || !this.canManage;
  }

  get showReadOnlyNote() {
    return !this.canManage;
  }

  handleSchedule() {
    this.runAction(setSchedule({ scheduled: !this.isScheduled }));
  }

  handleSendNow() {
    this.runAction(sendNow());
  }

  async runAction(promise) {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      this.digest = await promise;
      if (this.wiredDigestResult) {
        await refreshApex(this.wiredDigestResult);
      }
    } catch (error) {
      this.errorMessage = bodyMessage(error, helpText('Core', 'Core_ErrorDigest_UnexpectedError'));
    } finally {
      this.busy = false;
    }
  }
}
