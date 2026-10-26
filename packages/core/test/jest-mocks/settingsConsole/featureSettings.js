import { LightningElement, api } from 'lwc';

// Stands in for c/featureSettings in the settings console tests. It counts refresh() calls, the
// way the real panel re-reads its data when the console asks after first-run setup.
export default class FeatureSettings extends LightningElement {
  static refreshCount = 0;

  @api
  refresh() {
    FeatureSettings.refreshCount += 1;
  }
}
