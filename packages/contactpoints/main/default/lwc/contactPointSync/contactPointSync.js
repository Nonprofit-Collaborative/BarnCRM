import { LightningElement } from 'lwc';
import getStatus from '@salesforce/apex/ContactPointSyncController.getStatus';
import runBackfill from '@salesforce/apex/ContactPointSyncController.runBackfill';
import title from '@salesforce/label/c.ContactPoints_Page_Title';
import runBackfillLabel from '@salesforce/label/c.ContactPoints_Page_RunBackfill';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';
import { iconFor } from 'c/barnIcons';

/**
 * The Contact Point Sync page (C-45). The controller decides what the org and the person allow
 * and writes every message; the page shows them, the preview count, the last backfill and the
 * one button.
 */
export default class ContactPointSync extends LightningElement {
  helpReady = isHelpLoaded('ContactPoints');

  labels = {
    title,
    runBackfill: runBackfillLabel,
    get intro() {
      return helpText('ContactPoints', 'ContactPoints_Page_Intro');
    },
    get noManage() {
      return helpText('ContactPoints', 'ContactPoints_Page_NoManagePermission');
    },
    get running() {
      return helpText('ContactPoints', 'ContactPoints_Page_Running');
    }
  };

  icons = { page: iconFor('Contact_Point_Sync') };

  status;
  working = false;
  error;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('ContactPoints').then(() => {
        this.helpReady = true;
      });
    }
    this.load();
  }

  async load() {
    this.error = undefined;
    try {
      this.status = await getStatus();
    } catch (failure) {
      this.error = this.messageOf(failure);
    }
  }

  get loaded() {
    return Boolean(this.status);
  }

  /** The first status read, or a backfill starting; never over an error. */
  get loading() {
    return !this.error && (!this.loaded || this.working);
  }

  get kinds() {
    return (this.status.kinds || []).map((line) => ({
      ...line,
      variant: line.ready ? 'success' : 'warning'
    }));
  }

  get countsText() {
    const people = `${this.status.peopleCount}${this.status.peopleCountCapped ? '+' : ''}`;
    return helpText('ContactPoints', 'ContactPoints_Page_Counts')
      .replace('{0}', people)
      .replace('{1}', this.status.managedCount);
  }

  get lastText() {
    if (!this.status.lastBackfill) {
      return undefined;
    }
    const when = new Date(this.status.lastBackfill).toLocaleString();
    return helpText('ContactPoints', 'ContactPoints_Page_LastBackfill')
      .replace('{0}', when)
      .replace('{1}', this.status.lastSummary || '');
  }

  get noManageShown() {
    return this.loaded && !this.status.canRun;
  }

  get runningShown() {
    return this.loaded && this.status.running;
  }

  get runDisabled() {
    return (
      this.working ||
      !this.loaded ||
      !this.status.canRun ||
      !this.status.anyReady ||
      this.status.running
    );
  }

  async handleRun() {
    this.error = undefined;
    this.working = true;
    try {
      this.status = await runBackfill();
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  messageOf(failure) {
    return (
      (failure && failure.body && failure.body.message) ||
      helpText('ContactPoints', 'ContactPoints_Page_Failed')
    );
  }
}
