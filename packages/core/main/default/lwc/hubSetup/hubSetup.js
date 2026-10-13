import { LightningElement, wire } from 'lwc';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import CHECKLIST_HEADING from '@salesforce/label/c.Core_HubHome_ChecklistHeading';
import SETUP_COMPLETE_HEADING from '@salesforce/label/c.Core_SetupAssistant_CompleteTileHeading';
import REOPEN_SETUP from '@salesforce/label/c.Core_SetupAssistant_ReopenButton';
import PROGRESS_FORMAT from '@salesforce/label/c.Core_SetupAssistant_ProgressFormat';

/**
 * The setup checklist on the BarnCRM home page: the Setup Assistant until setup is finished,
 * then a small Setup complete tile one click from reopening it. The assistant loads its own
 * steps, so a home model that fails to load still leaves the checklist working.
 */
export default class HubSetup extends LightningElement {
  labels = {
    checklistHeading: CHECKLIST_HEADING,
    setupCompleteHeading: SETUP_COMPLETE_HEADING,
    reopenSetup: REOPEN_SETUP
  };

  stepsCompleted = 0;
  stepsTotal = 0;
  setupReopened = false;

  @wire(getHomeModel)
  wiredModel({ data }) {
    if (data) {
      this.stepsCompleted = data.stepsCompleted || 0;
      this.stepsTotal = data.stepsTotal || 0;
    }
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
