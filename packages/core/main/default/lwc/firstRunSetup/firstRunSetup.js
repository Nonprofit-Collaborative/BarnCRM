import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { RefreshEvent } from 'lightning/refresh';
import FirstRunModal from 'c/firstRunModal';
import getSettingsLink from '@salesforce/apex/SettingsController.getSettingsLink';
import getState from '@salesforce/apex/FirstRunController.getState';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_UnexpectedError';
import TITLE from '@salesforce/label/c.Core_FirstRun_Title';

const GENERAL_SECTION = 'General';

/**
 * First-run setup (ADR-0124) on BarnCRM Home and BarnCRM Settings: while setup is unfinished
 * (the server decides; a saved edition is pre-selected) it opens c/firstRunModal, a platform
 * modal that cannot be dismissed. When an administrator finishes, it fires `setupfinished`
 * for the page it sits in, asks the page to refresh (so an open Setup Checklist shows the
 * edition as answered and never asks it again), and lands on General. It installs no module.
 */
export default class FirstRunSetup extends NavigationMixin(LightningElement) {
  loadError;

  async connectedCallback() {
    let state;
    try {
      state = await getState();
    } catch (error) {
      // A page that cannot tell is not blocked (the window shows only when setup is known to
      // be unfinished), but it says so above the page rather than failing silently.
      this.loadError = messageOf(error);
      return;
    }
    if (!state || !state.needsSetup) {
      return;
    }
    // disableClose is given at open, not only set inside the modal: only then does the
    // platform disable its close button too, so an administrator never meets an X that
    // silently does nothing. Someone who cannot finish may close it.
    const result = await FirstRunModal.open({
      size: 'small',
      label: TITLE,
      state,
      disableClose: Boolean(state.canFinish)
    });
    if (result && result.finished) {
      await this.afterFinish();
    }
  }

  async afterFinish() {
    this.dispatchEvent(new CustomEvent('setupfinished'));
    this.dispatchEvent(new RefreshEvent());
    try {
      // The tab and the section key are qualified for the org's namespace in Apex.
      const link = await getSettingsLink();
      this[NavigationMixin.Navigate]({
        type: 'standard__navItemPage',
        attributes: { apiName: link.tabApiName },
        state: { [link.sectionKey]: GENERAL_SECTION }
      });
    } catch (error) {
      this.loadError = messageOf(error);
    }
  }
}

function messageOf(error) {
  return (
    (error && error.body && error.body.message) || (error && error.message) || UNEXPECTED_ERROR
  );
}
