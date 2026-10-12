import { LightningElement } from 'lwc';
import getStatus from '@salesforce/apex/CampaignSyncController.getStatus';
import syncAll from '@salesforce/apex/CampaignSyncController.syncAll';
import title from '@salesforce/label/c.Connect_CampaignSync_Title';
import intro from '@salesforce/label/c.Connect_CampaignSync_Intro';
import unavailable from '@salesforce/label/c.Connect_CampaignSync_Unavailable';
import switchedOff from '@salesforce/label/c.Connect_CampaignSync_SwitchedOff';
import switchedOn from '@salesforce/label/c.Connect_CampaignSync_SwitchedOn';
import counts from '@salesforce/label/c.Connect_CampaignSync_Counts';
import noCampaignAccess from '@salesforce/label/c.Connect_CampaignSync_NoCampaignAccess';
import noManagePermission from '@salesforce/label/c.Connect_CampaignSync_NoManagePermission';
import syncAllLabel from '@salesforce/label/c.Connect_CampaignSync_SyncAll';
import running from '@salesforce/label/c.Connect_CampaignSync_Running';
import errorFailed from '@salesforce/label/c.Connect_CampaignSync_ErrorFailed';

/**
 * The Campaign sync page (feature X-02). The controller decides what the org and the person
 * allow and refuses in words; the page shows the state, the counts, and the one button.
 */
export default class CampaignSync extends LightningElement {
  labels = {
    title,
    intro,
    unavailable,
    switchedOff,
    switchedOn,
    noCampaignAccess,
    noManagePermission,
    syncAll: syncAllLabel,
    running
  };

  status;
  working = false;
  error;

  connectedCallback() {
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

  get unavailableShown() {
    return this.loaded && !this.status.available;
  }

  get offShown() {
    return this.loaded && this.status.available && !this.status.switchedOn;
  }

  get onShown() {
    return this.loaded && this.status.available && this.status.switchedOn;
  }

  get countsText() {
    if (!this.loaded || this.status.linkedCount == null || this.status.appealCount == null) {
      return undefined;
    }
    const linked = `${this.status.linkedCount}${this.status.linkedCountCapped ? '+' : ''}`;
    const appeals = `${this.status.appealCount}${this.status.appealCountCapped ? '+' : ''}`;
    return counts.replace('{0}', linked).replace('{1}', appeals);
  }

  get noAccessShown() {
    return this.onShown && !this.status.canSync;
  }

  get noManageShown() {
    return this.onShown && !this.status.canManage;
  }

  get runningShown() {
    return this.onShown && this.status.running;
  }

  get syncDisabled() {
    return (
      this.working ||
      !this.onShown ||
      !this.status.canSync ||
      !this.status.canManage ||
      this.status.running
    );
  }

  async handleSyncAll() {
    this.error = undefined;
    this.working = true;
    try {
      this.status = await syncAll();
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  messageOf(failure) {
    return (failure && failure.body && failure.body.message) || errorFailed;
  }
}
