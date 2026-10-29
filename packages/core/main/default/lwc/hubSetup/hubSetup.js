import { LightningElement, api, wire } from 'lwc';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import CHECKLIST_HEADING from '@salesforce/label/c.Core_HubHome_ChecklistHeading';
import SETUP_COMPLETE_HEADING from '@salesforce/label/c.Core_SetupAssistant_CompleteTileHeading';
import REOPEN_SETUP from '@salesforce/label/c.Core_SetupAssistant_ReopenButton';
import PROGRESS_FORMAT from '@salesforce/label/c.Core_SetupAssistant_ProgressFormat';

/**
 * The setup checklist on the BarnCRM home page: the Setup Assistant until setup is finished,
 * then a small Setup complete tile one click from reopening it. The assistant loads its own
 * steps, so a home model that fails to load still leaves the checklist working.
 *
 * Nothing is shown until the home model answers, so a finished setup (the everyday case) goes
 * straight to the tile and the assistant never works its steps out a second time (ADMIN-10).
 *
 * The home page places it twice: in the side column (placement Side) and at the top of the
 * main column (placement Top). On a wide screen only the side one shows. On a narrow screen,
 * where the columns stack and the side column comes last, the top one shows while setup is
 * unfinished, so an administrator's main task comes first; once setup was finished, the side
 * one shows the small tile at the bottom as before.
 */
const NARROW = '(max-width: 47.9375em)';
const TOP = 'Top';

export default class HubSetup extends LightningElement {
  /** Where the home page put this instance: Side (the default) or Top. */
  @api placement = 'Side';

  labels = {
    checklistHeading: CHECKLIST_HEADING,
    setupCompleteHeading: SETUP_COMPLETE_HEADING,
    reopenSetup: REOPEN_SETUP
  };

  stepsCompleted = 0;
  stepsTotal = 0;
  setupReopened = false;
  modelAnswered = false;
  /** Whether setup was finished when the page loaded, which decides the placement used. */
  startedComplete = false;
  narrow = false;

  @wire(getHomeModel)
  wiredModel({ data, error }) {
    if (data) {
      this.stepsCompleted = data.stepsCompleted || 0;
      this.stepsTotal = data.stepsTotal || 0;
    }
    if ((data || error) && !this.modelAnswered) {
      this.startedComplete = this.setupComplete;
    }
    if (data || error) {
      this.modelAnswered = true;
    }
  }

  connectedCallback() {
    // A browser without matchMedia is treated as wide: the side column shows, as before.
    if (typeof window !== 'undefined' && typeof window.matchMedia === 'function') {
      this.media = window.matchMedia(NARROW);
      this.narrow = this.media.matches;
      this.onMediaChange = (event) => {
        this.narrow = event.matches;
      };
      this.media.addEventListener('change', this.onMediaChange);
    }
  }

  disconnectedCallback() {
    if (this.media) {
      this.media.removeEventListener('change', this.onMediaChange);
    }
  }

  /** This instance shows: the side one on a wide screen, and on a narrow one as above. */
  get shown() {
    if (!this.modelAnswered) {
      return false;
    }
    const top = this.placement === TOP;
    if (!this.narrow) {
      return !top;
    }
    return top ? !this.startedComplete : this.startedComplete;
  }

  get setupComplete() {
    return this.stepsTotal > 0 && this.stepsCompleted === this.stepsTotal;
  }

  /** The assistant is the main panel until it is finished, and one click away after that. */
  get showAssistant() {
    return this.setupReopened || !this.setupComplete;
  }

  // The same translatable sentence the assistant shows, from the same label.
  get setupProgressText() {
    return PROGRESS_FORMAT.replace('{0}', this.stepsCompleted).replace('{1}', this.stepsTotal);
  }

  /** The assistant reports its own progress, so the tile collapses without reloading. */
  handleSetupChanged(event) {
    this.stepsCompleted = event.detail.stepsCompleted || 0;
    this.stepsTotal = event.detail.stepsTotal || 0;
    if (!event.detail.isComplete) {
      this.setupReopened = false;
    }
  }

  handleReopenSetup() {
    this.setupReopened = true;
  }
}
