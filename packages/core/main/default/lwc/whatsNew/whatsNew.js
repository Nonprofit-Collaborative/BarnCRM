import { LightningElement } from 'lwc';
import getWhatsNew from '@salesforce/apex/WhatsNewController.getWhatsNew';
import dismiss from '@salesforce/apex/WhatsNewController.dismiss';

import TITLE from '@salesforce/label/c.Core_WhatsNew_Title';
import INTRO from '@salesforce/label/c.Core_WhatsNew_Intro';
import VERSION from '@salesforce/label/c.Core_WhatsNew_Version';
import DISMISS from '@salesforce/label/c.Core_WhatsNew_Dismiss';
import FAILED from '@salesforce/label/c.Core_WhatsNew_Failed';

export default class WhatsNew extends LightningElement {
  labels = { title: TITLE, intro: INTRO, dismiss: DISMISS };

  releases = [];
  errorMessage;
  busy = false;

  connectedCallback() {
    // A card that cannot load shows nothing: the controller has already logged why.
    return getWhatsNew()
      .then((releases) => {
        this.releases = (releases || []).map((release) => ({
          ...release,
          heading: VERSION.replace('{0}', release.version)
        }));
      })
      .catch(() => {
        this.releases = [];
      });
  }

  get hasReleases() {
    return this.releases.length > 0;
  }

  handleDismiss() {
    this.busy = true;
    this.errorMessage = undefined;
    return dismiss()
      .then(() => {
        this.releases = [];
      })
      .catch((error) => {
        this.errorMessage = error && error.body && error.body.message ? error.body.message : FAILED;
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
