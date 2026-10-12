// SPIKE (rollup slice S15). Proves the deploy starts from a Lightning context. Not for the product:
// strings are not labels, and the outcome is read from the debug log or `sf project deploy report`.
import { LightningElement } from 'lwc';
import start from '@salesforce/apex/S15SpikeSelfDeploy.start';

export default class S15SpikeDeploy extends LightningElement {
  objectApiName = '';
  checkOnly = true;
  busy = false;
  message = '';

  handleChange(event) {
    this.objectApiName = event.target.value;
  }

  handleCheck(event) {
    this.checkOnly = event.target.checked;
  }

  async handleDeploy() {
    this.busy = true;
    try {
      const jobId = await start({ objectApiName: this.objectApiName, checkOnly: this.checkOnly });
      this.message = `Deploy job queued: ${jobId}`;
    } catch (error) {
      this.message = error?.body?.message || 'The deploy could not start.';
    } finally {
      this.busy = false;
    }
  }
}
