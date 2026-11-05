import { LightningElement } from 'lwc';
import getWhatsNew from '@salesforce/apex/WhatsNewController.getWhatsNew';
import dismiss from '@salesforce/apex/WhatsNewController.dismiss';

import TITLE from '@salesforce/label/c.Core_WhatsNew_Title';
import VERSION from '@salesforce/label/c.Core_WhatsNew_Version';
import DISMISS from '@salesforce/label/c.Core_WhatsNew_Dismiss';
import { helpText, isHelpLoaded, loadHelp } from 'c/barnHelpText';

export default class WhatsNew extends LightningElement {
  helpReady = isHelpLoaded('Core');

  labels = {
    title: TITLE,
    get intro() {
      return helpText('Core', 'Core_WhatsNew_Intro');
    },
    dismiss: DISMISS
  };

  releases = [];
  errorMessage;
  busy = false;

  connectedCallback() {
    if (!this.helpReady) {
      loadHelp('Core').then(() => {
        this.helpReady = true;
      });
    }
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
        this.errorMessage =
          error && error.body && error.body.message
            ? error.body.message
            : helpText('Core', 'Core_WhatsNew_Failed');
      })
      .finally(() => {
        this.busy = false;
      });
  }
}
